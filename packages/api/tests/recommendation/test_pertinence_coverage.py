"""Tests for the Coverage contribution inside PertinencePillar.

Validates that an article belonging to a cluster covered by multiple
sources in the past 24h gets a positive boost on top of theme/subtopic
matching, while a scoop (cluster_size=1) gets nothing.
"""

import math
from datetime import datetime
from unittest.mock import MagicMock
from uuid import uuid4

from app.services.recommendation.helpers.coverage_score import compute_coverage_score
from app.services.recommendation.pillars.pertinence import PertinencePillar
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext


class _Source:
    def __init__(self, theme=None):
        self.id = uuid4()
        self.theme = theme
        self.secondary_themes = []
        self.is_curated = True


class _Content:
    def __init__(self, theme=None, source_theme=None, topics=None, cluster_id=None):
        self.id = uuid4()
        self.title = "Test"
        self.description = ""
        self.theme = theme
        self.topics = topics or []
        self.source = _Source(theme=source_theme)
        self.source_id = self.source.id
        self.published_at = datetime.now()
        self.content_type = None
        self.duration_seconds = None
        self.cluster_id = cluster_id


def _context(*, cluster_source_counts=None, user_interests=None):
    return ScoringContext(
        user_profile=MagicMock(id=uuid4()),
        user_interests=set(user_interests or []),
        user_interest_weights={},
        followed_source_ids=set(),
        user_prefs={},
        now=datetime.now(),
        cluster_source_counts=cluster_source_counts or {},
    )


def test_no_cluster_no_bonus():
    """Article sans cluster_id n'a pas de bonus coverage."""
    content = _Content(cluster_id=None)
    ctx = _context(cluster_source_counts={uuid4(): 5})

    pillar = PertinencePillar()
    raw, contribs = pillar.compute_raw(content, ctx)

    assert not any(c.label.startswith("Couvert") for c in contribs)
    assert not any(c.label == "Sujet relayé" for c in contribs)


def test_singleton_cluster_no_bonus():
    """cluster_size == 1 (scoop isolé) → 0 pt."""
    cid = uuid4()
    content = _Content(cluster_id=cid)
    ctx = _context(cluster_source_counts={cid: 1})

    pillar = PertinencePillar()
    raw, _ = pillar.compute_raw(content, ctx)

    # Pas de match thématique non plus → THEME_MISMATCH_MALUS s'applique
    # uniquement si user_interests, mais ici set vide → 0.
    assert raw == 0.0


def test_trending_cluster_gets_label_and_bonus():
    """≥3 sources → bonus log-calibré + label 'Couvert par N sources'."""
    cid = uuid4()
    content = _Content(cluster_id=cid)
    ctx = _context(cluster_source_counts={cid: 5})

    pillar = PertinencePillar()
    raw, contribs = pillar.compute_raw(content, ctx)

    coverage_contribs = [c for c in contribs if c.label.startswith("Couvert")]
    assert len(coverage_contribs) == 1
    expected = compute_coverage_score(5)
    assert coverage_contribs[0].points == expected
    assert raw == expected


def test_small_cluster_gets_relayed_label():
    """2 sources : bonus existe mais label moins fort que 'trending'."""
    cid = uuid4()
    content = _Content(cluster_id=cid)
    ctx = _context(cluster_source_counts={cid: 2})

    pillar = PertinencePillar()
    raw, contribs = pillar.compute_raw(content, ctx)

    contrib = next(c for c in contribs if c.label == "Sujet relayé")
    assert contrib.points == ScoringWeights.COVERAGE_BASE


def test_coverage_stacks_with_theme_match():
    """Coverage s'ajoute à THEME_MATCH, sans le remplacer."""
    cid = uuid4()
    content = _Content(theme="tech", cluster_id=cid)
    ctx = _context(
        cluster_source_counts={cid: 4},
        user_interests={"tech"},
    )

    pillar = PertinencePillar()
    raw, _ = pillar.compute_raw(content, ctx)

    expected = ScoringWeights.THEME_MATCH + ScoringWeights.COVERAGE_BASE * math.log2(4)
    assert raw == expected
