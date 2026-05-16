"""Tests câblage `state` dans le pilier Pertinence (Story 22.1).

Vérifie :
- `state=hidden` → `_score_behavioral` retourne 0 (court-circuit total),
- `state=favorite` → weight floor à 1.5 (boost garanti même si weight ML bas),
- `state=followed` (default) → comportement strictement identique à pré-PR
  (pas de régression sur l'algo V2).
"""

import datetime
from unittest.mock import MagicMock
from uuid import uuid4

from app.models.content import Content
from app.models.enums import InterestState
from app.services.recommendation.pillars.pertinence import PertinencePillar
from app.services.recommendation.scoring_engine import ScoringContext


def _content_with_theme(theme: str = "tech") -> Content:
    c = Content(
        id=uuid4(),
        title="Test article",
        url=f"https://example.com/{uuid4()}",
        source_id=uuid4(),
        published_at=datetime.datetime.now(datetime.UTC),
        theme=theme,
        topics=[theme],
    )
    return c


def _context(*, weight: float, state: InterestState | None) -> ScoringContext:
    user_interest_states = {} if state is None else {"tech": state}
    return ScoringContext(
        user_profile=MagicMock(),
        user_interests={"tech"},
        user_interest_weights={"tech": weight},
        followed_source_ids=set(),
        user_prefs={},
        now=datetime.datetime.now(datetime.UTC),
        user_custom_topics=[],
        user_interest_states=user_interest_states,
    )


def test_hidden_state_short_circuits_behavioral_score():
    pillar = PertinencePillar()
    content = _content_with_theme("tech")
    context = _context(weight=2.0, state=InterestState.HIDDEN)
    score, contribs = pillar._score_behavioral(content, context)
    assert score == 0.0
    assert contribs == []


def test_favorite_state_floors_weight_to_15():
    """`state=favorite` + `weight=1.0` doit produire le même bonus que
    `state=followed` + `weight=1.5` (le floor garantit le boost minimal)."""
    pillar = PertinencePillar()
    content = _content_with_theme("tech")

    score_fav, _ = pillar._score_behavioral(
        content, _context(weight=1.0, state=InterestState.FAVORITE)
    )
    score_high, _ = pillar._score_behavioral(
        content, _context(weight=1.5, state=InterestState.FOLLOWED)
    )
    assert score_fav == score_high
    assert score_fav > 0


def test_followed_default_unchanged_from_legacy():
    """Sans state déclaré (cas pré-22.1), le scoring reste identique : weight
    élevé donne un bonus, weight bas donne un malus, weight=1.0 → 0."""
    pillar = PertinencePillar()
    content = _content_with_theme("tech")

    high_score, _ = pillar._score_behavioral(
        content, _context(weight=2.0, state=None)
    )
    low_score, _ = pillar._score_behavioral(
        content, _context(weight=0.5, state=None)
    )
    neutral_score, _ = pillar._score_behavioral(
        content, _context(weight=1.0, state=None)
    )
    assert high_score > 0
    assert low_score < 0
    assert neutral_score == 0
