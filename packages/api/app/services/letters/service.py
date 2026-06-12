"""Service Lettres du Facteur — auto-détection actions + chaînage.

`get_user_letters` est idempotent : `_ensure_rows` initialise les rows
manquantes (user nouveau OU user existant après ajout de lettres au catalogue)
puis on retourne l'état complet (en rafraîchissant la lettre active pour
propager les actions déjà accomplies).

`refresh_letter_status` recalcule les détecteurs pour une lettre donnée et,
si elle est complète, l'archive et déverrouille la suivante.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

import structlog
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.analytics import AnalyticsEvent
from app.models.collection import Collection, CollectionItem
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, SourceType
from app.models.source import Source, UserSource
from app.models.user_letter_progress import UserLetterProgress
from app.models.user_personalization import UserPersonalization
from app.models.user_topic_profile import UserTopicProfile
from app.models.veille import VeilleConfig
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
    """≥2 user_sources ajoutées après le démarrage de la Lettre 1.

    Compte toute association (curée OU custom) ajoutée après que l'utilisateur
    soit entré dans la Lettre 1, pour valider l'effort post-onboarding sans
    dépendre du flag is_custom (qui ne couvre que les ajouts par URL libre).
    """
    started_at = await db.scalar(
        select(UserLetterProgress.started_at).where(
            UserLetterProgress.user_id == user_id,
            UserLetterProgress.letter_id == "letter_1",
        )
    )
    if started_at is None:
        return False
    count = await db.scalar(
        select(func.count())
        .select_from(UserSource)
        .where(
            UserSource.user_id == user_id,
            UserSource.added_at >= started_at,
        )
    )
    return (count or 0) >= 2


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


def _count_event_detector(event_type: str, threshold: int):
    async def _detect(user_id: UUID, db: AsyncSession) -> bool:
        stmt = (
            select(func.count())
            .select_from(AnalyticsEvent)
            .where(
                AnalyticsEvent.user_id == user_id,
                AnalyticsEvent.event_type == event_type,
            )
        )
        return ((await db.execute(stmt)).scalar() or 0) >= threshold

    return _detect


_detect_first_perspectives_open = _first_event_detector("perspectives_opened")
_detect_read_first_essentiel = _first_event_detector("digest_opened")
_detect_read_first_bonnes_nouvelles = _first_event_detector("bonnes_nouvelles_opened")
_detect_open_10_perspectives = _count_event_detector("perspectives_opened", 10)
_detect_give_app_feedback = _first_event_detector("app_feedback_opened")


async def _count_read_articles(user_id: UUID, db: AsyncSession) -> int:
    """Articles distincts avec un signal minimal d'interaction."""
    stmt = (
        select(func.count(func.distinct(UserContentStatus.content_id)))
        .select_from(UserContentStatus)
        .join(Content, Content.id == UserContentStatus.content_id)
        .where(
            UserContentStatus.user_id == user_id,
            Content.content_type == ContentType.ARTICLE,
            or_(
                UserContentStatus.time_spent_seconds > 0,
                UserContentStatus.reading_progress > 0,
                UserContentStatus.status.in_(
                    [ContentStatus.SEEN, ContentStatus.CONSUMED]
                ),
                UserContentStatus.seen_at.is_not(None),
            ),
        )
    )
    return (await db.execute(stmt)).scalar() or 0


async def _detect_read_3_long_articles(user_id: UUID, db: AsyncSession) -> bool:
    """≥10 articles distincts avec un signal minimal d'interaction."""
    return await _count_read_articles(user_id, db) >= 10


async def _detect_read_50_articles(user_id: UUID, db: AsyncSession) -> bool:
    """≥50 articles distincts avec un signal minimal d'interaction."""
    return await _count_read_articles(user_id, db) >= 50


async def _detect_read_first_video_podcast(user_id: UUID, db: AsyncSession) -> bool:
    """≥3 articles distincts ajoutés dans des collections utilisateur non likées."""
    stmt = (
        select(func.count(func.distinct(CollectionItem.content_id)))
        .select_from(CollectionItem)
        .join(Collection, Collection.id == CollectionItem.collection_id)
        .join(Content, Content.id == CollectionItem.content_id)
        .where(
            Collection.user_id == user_id,
            Collection.is_liked_collection.is_(False),
            Content.content_type == ContentType.ARTICLE,
        )
    )
    return ((await db.execute(stmt)).scalar() or 0) >= 3


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


async def _detect_create_first_veille(user_id: UUID, db: AsyncSession) -> bool:
    """≥1 veille_config, quel que soit son statut (pauser ou supprimer la
    veille ne dé-complète pas l'action)."""
    stmt = select(VeilleConfig.id).where(VeilleConfig.user_id == user_id).limit(1)
    return (await db.execute(stmt)).scalar() is not None


