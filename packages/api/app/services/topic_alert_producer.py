"""Production des alertes sujet (Epic 30, story 30.3 « alertes v2 »).

Miroir du producteur source : mêmes deux régimes (toutes les parutions /
filtré 1 par jour), même cadence, même plafond partagé. La seule vraie
différence est le **prédicat de match** : un sujet n'a pas de `source_id`, il
se reconnaît à son entité canonique ou à ses mots-clés.

⚠️ Le thème parent (`slug_parent`) n'entre **pas** dans le prédicat. C'est
volontaire : « politique » ou « sport » ramènerait des centaines d'articles par
jour et transformerait la cloche en robinet. Même raisonnement que
`_matched_axes` (`services/veille/feed_filter.py`), où le thème n'est jamais un
axe qualifiant.
"""

import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content
from app.models.enums import InterestState
from app.models.user_topic_profile import UserTopicProfile
from app.services.alert_cadence import (
    ALERT_LOOKBACK,
    FREQUENCY_WINDOW_DAYS,
)
from app.services.essentiel_service import (
    EssentielUserContext,
    _score_live_candidate,
    fetch_user_essentiel_context,
)

FOLLOWED_TOPIC_STATES = (InterestState.FOLLOWED, InterestState.FAVORITE)

_KIND_PREFIX = "topic_alert"
#: `kind` propre, utilisé pour les analytics (le `kind` stocké porte le sujet).
ANALYTICS_KIND = _KIND_PREFIX


@dataclass(frozen=True)
class TopicAlertCandidate:
    """Un contenu frais correspondant à un sujet sous cloche."""

    topic_id: UUID
    topic_name: str
    content_id: UUID
    content_title: str
    published_at: datetime
    articles_30d: int
    oldest_content_at: datetime | None


def topic_alert_kind(topic_id: UUID) -> str:
    """`kind` de livraison porteur du sujet (28 car., tient dans `String(32)`).

    Même raison que côté source : `push_deliveries` est unique par
    `(device_id, target_date, kind)`, donc deux cloches du même jour doivent
    porter des `kind` distincts.
    """
    return f"{_KIND_PREFIX}:{topic_id.hex[:16]}"


def build_topic_predicate(profile: UserTopicProfile):
    r"""Clause `OR` « cet article parle de ce sujet », ou `None` si indécidable.

    - `canonical_name` → `content_entities_text(entities) ILIKE '%nom%'`, la
      forme exacte qu'indexe `ix_contents_entities_trgm` (GIN trigram) ;
    - `keywords` → `title`/`description` en **mot entier** (`\m…\M`, bornes de
      mot Postgres), jamais en sous-chaîne : sinon « nets » survit dans
      « internets ».

    Un profil sans entité ni mot-clé ne matche rien (`None`) plutôt que tout :
    une cloche silencieuse vaut mieux qu'une cloche qui sonne sur le vide.
    """
    clauses = []
    if profile.canonical_name:
        clauses.append(
            func.content_entities_text(Content.entities).ilike(
                f"%{profile.canonical_name}%"
            )
        )
    for kw in profile.keywords or []:
        if not kw or not kw.strip():
            continue
        pattern = r"\m" + re.escape(kw.strip()) + r"\M"
        clauses.append(Content.title.op("~*")(pattern))
        clauses.append(Content.description.op("~*")(pattern))
    return or_(*clauses) if clauses else None


async def count_active_topic_alerts(session: AsyncSession, *, user_id: UUID) -> int:
    """Cloches sujet actives — composant sujet du plafond partagé."""
    return (
        await session.execute(
            select(func.count())
            .select_from(UserTopicProfile)
            .where(
                UserTopicProfile.user_id == user_id,
                UserTopicProfile.notify.is_(True),
                UserTopicProfile.state.in_(FOLLOWED_TOPIC_STATES),
            )
        )
    ).scalar_one()


async def topic_frequency_stats(
    session: AsyncSession, *, profile: UserTopicProfile, now: datetime
) -> tuple[int, datetime | None]:
    """`(articles_30d, oldest_match_at)` du sujet — entrées de la cadence.

    Contrairement aux sources, l'« âge » de la cible n'a pas de sens absolu :
    on prend la plus ancienne parution *correspondante* dans la fenêtre 30 j,
    ce qui donne le même clamp anti-sous-estimation pour un sujet apparu il y a
    trois jours.
    """
    predicate = build_topic_predicate(profile)
    if predicate is None:
        return 0, None
    window_start = now - timedelta(days=FREQUENCY_WINDOW_DAYS)
    articles_30d, oldest_match_at = (
        await session.execute(
            select(func.count(), func.min(Content.published_at)).where(
                predicate,
                Content.published_at >= window_start,
                Content.published_at <= now,
            )
        )
    ).one()
    return articles_30d, oldest_match_at


async def find_topic_alert_candidates(
    session: AsyncSession,
    *,
    user_id: UUID,
    now: datetime,
    ctx: EssentielUserContext | None = None,
) -> list[TopicAlertCandidate]:
    """Contenus frais (< 24 h) matchant les sujets sous cloche, un par sujet."""
    profiles = (
        (
            await session.execute(
                select(UserTopicProfile).where(
                    UserTopicProfile.user_id == user_id,
                    UserTopicProfile.notify.is_(True),
                    UserTopicProfile.state.in_(FOLLOWED_TOPIC_STATES),
                )
            )
        )
        .scalars()
        .all()
    )
    if not profiles:
        return []

    since = now - ALERT_LOOKBACK
    candidates: list[TopicAlertCandidate] = []
    for profile in profiles:
        predicate = build_topic_predicate(profile)
        if predicate is None:
            continue
        contents = (
            (
                await session.execute(
                    select(Content)
                    .options(selectinload(Content.source))
                    .where(
                        predicate,
                        Content.published_at >= since,
                        Content.published_at <= now,
                    )
                    .order_by(Content.published_at.desc())
                )
            )
            .scalars()
            .all()
        )
        if not contents:
            continue

        if profile.notify_filtered is True:
            if ctx is None:
                ctx = await fetch_user_essentiel_context(session, user_id)
            scoring_ctx = ctx
            best = max(
                contents,
                key=lambda c: (_score_live_candidate(c, scoring_ctx), c.published_at),
            )
        else:
            best = contents[0]

        articles_30d, oldest_match_at = await topic_frequency_stats(
            session, profile=profile, now=now
        )
        candidates.append(
            TopicAlertCandidate(
                topic_id=profile.id,
                topic_name=profile.topic_name,
                content_id=best.id,
                content_title=best.title,
                published_at=best.published_at,
                articles_30d=articles_30d,
                oldest_content_at=oldest_match_at,
            )
        )
    return candidates
