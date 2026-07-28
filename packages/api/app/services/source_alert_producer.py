"""Production des alertes source (Epic 30, stories 30.2 puis 30.3 « alertes v2 »).

La v1 conditionnait la cloche à la rareté de la source. La v2 lève ce gate :
n'importe quelle source suivie est éligible, et le bruit se règle par un
**mode filtré** (`user_sources.notify_filtered`) plutôt que par une
interdiction. Deux régimes de production, donc :

- **toutes les parutions** — une alerte par source et par passe, le contenu le
  plus récent des dernières 24 h (`DISTINCT ON (source_id)`) ;
- **filtré** — tous les contenus < 24 h de la source sont scorés avec le même
  scoring que le blend live de l'Essentiel, et seul le meilleur part. La
  contrainte d'unicité `(device_id, target_date, kind)` de `push_deliveries`
  fait le reste : au plus 1 alerte par jour et par source.

Le calcul de fréquence vit dans `services/alert_cadence.py`, partagé avec le
producteur sujet et miroir de
`apps/mobile/lib/features/sources/utils/publication_frequency.dart`.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content
from app.models.enums import InterestState
from app.models.source import Source, UserSource
from app.models.user_topic_profile import UserTopicProfile
from app.services.alert_cadence import (
    ALERT_CAP,
    ALERT_LOOKBACK,
    FREQUENCY_WINDOW_DAYS,
    NOISY_PER_WEEK,
    cadence_per_week,
    cadence_phrase,
    is_noisy,
)
from app.services.essentiel_service import (
    EssentielUserContext,
    _score_live_candidate,
    fetch_user_essentiel_context,
)

__all__ = [
    "ALERT_CAP",
    "ALERT_LOOKBACK",
    "ANALYTICS_KIND",
    "FOLLOWED_SOURCE_STATES",
    "FREQUENCY_WINDOW_DAYS",
    "NOISY_PER_WEEK",
    "SourceAlertCandidate",
    "cadence_per_week",
    "cadence_phrase",
    "count_active_alerts",
    "find_source_alert_candidates",
    "is_noisy",
    "source_alert_kind",
    "source_frequency_stats",
]

FOLLOWED_SOURCE_STATES = (InterestState.FOLLOWED, InterestState.FAVORITE)

_KIND_PREFIX = "source_alert"
#: `kind` propre, utilisé pour les analytics (le `kind` stocké porte la source).
ANALYTICS_KIND = _KIND_PREFIX


@dataclass(frozen=True)
class SourceAlertCandidate:
    """Un contenu frais d'une source sur laquelle l'utilisateur a une cloche."""

    source_id: UUID
    source_name: str
    content_id: UUID
    content_title: str
    published_at: datetime
    articles_30d: int
    oldest_content_at: datetime | None


def source_alert_kind(source_id: UUID) -> str:
    """`kind` de livraison porteur de la source.

    `push_deliveries` est unique par `(device_id, target_date, kind)` : deux
    cloches déclenchées le même jour entreraient en collision si elles
    partageaient un `kind` constant. Élargir la contrainte n'étant pas
    expand-contract safe (DB partagée staging/prod), c'est le `kind` qui porte
    la source. 29 caractères, donc dans le `String(32)` de la colonne.
    """
    return f"{_KIND_PREFIX}:{source_id.hex[:16]}"


async def count_active_alerts(session: AsyncSession, *, user_id: UUID) -> int:
    """Cloches actives, **toutes familles confondues** (sources + sujets).

    Le plafond de 5 est un budget d'attention, pas un quota par écran : une
    cloche sur un sujet coûte autant qu'une cloche sur une source.
    """
    sources = (
        await session.execute(
            select(func.count())
            .select_from(UserSource)
            .where(
                UserSource.user_id == user_id,
                UserSource.notify.is_(True),
                UserSource.state.in_(FOLLOWED_SOURCE_STATES),
            )
        )
    ).scalar_one()
    topics = (
        await session.execute(
            select(func.count())
            .select_from(UserTopicProfile)
            .where(
                UserTopicProfile.user_id == user_id,
                UserTopicProfile.notify.is_(True),
                UserTopicProfile.state.in_(FOLLOWED_SOURCE_STATES),
            )
        )
    ).scalar_one()
    return sources + topics


async def source_frequency_stats(
    session: AsyncSession, *, source_id: UUID, now: datetime
) -> tuple[int, datetime | None]:
    """`(articles_30d, oldest_content_at)` — les deux entrées de la cadence.

    Un seul aller-retour : le compte 30 j est un `COUNT(*) FILTER` sur la fenêtre,
    la plus ancienne parution un `MIN` sur tout l'historique de la source.
    """
    window_start = now - timedelta(days=FREQUENCY_WINDOW_DAYS)
    articles_30d, oldest_content_at = (
        await session.execute(
            select(
                func.count().filter(Content.published_at >= window_start),
                func.min(Content.published_at),
            ).where(Content.source_id == source_id)
        )
    ).one()
    return articles_30d, oldest_content_at


async def find_source_alert_candidates(
    session: AsyncSession,
    *,
    user_id: UUID,
    now: datetime,
    ctx: EssentielUserContext | None = None,
) -> list[SourceAlertCandidate]:
    """Contenus frais (< 24 h) des sources sous cloche, une alerte par source.

    En mode « toutes les parutions », c'est l'article le plus récent ; en mode
    filtré, le mieux scoré pour cet utilisateur. Dans les deux cas une seule
    alerte par source et par passe — une info, une notif.

    `ctx` (contexte de scoring Essentiel) n'est chargé que si au moins une
    source est en mode filtré : le régime par défaut n'en a pas besoin.
    """
    since = now - ALERT_LOOKBACK
    rows = (
        await session.execute(
            select(Content, UserSource.notify_filtered)
            .options(selectinload(Content.source))
            .join(Source, Source.id == Content.source_id)
            .join(UserSource, UserSource.source_id == Content.source_id)
            .where(
                UserSource.user_id == user_id,
                UserSource.notify.is_(True),
                UserSource.state.in_(FOLLOWED_SOURCE_STATES),
                Content.published_at >= since,
                Content.published_at <= now,
            )
            .order_by(Source.id, Content.published_at.desc())
        )
    ).all()
    if not rows:
        return []

    # Regroupement par source, en mémoire : les contenus frais d'un utilisateur
    # sous cloche se comptent en dizaines, et le mode filtré a besoin de tout
    # le lot pour choisir.
    by_source: dict[UUID, tuple[bool, list[Content]]] = {}
    for content, notify_filtered in rows:
        entry = by_source.setdefault(content.source_id, (notify_filtered is True, []))
        entry[1].append(content)

    if ctx is None and any(filtered for filtered, _ in by_source.values()):
        ctx = await fetch_user_essentiel_context(session, user_id)

    candidates: list[SourceAlertCandidate] = []
    for source_id, (filtered, contents) in by_source.items():
        if filtered:
            scoring_ctx = ctx or EssentielUserContext()
            best = max(
                contents,
                key=lambda c: (_score_live_candidate(c, scoring_ctx), c.published_at),
            )
        else:
            best = max(contents, key=lambda c: c.published_at)

        articles_30d, oldest_content_at = await source_frequency_stats(
            session, source_id=source_id, now=now
        )
        candidates.append(
            SourceAlertCandidate(
                source_id=source_id,
                source_name=best.source.name,
                content_id=best.id,
                content_title=best.title,
                published_at=best.published_at,
                articles_30d=articles_30d,
                oldest_content_at=oldest_content_at,
            )
        )
    return candidates