async def _detect_save_5_articles(user_id: UUID, db: AsyncSession) -> bool:
    """≥5 UserContentStatus avec is_saved=True."""
    stmt = (
        select(func.count())
        .select_from(UserContentStatus)
        .where(
            UserContentStatus.user_id == user_id,
            UserContentStatus.is_saved.is_(True),
        )
    )
    return ((await db.execute(stmt)).scalar() or 0) >= 5


async def _detect_write_first_note(user_id: UUID, db: AsyncSession) -> bool:
    """≥1 note non vide (trim) sur un article sauvegardé."""
    stmt = (
        select(UserContentStatus.id)
        .where(
            UserContentStatus.user_id == user_id,
            UserContentStatus.is_saved.is_(True),
            UserContentStatus.note_text.is_not(None),
            func.length(func.trim(UserContentStatus.note_text)) > 0,
        )
        .limit(1)
    )
    return (await db.execute(stmt)).scalar() is not None


async def _detect_mute_3_sources(user_id: UUID, db: AsyncSession) -> bool:
    """≥3 sources masquées (UserPersonalization.muted_sources)."""
    count = await db.scalar(
        select(func.cardinality(UserPersonalization.muted_sources)).where(
            UserPersonalization.user_id == user_id
        )
    )
    return (count or 0) >= 3


async def _detect_add_5_youtube_channels(user_id: UUID, db: AsyncSession) -> bool:
    """≥5 user_sources pointant vers une source de type YouTube."""
    stmt = (
        select(func.count())
        .select_from(UserSource)
        .join(Source, Source.id == UserSource.source_id)
        .where(
            UserSource.user_id == user_id,
            Source.type == SourceType.YOUTUBE,
        )
    )
    return ((await db.execute(stmt)).scalar() or 0) >= 5


async def _detect_recommend_10_articles(user_id: UUID, db: AsyncSession) -> bool:
    """≥10 UserContentStatus avec is_liked=True."""
    stmt = (
        select(func.count())
        .select_from(UserContentStatus)
        .where(
            UserContentStatus.user_id == user_id,
            UserContentStatus.is_liked.is_(True),
        )
    )
    return ((await db.execute(stmt)).scalar() or 0) >= 10


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
    "create_first_veille": _detect_create_first_veille,
    "save_5_articles": _detect_save_5_articles,
    "write_first_note": _detect_write_first_note,
    "mute_3_sources": _detect_mute_3_sources,
    "add_5_youtube_channels": _detect_add_5_youtube_channels,
    "read_50_articles": _detect_read_50_articles,
    "recommend_10_articles": _detect_recommend_10_articles,
    "open_10_perspectives": _detect_open_10_perspectives,
    "give_app_feedback": _detect_give_app_feedback,
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
            for k in ("id", "label", "help", "completion_palier", "target_route")
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
    """Crée toutes les rows initiales pour un nouveau user."""
    from app.services.user_service import UserService

    await UserService(db).get_or_create_profile(str(user_id))
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


async def _ensure_rows(
    user_id: UUID, db: AsyncSession
) -> dict[str, UserLetterProgress]:
    """Garantit une row par lettre du catalogue. Idempotent, read-mostly.

    - Aucune row → init complet (nouveau user).
    - Rows partielles (lettres ajoutées au catalogue après coup) → backfill
      des manquantes en `upcoming`.
    - Réactivation de chaîne : si aucune lettre n'est active et que toutes
      les lettres précédant la première `upcoming` sont archivées, on active
      cette première `upcoming` (couvre le user qui avait fini la dernière
      lettre avant l'extension du catalogue).
    - Commit seulement si quelque chose a changé.
    """
    rows = await _get_rows(user_id, db)
    if not rows:
        await _init_progress(user_id, db)
        return await _get_rows(user_id, db)

    changed = False
    now = datetime.now(UTC)
    for catalog in LETTERS_ORDER:
        if catalog["id"] in rows:
            continue
        row = UserLetterProgress(
            user_id=user_id,
            letter_id=catalog["id"],
            status="upcoming",
            completed_actions=[],
        )
        db.add(row)
        rows[catalog["id"]] = row
        changed = True

    has_active = any(r.status == "active" for r in rows.values())
    if not has_active:
        for catalog in LETTERS_ORDER:
            row = rows[catalog["id"]]
            if row.status == "archived":
                continue
            if row.status == "upcoming":
                row.status = "active"
                row.started_at = now
                row.updated_at = now
                changed = True
            break

    if changed:
        await db.commit()
        rows = await _get_rows(user_id, db)
    return rows


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
    rows = await _ensure_rows(user_id, db)
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
    """Retourne toutes les lettres du catalogue avec leur état courant.

    `_ensure_rows` initialise ou complète les rows manquantes (nouveau user
    ou lettres ajoutées au catalogue après coup)."""
    rows = await _ensure_rows(user_id, db)

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
