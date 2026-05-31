"""Construction d'un `ScoringContext` pour le feed veille (refonte curation).

La veille réutilise **le moteur de scoring de la Tournée** (`PillarScoringEngine`,
piliers Pertinence/Source/Fraîcheur/Qualité) au lieu d'un scoring parallèle. Ce
module adapte une `VeilleConfig` + ses filtres en un `ScoringContext` :

- thème → `user_interests` (signal **faible** : ne qualifie jamais seul, le
  thème est même retiré du prédicat SQL côté `feed_filter`).
- topics/angles canoniques → `user_subtopics` (+45/topic matché, signal fort).
- angles (sujet + sa grappe de mots-clés) → `user_custom_topics` via
  l'adaptateur `VeilleAngleTopic` (+25/angle matché par slug **ou** keyword).
- sources suivies → `followed_source_ids` (+35 source de confiance).

Aucune affinité/multiplicateur/mute en V1 — seuls ces 4 leviers pilotent le tri.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import InterestState
from app.models.user import UserProfile
from app.services.recommendation.scoring_engine import ScoringContext

if TYPE_CHECKING:  # éviter un import circulaire feed_filter ↔ scoring_context
    from app.services.veille.feed_filter import VeilleFilters


@dataclass(frozen=True)
class VeilleAngleTopic:
    """Adaptateur angle veille → custom-topic (duck-typing de `_score_custom_topics`).

    `_score_custom_topics` (pertinence.py) attend `slug_parent`, `keywords`,
    `priority_multiplier`, `state`, `topic_name`. Un angle matche si son
    `slug_parent` est dans `content.topics` **ou** si l'un de ses `keywords`
    apparaît dans le titre/description → +CUSTOM_TOPIC_BASE_BONUS (25).
    """

    slug_parent: str
    keywords: list[str]
    topic_name: str
    priority_multiplier: float = 1.0
    state: InterestState = InterestState.FOLLOWED


async def build_veille_scoring_context(
    session: AsyncSession,
    config,
    filters: VeilleFilters,
    now: datetime,
) -> ScoringContext:
    """Construit le `ScoringContext` veille depuis la config + ses filtres.

    Calqué sur la construction de contexte du digest (`digest_selector`), mais
    sourcé depuis la config veille. Charge le `UserProfile` réel (select léger)
    pour un contexte non-None ; retombe sur une instance transitoire si absent.
    """
    profile = (
        (
            await session.execute(
                select(UserProfile).where(UserProfile.user_id == config.user_id)
            )
        )
        .scalars()
        .first()
    )
    if profile is None:
        profile = UserProfile(user_id=config.user_id)

    topic_slugs = {s.lower().strip() for s in filters.topic_slugs if s}

    custom_topics: list[VeilleAngleTopic] = [
        VeilleAngleTopic(
            slug_parent=angle.topic_id.lower().strip(),
            keywords=[k.lower().strip() for k in angle.keywords if k.strip()],
            topic_name=angle.label,
        )
        for angle in filters.angles
    ]
    # Les mots-clés globaux (non rattachés à un angle) deviennent un custom-topic
    # sans slug → ne matchent que par leur grappe, mais restent un signal fort
    # (+25) au même titre qu'un angle.
    if filters.global_keywords:
        custom_topics.append(
            VeilleAngleTopic(
                slug_parent="",
                keywords=[k.lower().strip() for k in filters.global_keywords if k.strip()],
                topic_name="Mots-clés",
            )
        )

    return ScoringContext(
        user_profile=profile,
        user_interests={config.theme_id} if config.theme_id else set(),
        user_interest_weights={},
        followed_source_ids=set(filters.source_ids),
        user_prefs={},
        now=now,
        user_subtopics=topic_slugs,
        user_subtopic_weights={},
        user_custom_topics=custom_topics,
    )
