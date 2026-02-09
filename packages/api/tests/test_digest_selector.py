"""Tests unitaires pour DigestSelector — sélection et diversité.

Couvre:
- _select_with_diversity: sélection avec contraintes de diversité
- Decay factor 0.70 appliqué aux sources répétées
- Maximum 2 articles par source
- Minimum 3 sources différentes
- Retourne des 4-tuples (content, score, reason, breakdown)
- Gestion des cas limites (peu de candidats, source unique)
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from uuid import uuid4
from datetime import datetime, timezone, timedelta
from collections import defaultdict

from app.services.digest_selector import DigestSelector, DigestContext, DiversityConstraints
from app.schemas.digest import DigestScoreBreakdown


# ─── Factories ────────────────────────────────────────────────────────────────


def make_source(name="Test Source", theme="tech", is_curated=False):
    """Factory pour créer un objet Source mocké."""
    source = Mock()
    source.id = uuid4()
    source.name = name
    source.theme = theme
    source.is_curated = is_curated
    source.reliability_score = None
    return source


def make_content(source=None, topics=None, published_at=None, content_type=None):
    """Factory pour créer un objet Content mocké."""
    content = Mock()
    content.id = uuid4()
    content.source = source or make_source()
    content.source_id = content.source.id
    content.published_at = published_at or datetime.now(timezone.utc)
    content.topics = topics
    content.content_type = content_type
    content.title = f"Article {content.id}"
    content.url = f"https://example.com/{content.id}"
    content.thumbnail_url = None
    content.description = None
    content.duration_seconds = None
    return content


def make_scored_candidates(contents_with_scores):
    """Construit la liste scored_candidates au format attendu par _select_with_diversity.
    
    Args:
        contents_with_scores: list of (content, score) or (content, score, breakdown)
    
    Returns:
        list of (content, score, breakdown) — format d'entrée de _select_with_diversity
    """
    result = []
    for item in contents_with_scores:
        if len(item) == 3:
            result.append(item)
        else:
            content, score = item
            result.append((content, score, []))
    return result


# ─── Fixtures ─────────────────────────────────────────────────────────────────


@pytest.fixture
def mock_session():
    """Mock de session SQLAlchemy async."""
    return AsyncMock()


@pytest.fixture
def selector(mock_session):
    """Instance de DigestSelector avec session mockée.
    
    Note: on patche rec_service pour éviter l'initialisation
    de RecommendationService qui nécessite une vraie session DB.
    """
    with patch('app.services.digest_selector.RecommendationService'):
        sel = DigestSelector(mock_session)
    return sel


# ─── Tests: _select_with_diversity ────────────────────────────────────────────


class TestSelectWithDiversity:
    """Tests pour DigestSelector._select_with_diversity().
    
    Cette méthode est synchrone (pas de DB), donc testable directement.
    Elle prend des scored_candidates triés par score et retourne
    des 4-tuples (content, decayed_score, reason, breakdown).
    """

    def test_selects_exactly_target_count(self, selector):
        """Given 10 articles from 5 sources, selects exactly 5."""
        sources = [make_source(name=f"Source {i}", theme=f"theme{i}") for i in range(5)]
        candidates = []
        for i, source in enumerate(sources):
            for j in range(2):
                content = make_content(source=source)
                score = 100.0 - (i * 10) - j
                candidates.append((content, score, []))

        selected = selector._select_with_diversity(candidates, target_count=5)

        assert len(selected) == 5

    def test_returns_four_tuple(self, selector):
        """Each result element is a 4-tuple (content, score, reason, breakdown)."""
        source = make_source()
        content = make_content(source=source)
        scored = [(content, 100.0, [])]

        selected = selector._select_with_diversity(scored, target_count=1)

        assert len(selected) == 1
        # Unpack 4 values — must not raise ValueError
        content_out, score_out, reason_out, breakdown_out = selected[0]
        assert content_out is content
        assert isinstance(score_out, float)
        assert isinstance(reason_out, str)
        assert isinstance(breakdown_out, list)

    def test_diversity_max_two_per_source(self, selector):
        """No source should have more than 2 articles in the result."""
        source_a = make_source(name="Source A", theme="tech")
        source_b = make_source(name="Source B", theme="science")

        candidates = []
        # 5 articles from source A (high scores)
        for i in range(5):
            candidates.append((make_content(source=source_a), 100.0 - i, []))
        # 5 articles from source B (lower scores)
        for i in range(5):
            candidates.append((make_content(source=source_b), 50.0 - i, []))

        selected = selector._select_with_diversity(candidates, target_count=5)

        # Count articles per source
        source_counts = defaultdict(int)
        for content, _, _, _ in selected:
            source_counts[content.source_id] += 1

        for source_id, count in source_counts.items():
            assert count <= 2, f"Source {source_id} has {count} articles (max 2)"

    def test_decay_factor_applied(self, selector):
        """Score should decrease with repeated source selection (decay 0.70)."""
        source = make_source(name="Repeated Source", theme="tech")
        content1 = make_content(source=source)
        content2 = make_content(source=source)

        # Give both same base score
        candidates = [
            (content1, 100.0, []),
            (content2, 100.0, []),
        ]

        selected = selector._select_with_diversity(candidates, target_count=2)

        assert len(selected) == 2
        _, score1, _, _ = selected[0]
        _, score2, _, _ = selected[1]

        # First article: no decay (0.70^0 = 1.0) → score = 100.0
        assert score1 == pytest.approx(100.0)
        # Second article: one decay (0.70^1 = 0.70) → score = 70.0
        assert score2 == pytest.approx(70.0)

    def test_higher_scores_selected_first(self, selector):
        """Higher-scored articles are selected before lower-scored ones."""
        sources = [make_source(name=f"Source {i}", theme=f"theme{i}") for i in range(5)]
        candidates = []
        for i, source in enumerate(sources):
            content = make_content(source=source)
            score = 100.0 - (i * 20)  # 100, 80, 60, 40, 20
            candidates.append((content, score, []))

        selected = selector._select_with_diversity(candidates, target_count=5)

        # Scores should be in descending order (all from different sources, no decay)
        scores = [score for _, score, _, _ in selected]
        assert scores == sorted(scores, reverse=True)

    def test_fewer_candidates_than_target(self, selector):
        """When fewer candidates available than target, returns all available."""
        sources = [make_source(name=f"Source {i}", theme=f"theme{i}") for i in range(3)]
        candidates = []
        for i, source in enumerate(sources):
            content = make_content(source=source)
            candidates.append((content, 80.0 - i * 10, []))

        selected = selector._select_with_diversity(candidates, target_count=5)

        assert len(selected) == 3

    def test_single_source_max_two_selected(self, selector):
        """All articles from same source → only 2 selected with decay."""
        source = make_source(name="Only Source", theme="tech")
        candidates = []
        for i in range(10):
            content = make_content(source=source)
            candidates.append((content, 100.0 - i, []))

        selected = selector._select_with_diversity(candidates, target_count=5)

        # Should select max 2 from single source
        assert len(selected) == 2

    def test_theme_diversity_max_two_per_theme(self, selector):
        """No theme should have more than 2 articles in the result."""
        # Create 3 sources with same theme
        source_a = make_source(name="Source A", theme="tech")
        source_b = make_source(name="Source B", theme="tech")
        source_c = make_source(name="Source C", theme="tech")
        # Create 2 sources with different themes
        source_d = make_source(name="Source D", theme="science")
        source_e = make_source(name="Source E", theme="economy")

        candidates = [
            (make_content(source=source_a), 100.0, []),
            (make_content(source=source_b), 95.0, []),
            (make_content(source=source_c), 90.0, []),  # 3rd tech — should be skipped
            (make_content(source=source_d), 85.0, []),
            (make_content(source=source_e), 80.0, []),
        ]

        selected = selector._select_with_diversity(candidates, target_count=5)

        # Count articles per theme
        theme_counts = defaultdict(int)
        for content, _, _, _ in selected:
            theme = content.source.theme
            theme_counts[theme] += 1

        for theme, count in theme_counts.items():
            assert count <= 2, f"Theme '{theme}' has {count} articles (max 2)"

    def test_diversity_halves_score_for_duplicate_source(self, selector):
        """TEST-02: Verify score ÷ 2 for 2nd article from same source (revue de presse)."""
        source = make_source(name="Test Source", theme="tech")
        content1 = make_content(source=source)
        content2 = make_content(source=source)

        candidates = [
            (content1, 220.0, []),
            (content2, 220.0, []),
        ]

        selected = selector._select_with_diversity(candidates, target_count=2)

        _, score1, _, _ = selected[0]
        _, score2, _, _ = selected[1]

        # First: 220 (no penalty)
        assert score1 == pytest.approx(220.0)
        # Second: 220 ÷ 2 = 110
        assert score2 == pytest.approx(110.0)

    def test_reason_string_generated(self, selector):
        """Each selected item has a non-empty reason string."""
        source = make_source(name="Test Source", theme="tech")
        content = make_content(source=source)
        candidates = [(content, 50.0, [])]

        selected = selector._select_with_diversity(candidates, target_count=1)

        _, _, reason, _ = selected[0]
        assert reason  # Non-empty
        assert isinstance(reason, str)
        assert len(reason) > 0

    def test_breakdown_passed_through(self, selector):
        """Breakdown from scored candidates is preserved in output."""
        source = make_source(name="Breakdown Source", theme="tech")
        content = make_content(source=source)
        breakdown_input = [
            DigestScoreBreakdown(label="Thème matché : tech", points=70.0, is_positive=True),
            DigestScoreBreakdown(label="Source de confiance", points=50.0, is_positive=True),
        ]
        candidates = [(content, 120.0, breakdown_input)]

        selected = selector._select_with_diversity(candidates, target_count=1)

        _, _, _, breakdown_out = selected[0]
        assert len(breakdown_out) == 2
        assert breakdown_out[0].label == "Thème matché : tech"
        assert breakdown_out[1].points == 50.0

    def test_mixed_sources_diversity(self, selector):
        """With 5 different sources and varied scores, all 5 sources represented."""
        sources = [make_source(name=f"Source {chr(65+i)}", theme=f"theme{i}") for i in range(5)]
        candidates = []
        for i, source in enumerate(sources):
            content = make_content(source=source)
            candidates.append((content, 100.0 - i * 5, []))

        selected = selector._select_with_diversity(candidates, target_count=5)

        assert len(selected) == 5
        unique_sources = set(c.source_id for c, _, _, _ in selected)
        assert len(unique_sources) == 5

    def test_empty_candidates_returns_empty(self, selector):
        """Empty candidate list returns empty selection."""
        selected = selector._select_with_diversity([], target_count=5)
        assert selected == []


# ─── Tests: DiversityConstraints ──────────────────────────────────────────────


class TestDiversityConstraints:
    """Test configuration constants for diversity."""

    def test_max_per_source_is_two(self):
        assert DiversityConstraints.MAX_PER_SOURCE == 2

    def test_max_per_theme_is_two(self):
        assert DiversityConstraints.MAX_PER_THEME == 2

    def test_target_digest_size_is_five(self):
        assert DiversityConstraints.TARGET_DIGEST_SIZE == 5

    def test_diversity_divisor_value(self):
        """Verify diversity divisor is 2 (score ÷ 2) as per algorithm spec."""
        from app.services.recommendation.scoring_config import ScoringWeights
        assert ScoringWeights.DIGEST_DIVERSITY_DIVISOR == 2, \
            "Diversity divisor should be 2 (score ÷ 2)"


# ─── Tests: Diversity Revue de Presse (÷2 Penalty) ────────────────────────────


class TestDiversityRevueDePresse:
    """Tests for the ÷2 diversity penalty algorithm (revue de presse effect)."""

    def test_diversity_penalty_visible_in_breakdown(self, selector):
        """Règle d'or: la pénalité diversité doit apparaître dans le breakdown utilisateur."""
        source = make_source(name="Le Monde", theme="society")
        content1 = make_content(source=source)
        content2 = make_content(source=source)

        articles = [
            (content1, 200.0, []),
            (content2, 200.0, []),
        ]

        selected = selector._select_with_diversity(articles, target_count=5)

        # The 2nd article should have "Diversité revue de presse" in its breakdown
        assert len(selected) == 2
        second_article_breakdown = selected[1][3]  # (content, score, reason, breakdown)
        diversity_labels = [b.label for b in second_article_breakdown]
        assert "Diversité revue de presse" in diversity_labels, \
            f"Expected 'Diversité revue de presse' in breakdown, got: {diversity_labels}"

        # The penalty should be -100 (200 / 2)
        diversity_entry = next(b for b in second_article_breakdown if b.label == "Diversité revue de presse")
        assert diversity_entry.points == -100.0
        assert diversity_entry.is_positive is False

        # First article should NOT have the diversity penalty
        first_article_breakdown = selected[0][3]
        first_labels = [b.label for b in first_article_breakdown]
        assert "Diversité revue de presse" not in first_labels

    def test_diversity_penalty_relegate_duplicate_below_alternative(self, selector):
        """Scenario réel: un doublon à 220 pts doit être dépassé par une alternative à 150 pts."""
        source_a = make_source(name="Le Monde", theme="society")
        source_b = make_source(name="Libération", theme="politics")

        # Le Monde article 1 (rank 1) — score 220
        content1 = make_content(source=source_a)
        content1.title = "Le Monde #1"
        # Le Monde article 2 (would be rank 2) — score 200
        content2 = make_content(source=source_a)
        content2.title = "Le Monde #2"
        # Libération article (rank 3 without penalty) — score 150
        content3 = make_content(source=source_b)
        content3.title = "Libération #1"

        scored = [
            (content1, 220.0, []),
            (content2, 200.0, []),
            (content3, 150.0, []),
        ]

        selected = selector._select_with_diversity(scored, target_count=3)

        # Verify all 3 selected and Le Monde #2 got penalized
        assert len(selected) == 3

        # Verify Le Monde #2 got penalized (200 ÷ 2 = 100)
        scores = {item[0].title: item[1] for item in selected}
        assert scores["Le Monde #1"] == 220.0
        assert scores["Le Monde #2"] == pytest.approx(100.0)
        assert scores["Libération #1"] == 150.0
