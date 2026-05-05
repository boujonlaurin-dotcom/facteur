"""Service Lettres du Facteur — auto-détection actions + chaînage.

`get_user_letters` est idempotent : si l'utilisateur n'a pas encore de rows,
on initialise les 3 lettres en base puis on retourne l'état complet (en
rafraîchissant la lettre active pour propager les actions déjà accomplies).

`refresh_letter_status` recalcule les détecteurs pour une lettre donnée et,
si elle est complète, l'archive et déverrouille la suivante.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

import structlog
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.analytics import AnalyticsEvent
from app.models.content import Content, UserContentStatus
from app.models.source import UserSource
from app.models.user_letter_progress import UserLetterProgress
from app.models.user_topic_profile import UserTopicProfile
from app.services.letters.catalog import (
    LETTERS_BY_ID,
    LETTERS_ORDER,
)

logger = structlog.get_logger(__name__)


# ─── Détecteurs ────────────────────────────────────────────────────────────


async def _detect_define_editorial_line(user_id: UUID, db: AsyncSession) -> bool:
    """≥3 centres d'intérêt via UserTopicProfile (custom topics, Epic 11)."""
    stmt = (
        select(func.count())
        .select_from(UserTopicProfile)
        .where(UserTopicProfile.user_id == user_id)
    )
    return ((await db.execute(stmt)).scalar() or 0) >= 3


async def _detect_add_5_sources(user_id: UUID, db: AsyncSession) -> bool:
    """≥5 user_sources (toute association compte)."""
    stmt = (
        select(func.count())
        .select_from(UserSource)
        .where(UserSource.user_id == user_id)
    )
    return ((await db.execute(stmt)).scalar() or 0) >= 5


async def _detect_add_2_personal_sources(user_id: UUID, db: AsyncSession) -> bool:
    """≥2 user_sources avec is_custom=True."""
    stmt = (
        select(func.count())
        .select_from(UserSource)
        .where(UserSource.user_id == user_id, UserSource.is_custom.is_(True))
    )
    return ((await db.execute(stmt)).scalar() or 0) >= 2


def _first_event_detector(event_type: str):
    async def _detect(user_id: UUID, db: AsyncSession) -> bool:
        stmt = (
            select(AnalyticsEvent.id)
            .where(
                AnalyticsEvent.user_id == user_id,
                AnalyticsEvent.event_type == event_type,
            )
            .limit(1)
        )
        return (await db.execute(stmt)).scalar() is not None

    return _detect


_detect_first_perspectives_open = _first_event_detector("perspectives_opened")
_detect_read_first_essentiel = _first_event_detector("digest_opened")
_detect_read_first_bonnes_nouvelles = _first_event_detector("bonnes_nouvelles_opened")


async def _detect_read_3_long_articles(user_id: UUID, db: AsyncSession) -> bool:
    """≥3 contenus articles avec reading_progress≥90 et time_spent_seconds≥60."""
    stmt = (
        select(func.count(func.distinct(UserContentStatus.content_id)))
        .select_from(UserContentStatus)
        .join(Content, Content.id == UserContentStatus.content_id)
        .where(
            UserContentStatus.user_id == user_id,
            UserContentStatus.reading_progress >= 90,
            UserContentStatus.time_spent_seconds >= 60,
            Content.content_type == "article",
        )
    )
    return ((await db.execute(stmt)).scalar() or 0) >= 3


async def _detect_read_first_video_podcast(user_id: UUID, db: AsyncSession) -> bool:
    """Au moins un contenu podcast/youtube avec time_spent_seconds≥240."""
    stmt = (
        select(UserContentStatus.id)
        .join(Content, Content.id == UserContentStatus.content_id)
        .where(
            UserContentStatus.user_id == user_id,
            UserContentStatus.time_spent_seconds >= 240,
            Content.content_type.in_(["podcast", "youtube"]),
        )
        .limit(1)
    )
    return (await db.execute(stmt)).scalar() is not None


async def _detect_recommend_first_article(user_id: UUID, db: AsyncSession) -> bool:
    """Au moins un UserContentStatus avec is_liked=True."""
    stmt = (
        select(UserContentStatus.id)
        .where(
            UserContentStatus.user_id == user_id,
            UserContentStatus.is_liked.is_(True),
        )
        .limit(1)
    )
    return (await db.execute(stmt)).scalar() is not None


DETECTORS = {
    "define_editorial_line": _detect_define_editorial_line,
    "add_5_sources": _detect_add_5_sources,
    "add_2_personal_sources": _detect_add_2_personal_sources,
    "first_perspectives_open": _detect_first_perspectives_open,
    "read_first_essentiel": _detect_read_first_essentiel,
    "read_first_bonnes_nouvelles": _detect_read_first_bonnes_nouvelles,
    "read_3_long_articles": _detect_read_3_long_articles,
    "read_first_video_podcast": _detect_read_first_video_podcast,
    "recommend_first_article": _detect_recommend_first_article,
}


# ─── Helpers ───────────────────────────────────────────────────────────────


