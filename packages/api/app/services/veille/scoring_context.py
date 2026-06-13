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

import re
from dataclasses import dataclass
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import InterestState
from app.models.user import UserProfile
from app.services.recommendation.french_stopwords import FRENCH_STOP_WORDS
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext

if TYPE_CHECKING:  # éviter un import circulaire feed_filter ↔ scoring_context
    from app.services.veille.feed_filter import VeilleFilters

# Longueur min d'un token d'intention (aligné sur KEYWORD_MIN_LENGTH = 4) :
# en-deçà les mots sont trop génériques pour discriminer.
_INTENT_MIN_TOKEN_LEN = ScoringWeights.KEYWORD_MIN_LENGTH
_INTENT_TOKEN_RE = re.compile(r"[a-zàâäéèêëîïôöùûüÿç0-9]+", re.IGNORECASE)


def _tokenize_intent(texts: list[str]) -> list[str]:
    """Tokenise des notes d'intention libres en mots-clés discriminants.

    Stopwords FR retirés, longueur ≥ 4, dédupliqués (ordre stable), bornés à
    ``VEILLE_KEYWORD_CAP`` tokens — au-delà le bonus mots-clés est de toute
    façon plafonné côté pilier Pertinence.
    """
    seen: set[str] = set()
    out: list[str] = []
    for text in texts:
        for raw in _INTENT_TOKEN_RE.findall(text.lower()):
            if (
                len(raw) >= _INTENT_MIN_TOKEN_LEN
                and raw not in FRENCH_STOP_WORDS
                and raw not in seen
            ):
                seen.add(raw)
                out.append(raw)
    return out[: int(ScoringWeights.VEILLE_KEYWORD_CAP)]


@dataclass(frozen=True)
class VeilleAngleTopic:
    """Adaptateur angle veille → custom-topic (duck-typing de `_score_custom_topics`).

    `_score_custom_topics` (pertinence.py) attend `slug_parent`, `keywords`,
    `priority_multiplier`, `state`, `topic_name`. Le flag `is_veille=True`
    aiguille le pilier Pertinence vers sa **branche veille** (Story 23.4) :
    bonus mots-clés escaladant + bonus topic canonique (+50) + combo (+15) +
    source suivie conditionnée (+12 si bonus angle > 0). Hors veille (vrais
    custom topics Epic 11), `getattr(tp, "is_veille", False)` reste `False` et
    le chemin plat `+25` est inchangé.
    """

    slug_parent: str
    keywords: list[str]
    topic_name: str
    priority_multiplier: float = 1.0
    state: InterestState = InterestState.FOLLOWED
    is_veille: bool = True


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
                keywords=[
                    k.lower().strip() for k in filters.global_keywords if k.strip()
                ],
                topic_name="Mots-clés",
            )
        )

    # Notes d'intention texte libre (`why` des sources) → angle « Intention » :
    # leurs tokens deviennent des mots-clés ordinaires qui affinent le tri via
    # le bonus mots-clés existant (zéro nouveau code de scoring, borné par le
    # cap). Aucun slug → ne matche que par sa grappe.
    intent_tokens = _tokenize_intent(list(filters.source_intents.values()))
    if intent_tokens:
        custom_topics.append(
            VeilleAngleTopic(
                slug_parent="",
                keywords=intent_tokens,
                topic_name="Intention",
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
