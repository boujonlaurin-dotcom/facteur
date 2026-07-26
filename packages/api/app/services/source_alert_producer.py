"""Éligibilité « source rare » et production des alertes (Epic 30, story 30.2).

Une cloche ne peut être posée que sur une source qui publie **moins d'une fois
par semaine** : c'est ce qui rend la fonctionnalité insensible au spam par
construction. Le test d'éligibilité est rejoué à l'activation *et* au dispatch
(défense en profondeur : le profil affiché côté client peut être périmé).

Le calcul de fréquence est le pendant serveur de
`apps/mobile/lib/features/sources/utils/publication_frequency.dart` : même
fenêtre de 30 jours clampée à l'âge réel de la source, pour ne pas classer
« rare » une source qui vient d'être ingérée.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.enums import InterestState
from app.models.source import Source, UserSource

#: Une alerte ne se pose que sur une source sous ce rythme (articles / semaine).
RARE_MAX_PER_WEEK = 1.0
#: Fenêtre de comptage, en jours, avant clamp sur l'âge réel de la source.
FREQUENCY_WINDOW_DAYS = 30
#: Fenêtre de fraîcheur d'un contenu pour déclencher une alerte.
ALERT_LOOKBACK = timedelta(hours=24)
#: Plafond de cloches actives par utilisateur.
ALERT_CAP = 5

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


def _per_day(
    articles_30d: int, oldest_content_at: datetime | None, now: datetime
) -> float:
    window_days = FREQUENCY_WINDOW_DAYS
    if oldest_content_at is not None:
        age_days = (now - oldest_content_at).days
        window_days = min(max(age_days, 1), FREQUENCY_WINDOW_DAYS)
    return articles_30d / window_days


def is_rare_source(
    articles_30d: int, oldest_content_at: datetime | None, now: datetime
) -> bool:
    """Une source est « rare » si elle publie moins d'une fois par semaine.

    `articles_30d == 0` n'est **pas** éligible : sans preuve qu'elle publie
    (source morte, flux cassé), la cloche ne sonnerait jamais — poser une
    alerte dessus serait une promesse vide.
    """
    if articles_30d < 1:
        return False
    return _per_day(articles_30d, oldest_content_at, now) * 7 < RARE_MAX_PER_WEEK


def rarity_phrase(
    articles_30d: int, oldest_content_at: datetime | None, now: datetime
) -> str:
    """Phrase de rareté pour le bigText — dérivée des mêmes seuils.

    Jamais une affirmation que les chiffres ne soutiennent pas : la borne
    d'éligibilité (< 1/semaine) garantit qu'on reste sur « deux semaines » ou
    « mois ».
    """
    per_week = _per_day(articles_30d, oldest_content_at, now) * 7
    if per_week >= 0.5:
        return "Ça n'arrive qu'une fois toutes les deux semaines."
    return "Ça n'arrive qu'une fois par mois."


async def count_active_alerts(session: AsyncSession, *, user_id: UUID) -> int:
    """Nombre de cloches actives sur des sources toujours suivies."""
    return (
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


async def source_frequency_stats(
    session: AsyncSession, *, source_id: UUID, now: datetime
) -> tuple[int, datetime | None]:
    """`(articles_30d, oldest_content_at)` — les deux entrées de `is_rare_source`.

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
    session: AsyncSession, *, user_id: UUID, now: datetime
) -> list[SourceAlertCandidate]:
    """Contenus frais (< 24 h) des sources sous cloche, une alerte par source.

    `DISTINCT ON (source_id)` : si une source rare publie deux articles dans la
    même journée, on n'annonce que le plus récent — une info, une notif.
    """
    since = now - ALERT_LOOKBACK
    rows = (
        await session.execute(
            select(
                Content.id,
                Content.title,
                Content.published_at,
                Source.id.label("source_id"),
                Source.name.label("source_name"),
            )
            .join(Source, Source.id == Content.source_id)
            .join(UserSource, UserSource.source_id == Content.source_id)
            .where(
                UserSource.user_id == user_id,
                UserSource.notify.is_(True),
                UserSource.state.in_(FOLLOWED_SOURCE_STATES),
                Content.published_at >= since,
                Content.published_at <= now,
            )
            .distinct(Source.id)
            .order_by(Source.id, Content.published_at.desc())
        )
    ).all()

    candidates: list[SourceAlertCandidate] = []
    for row in rows:
        # Rareté rejouée ici : la cloche a pu être posée quand la source était
        # calme, et la source s'être mise à publier tous les jours depuis.
        articles_30d, oldest_content_at = await source_frequency_stats(
            session, source_id=row.source_id, now=now
        )
        if not is_rare_source(articles_30d, oldest_content_at, now):
            continue
        candidates.append(
            SourceAlertCandidate(
                source_id=row.source_id,
                source_name=row.source_name,
                content_id=row.id,
                content_title=row.title,
                published_at=row.published_at,
                articles_30d=articles_30d,
                oldest_content_at=oldest_content_at,
            )
        )
    return candidates