def _serialize(row: UserLetterProgress, catalog: dict) -> dict:
    """Compose la réponse JSON à partir de la row DB + des constantes."""
    actions = catalog["actions"]
    completed = list(row.completed_actions or [])
    progress = (
        len([a for a in actions if a["id"] in completed]) / len(actions)
        if actions
        else 1.0
    )
    serialized_actions = [
        {
            k: a[k]
            for k in ("id", "label", "help", "completion_palier")
            if k in a and a[k] is not None
        }
        for a in actions
    ]
    payload: dict = {
        "id": catalog["id"],
        "num": catalog["num"],
        "title": catalog["title"],
        "message": catalog["message"],
        "signature": catalog["signature"],
        "actions": serialized_actions,
        "status": row.status,
        "completed_actions": completed,
        "progress": round(progress, 4),
        "started_at": row.started_at.isoformat() if row.started_at else None,
        "archived_at": row.archived_at.isoformat() if row.archived_at else None,
    }
    if catalog.get("intro_palier"):
        payload["intro_palier"] = catalog["intro_palier"]
    if catalog.get("completion_voeu"):
        payload["completion_voeu"] = catalog["completion_voeu"]
    return payload


async def _get_rows(user_id: UUID, db: AsyncSession) -> dict[str, UserLetterProgress]:
    stmt = select(UserLetterProgress).where(UserLetterProgress.user_id == user_id)
    rows = (await db.execute(stmt)).scalars().all()
    return {row.letter_id: row for row in rows}


async def _init_progress(user_id: UUID, db: AsyncSession) -> None:
    """Crée les 3 rows initiales pour un nouveau user."""
    now = datetime.now(UTC)
    for catalog in LETTERS_ORDER:
        default_status = catalog["default_status"]
        row = UserLetterProgress(
            user_id=user_id,
            letter_id=catalog["id"],
            status=default_status,
            completed_actions=[],
            started_at=now if default_status == "active" else None,
            archived_at=now if default_status == "archived" else None,
        )
        db.add(row)
    await db.commit()


def _next_upcoming(
    rows: dict[str, UserLetterProgress], after_letter_id: str
) -> UserLetterProgress | None:
    """Cherche la prochaine lettre upcoming dans le dict déjà chargé."""
    order_ids = [letter["id"] for letter in LETTERS_ORDER]
    try:
        idx = order_ids.index(after_letter_id)
    except ValueError:
        return None
    for next_id in order_ids[idx + 1 :]:
        candidate = rows.get(next_id)
        if candidate is not None and candidate.status == "upcoming":
            return candidate
    return None


async def _recompute_completed(
    user_id: UUID, catalog: dict, db: AsyncSession
) -> list[str]:
    """Lance les détecteurs pour chaque action de la lettre."""
    completed: list[str] = []
    for action in catalog["actions"]:
        detector = DETECTORS.get(action["id"])
        if detector is None:
            continue
        try:
            if await detector(user_id, db):
                completed.append(action["id"])
        except Exception:
            logger.warning(
                "letter_detector_failed",
                user_id=str(user_id),
                action_id=action["id"],
                exc_info=True,
            )
    return completed


# ─── API publique ──────────────────────────────────────────────────────────


async def refresh_letter_status(
    user_id: UUID, letter_id: str, db: AsyncSession
) -> dict:
    """Recalcule les actions cochées + archive si terminée + déverrouille
    la suivante. Idempotent."""
    catalog = LETTERS_BY_ID[letter_id]
    rows = await _get_rows(user_id, db)
    if letter_id not in rows:
        # Init si jamais — peut arriver pour un user qui n'a pas appelé
        # GET /api/letters au préalable.
        await _init_progress(user_id, db)
        rows = await _get_rows(user_id, db)
    row = rows[letter_id]

    # Idempotence : une lettre archivée n'est jamais re-évaluée.
    if row.status == "archived":
        return _serialize(row, catalog)

    completed = await _recompute_completed(user_id, catalog, db)
    action_ids = [a["id"] for a in catalog["actions"]]
    merged = [a_id for a_id in action_ids if a_id in completed]
    now = datetime.now(UTC)
    if merged != list(row.completed_actions or []):
        row.completed_actions = merged
        row.updated_at = now

    if action_ids and len(merged) == len(action_ids) and row.status == "active":
        row.status = "archived"
        row.archived_at = now
        next_row = _next_upcoming(rows, letter_id)
        if next_row is not None:
            next_row.status = "active"
            next_row.started_at = now
            next_row.updated_at = now

    await db.commit()
    await db.refresh(row)
    return _serialize(row, catalog)


async def get_user_letters(user_id: UUID, db: AsyncSession) -> list[dict]:
    """Retourne les 3 lettres avec leur état courant. Init si pas de rows."""
    rows = await _get_rows(user_id, db)
    if not rows:
        await _init_progress(user_id, db)
        rows = await _get_rows(user_id, db)

    # Refresh la lettre active (s'il y en a une) pour propager les actions
    # accomplies hors de l'app (ex: user a ajouté des sources sans appeler
    # refresh-status explicitement).
    active_id = next(
        (lid for lid, r in rows.items() if r.status == "active"),
        None,
    )
    if active_id is not None:
        await refresh_letter_status(user_id, active_id, db)
        rows = await _get_rows(user_id, db)

    return [_serialize(rows[letter["id"]], letter) for letter in LETTERS_ORDER]
