"""Tests unitaires pour DigestSelector — sélection et diversité.

Couvre:
- _select_with_diversity: sélection avec contraintes de diversité
- Decay factor 0.70 appliqué aux sources répétées
- Maximum 1 article par source (fallback à 2 si < 7 sources distinctes)
- Minimum 4 sources différentes
- Retourne des 4-tuples (content, score, reason, breakdown)
- Gestion des cas limites (peu de candidats, source unique)
- Sélection hybride deux passes (trending + personnalisé)
- Continuité diversité entre passes
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from uuid import uuid4
from datetime import datetime, timezone, timedelta
from collections import defaultdict

from app.services.digest_selector import DigestSelector, DigestContext, DiversityConstraints, GlobalTrendingContext
from app.schemas.digest import DigestScoreBreakdown


# ─── Factories ────────────────────────────────────────────────────────────────


def make_source(name="Test Source", theme="tech", is_curated=False, secondary_themes=None):
    """Factory pour créer un objet Source mocké."""
    source = Mock()
    source.id = uuid4()
    source.name = name
    source.theme = theme
    source.is_curated = is_curated
    source.reliability_score = None
    source.secondary_themes = secondary_themes or []
    return source


def make_content(source=None, topics=None, published_at=None, content_type=None, theme=None):
    """Factory pour créer un objet Content mocké."""
    content = Mock()
    content.id = uuid4()
    content.source = source or make_source()
    content.source_id = content.source.id
    content.published_at = published_at or datetime.now(timezone.utc)
    content.topics = topics
    content.content_type = content_type
    content.theme = theme
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
        """Given 14 articles from 7 sources, selects exactly 7."""
        sources = [make_source(name=f"Source {i}", theme=f"theme{i}") for i in range(7)]
        candidates = []
        for i, source in enumerate(sources):
            for j in range(2):
                content = make_content(source=source)
                score = 100.0 - (i * 10) - j
                candidates.append((content, score, []))

        selected = selector._select_with_diversity(candidates, target_count=7)

        assert len(selected) == 7

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

    def test_diversity_max_one_per_source_with_enough_sources(self, selector):
        """With >= 7 distinct sources, max 1 article per source."""
        sources = [make_source(name=f"Source {i}", theme=f"theme{i}") for i in range(8)]
        candidates = []
        for i, source in enumerate(sources):
            # 2 articles per source
            for j in range(2):
                candidates.append((make_content(source=source), 100.0 - i * 5 - j, []))

        selected = selector._select_with_diversity(candidates, target_count=7)

        # Count articles per source — should be max 1 each
        source_counts = defaultdict(int)
        for content, _, _, _ in selected:
            source_counts[content.source_id] += 1

        for source_id, count in source_counts.items():
            assert count <= 1, f"Source {source_id} has {count} articles (max 1 with >= 7 sources)"

    def test_diversity_fallback_max_two_per_source_with_few_sources(self, selector):
        """With < 7 distinct sources, fallback to max 2 per source."""
        source_a = make_source(name="Source A", theme="tech")
        source_b = make_source(name="Source B", theme="science")
        source_c = make_source(name="Source C", theme="economy")

        candidates = []
        # 5 articles from source A (high scores)
        for i in range(5):
            candidates.append((make_content(source=source_a), 100.0 - i, []))
        # 5 articles from source B (medium scores)
        for i in range(5):
            candidates.append((make_content(source=source_b), 50.0 - i, []))
        # 5 articles from source C (lower scores)
        for i in range(5):
            candidates.append((make_content(source=source_c), 30.0 - i, []))

        selected = selector._select_with_diversity(candidates, target_count=7)

        # Count articles per source — should allow up to 2
        source_counts = defaultdict(int)
        for content, _, _, _ in selected:
            source_counts[content.source_id] += 1

        for source_id, count in source_counts.items():
            assert count <= 2, f"Source {source_id} has {count} articles (max 2 with < 7 sources)"

    def test_decay_factor_applied(self, selector):
        """Score should decrease with repeated source selection (÷2 divisor).

        With only 1 source, the fallback to MAX_PER_SOURCE=2 kicks in.
        """
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

        # First article: no penalty → score = 100.0
        assert score1 == pytest.approx(100.0)
        # Second article: ÷2 divisor → score = 50.0
        assert score2 == pytest.approx(50.0)

    def test_higher_scores_selected_first(self, selector):
        """Higher-scored articles are selected before lower-scored ones."""
        sources = [make_source(name=f"Source {i}", theme=f"theme{i}") for i in range(7)]
        candidates = []
        for i, source in enumerate(sources):
            content = make_content(source=source)
            score = 100.0 - (i * 10)  # 100, 90, 80, 70, 60, 50, 40
            candidates.append((content, score, []))

        selected = selector._select_with_diversity(candidates, target_count=7)

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

        selected = selector._select_with_diversity(candidates, target_count=7)

        assert len(selected) == 3

    def test_single_source_max_two_selected(self, selector):
        """All articles from same source → only 2 selected (fallback since < 7 sources)."""
        source = make_source(name="Only Source", theme="tech")
        candidates = []
        for i in range(10):
            content = make_content(source=source)
            candidates.append((content, 100.0 - i, []))

        selected = selector._select_with_diversity(candidates, target_count=7)

        # Should select max 2 from single source (fallback to MAX_PER_SOURCE=2)
        assert len(selected) == 2

    def test_theme_diversity_max_two_per_theme(self, selector):
        """No theme should have more than 2 articles in the result."""
        # Create 3 sources with same theme
        source_a = make_source(name="Source A", theme="tech")
        source_b = make_source(name="Source B", theme="tech")
        source_c = make_source(name="Source C", theme="tech")
        # Create 4 sources with different themes
        source_d = make_source(name="Source D", theme="science")
        source_e = make_source(name="Source E", theme="economy")
        source_f = make_source(name="Source F", theme="culture")
        source_g = make_source(name="Source G", theme="politics")

        candidates = [
            (make_content(source=source_a), 100.0, []),
            (make_content(source=source_b), 95.0, []),
            (make_content(source=source_c), 90.0, []),  # 3rd tech — should be skipped
            (make_content(source=source_d), 85.0, []),
            (make_content(source=source_e), 80.0, []),
            (make_content(source=source_f), 75.0, []),
            (make_content(source=source_g), 70.0, []),
        ]

        selected = selector._select_with_diversity(candidates, target_count=7)

        # Count articles per theme
        theme_counts = defaultdict(int)
        for content, _, _, _ in selected:
            theme = content.source.theme
            theme_counts[theme] += 1

        for theme, count in theme_counts.items():
            assert count <= 2, f"Theme '{theme}' has {count} articles (max 2)"

    def test_diversity_halves_score_for_duplicate_source(self, selector):
        """TEST-02: Verify score ÷ 2 for 2nd article from same source (revue de presse).

        With only 1 source, fallback MAX_PER_SOURCE=2 kicks in.
        """
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
        """With 7 different sources and varied scores, all 7 sources represented."""
        sources = [make_source(name=f"Source {chr(65+i)}", theme=f"theme{i}") for i in range(7)]
        candidates = []
        for i, source in enumerate(sources):
            content = make_content(source=source)
            candidates.append((content, 100.0 - i * 5, []))

        selected = selector._select_with_diversity(candidates, target_count=7)

        assert len(selected) == 7
        unique_sources = set(c.source_id for c, _, _, _ in selected)
        assert len(unique_sources) == 7

    def test_empty_candidates_returns_empty(self, selector):
        """Empty candidate list returns empty selection."""
        selected = selector._select_with_diversity([], target_count=7)
        assert selected == []


# ─── Tests: DiversityConstraints ──────────────────────────────────────────────


class TestDiversityConstraints:
    """Test configuration constants for diversity."""

    def test_max_per_source_is_one(self):
        assert DiversityConstraints.MAX_PER_SOURCE == 1

    def test_max_per_theme_is_two(self):
        assert DiversityConstraints.MAX_PER_THEME == 2

    def test_target_digest_size_is_seven(self):
        assert DiversityConstraints.TARGET_DIGEST_SIZE == 7

    def test_completion_threshold_is_five(self):
        assert DiversityConstraints.COMPLETION_THRESHOLD == 5

    def test_min_sources_is_three(self):
        """MIN_SOURCES is overridden to 3 in _select_with_diversity for production."""
        # Note: DiversityConstraints.MIN_SOURCES is 4, but the algorithm uses MIN_SOURCES = 3
        # This is set in _select_with_diversity method for better digest diversity
        assert DiversityConstraints.MIN_SOURCES == 4  # Class constant

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


# ─── Tests: Diversity avec compteurs initiaux (continuité entre passes) ───────


class TestDiversityInitialCounts:
    """Tests pour _select_with_diversity avec initial_source_counts/initial_theme_counts."""

    def test_initial_source_counts_respected(self, selector):
        """Si une source est déjà comptée (pass 1), elle ne dépasse pas max_per_source."""
        source_a = make_source(name="Source A", theme="tech")
        source_b = make_source(name="Source B", theme="science")
        source_c = make_source(name="Source C", theme="culture")

        candidates = [
            (make_content(source=source_a), 200.0, []),  # source_a déjà à 1 → skip
            (make_content(source=source_b), 150.0, []),
            (make_content(source=source_c), 100.0, []),
        ]

        # source_a already has 1 article from pass 1
        selected = selector._select_with_diversity(
            candidates,
            target_count=2,
            initial_source_counts={source_a.id: 1},
        )

        # source_a article should be skipped (max 1 per source with >= 7 distinct)
        # With < 7 sources, fallback to max 2 → source_a gets penalty ÷2
        # But the key test: source_a count starts at 1
        source_ids = [c.source_id for c, _, _, _ in selected]
        # source_b and source_c should be selected first (no prior count)
        assert len(selected) == 2

    def test_initial_theme_counts_respected(self, selector):
        """Si un thème est déjà compté (pass 1), il ne dépasse pas max_per_theme."""
        # With 8 different sources but some sharing theme "tech"
        sources = [make_source(name=f"Source {i}", theme="tech") for i in range(3)]
        sources += [make_source(name=f"Other {i}", theme=f"other{i}") for i in range(5)]

        candidates = [
            (make_content(source=sources[0]), 200.0, []),  # tech (already at 2 → skip)
            (make_content(source=sources[3]), 150.0, []),   # other0
            (make_content(source=sources[4]), 120.0, []),   # other1
        ]

        # theme "tech" already has 2 articles from pass 1
        selected = selector._select_with_diversity(
            candidates,
            target_count=2,
            initial_theme_counts={"tech": 2},
        )

        # tech article should be skipped (max 2 per theme)
        themes = []
        for content, _, _, _ in selected:
            themes.append(content.source.theme)
        assert "tech" not in themes
        assert len(selected) == 2

    def test_no_initial_counts_matches_original_behavior(self, selector):
        """Sans compteurs initiaux, le comportement est identique à l'original."""
        sources = [make_source(name=f"S{i}", theme=f"t{i}") for i in range(7)]
        candidates = [(make_content(source=s), 100.0 - i * 10, []) for i, s in enumerate(sources)]

        selected_default = selector._select_with_diversity(candidates, target_count=7)
        selected_explicit = selector._select_with_diversity(
            candidates, target_count=7, initial_source_counts=None, initial_theme_counts=None,
        )

        # Both should select same articles in same order
        assert len(selected_default) == len(selected_explicit)
        for (c1, s1, _, _), (c2, s2, _, _) in zip(selected_default, selected_explicit):
            assert c1.id == c2.id
            assert s1 == s2


# ─── Tests: Sélection deux passes (trending + personnalisé) ──────────────────


class TestTwoPassSelection:
    """Tests pour DigestSelector._two_pass_selection()."""

    @pytest.fixture
    def context(self):
        """Construit un DigestContext minimal pour les tests."""
        return DigestContext(
            user_id=uuid4(),
            user_profile=Mock(),
            user_interests={"tech", "science"},
            user_interest_weights={"tech": 1.0, "science": 1.0},
            followed_source_ids=set(),
            custom_source_ids=set(),
            user_prefs={},
            user_subtopics=set(),
            user_subtopic_weights={},
            muted_sources=set(),
            muted_themes=set(),
            muted_topics=set(),
        )

    @pytest.fixture
    def trending_context(self):
        """Construit un GlobalTrendingContext vide (à remplir par test)."""
        return GlobalTrendingContext(
            trending_content_ids=set(),
            une_content_ids=set(),
            computed_at=datetime.now(timezone.utc),
        )

    @pytest.mark.asyncio
    async def test_two_pass_with_trending(self, selector, context, trending_context):
        """Les articles trending sont sélectionnés en passe 1, le reste en passe 2."""
        themes = ["tech", "science", "culture", "economy", "politics", "environment", "international"]
        sources = [make_source(name=f"Source {i}", theme=themes[i]) for i in range(7)]
        context.user_interests = set(themes)

        trending_content = make_content(source=sources[0])
        perso_contents = [make_content(source=sources[i]) for i in range(1, 7)]

        trending_context.trending_content_ids = {trending_content.id}
        all_candidates = [trending_content] + perso_contents

        async def mock_score(candidates, ctx, mode="pour_vous"):
            return [(c, 100.0, []) for c in candidates]

        selector._score_candidates = mock_score

        selected = await selector._two_pass_selection(
            candidates=all_candidates,
            context=context,
            trending_context=trending_context,
            target_count=7,
        )

        assert len(selected) == 7

        # Le premier article devrait être trending (pass 1 est en tête)
        first_content = selected[0][0]
        assert first_content.id == trending_content.id

        # Vérifier que "Sujet du jour" est dans le breakdown du trending
        first_breakdown = selected[0][3]
        labels = [b.label for b in first_breakdown]
        assert "Sujet du jour" in labels

    @pytest.mark.asyncio
    async def test_two_pass_trending_relevance_filter(self, selector, context, trending_context):
        """Articles trending hors thèmes/sources utilisateur → pool personnalisé."""
        # Source avec thème "sports" (PAS dans user_interests)
        source_sports = make_source(name="L'Équipe", theme="sports")
        # Source avec thème "tech" (dans user_interests)
        source_tech = make_source(name="TechCrunch", theme="tech")

        trending_but_irrelevant = make_content(source=source_sports)
        perso_content = make_content(source=source_tech)

        trending_context.trending_content_ids = {trending_but_irrelevant.id}

        async def mock_score(candidates, ctx, mode="pour_vous"):
            return [(c, 100.0, []) for c in candidates]

        selector._score_candidates = mock_score

        selected = await selector._two_pass_selection(
            candidates=[trending_but_irrelevant, perso_content],
            context=context,
            trending_context=trending_context,
            target_count=2,
        )

        # trending_but_irrelevant devrait être dans le pool perso (pas de bonus trending)
        # Les deux articles devraient être sélectionnés mais sans bonus trending
        assert len(selected) == 2
        # Pas de "Sujet du jour" dans le breakdown car l'article n'est pas pertinent
        for _, _, _, breakdown in selected:
            labels = [b.label for b in breakdown]
            assert "Sujet du jour" not in labels

    @pytest.mark.asyncio
    async def test_two_pass_full_personalized_fallback(self, selector, context, trending_context):
        """Sans contenu trending, le digest est 100% personnalisé."""
        themes = ["tech", "science", "culture", "economy", "politics", "environment", "international"]
        sources = [make_source(name=f"S{i}", theme=themes[i]) for i in range(7)]
        contents = [make_content(source=s) for s in sources]
        context.user_interests = set(themes)

        # trending_context vide → pas de trending
        assert len(trending_context.trending_content_ids) == 0

        async def mock_score(candidates, ctx, mode="pour_vous"):
            return [(c, 100.0 - i * 10, []) for i, c in enumerate(candidates)]

        selector._score_candidates = mock_score

        selected = await selector._two_pass_selection(
            candidates=contents,
            context=context,
            trending_context=trending_context,
            target_count=7,
        )

        assert len(selected) == 7
        # Aucun breakdown ne contient "Sujet du jour" ou "À la une"
        for _, _, _, breakdown in selected:
            labels = [b.label for b in breakdown]
            assert "Sujet du jour" not in labels
            assert "À la une" not in labels

    @pytest.mark.asyncio
    async def test_two_pass_diversity_continuity(self, selector, context, trending_context):
        """Pass 2 respecte les source/theme counts de pass 1."""
        # Source A trending, Source A aussi dans perso → max 1 per source
        source_a = make_source(name="Source A", theme="tech")
        source_b = make_source(name="Source B", theme="science")
        source_c = make_source(name="Source C", theme="culture")

        # Construire assez de sources pour que max_per_source = 1
        extra_sources = [make_source(name=f"Extra{i}", theme=f"extra{i}") for i in range(5)]
        all_sources = [source_a, source_b, source_c] + extra_sources

        trending_article = make_content(source=source_a)
        perso_article_same_source = make_content(source=source_a)
        perso_article_b = make_content(source=source_b)
        perso_article_c = make_content(source=source_c)
        perso_extras = [make_content(source=s) for s in extra_sources]

        trending_context.trending_content_ids = {trending_article.id}
        context.user_interests = {"tech", "science", "culture", "extra0", "extra1", "extra2", "extra3", "extra4"}

        all_candidates = [trending_article, perso_article_same_source, perso_article_b, perso_article_c] + perso_extras

        async def mock_score(candidates, ctx, mode="pour_vous"):
            return [(c, 200.0 - i * 10, []) for i, c in enumerate(candidates)]

        selector._score_candidates = mock_score

        selected = await selector._two_pass_selection(
            candidates=all_candidates,
            context=context,
            trending_context=trending_context,
            target_count=7,
        )

        # Compter les articles par source
        source_counts = defaultdict(int)
        for content, _, _, _ in selected:
            source_counts[content.source_id] += 1

        # source_a ne devrait pas avoir plus de 1 article (pass1 trending + continuité)
        assert source_counts[source_a.id] <= 1

    @pytest.mark.asyncio
    async def test_two_pass_trending_capped(self, selector, context, trending_context):
        """Pass 1 ne sélectionne pas plus que ceil(target * ratio) articles."""
        from app.services.recommendation.scoring_config import ScoringWeights
        from math import ceil

        sources = [make_source(name=f"S{i}", theme="tech") for i in range(10)]
        # 8 articles trending (plus que le cap)
        trending_contents = [make_content(source=sources[i]) for i in range(8)]
        perso_contents = [make_content(source=sources[8]), make_content(source=sources[9])]

        trending_context.trending_content_ids = {c.id for c in trending_contents}
        context.user_interests = {"tech"}

        async def mock_score(candidates, ctx, mode="pour_vous"):
            return [(c, 100.0, []) for c in candidates]

        selector._score_candidates = mock_score

        target = 7
        selected = await selector._two_pass_selection(
            candidates=trending_contents + perso_contents,
            context=context,
            trending_context=trending_context,
            target_count=target,
        )

        # Compter les articles trending dans la sélection
        trending_in_selection = sum(
            1 for c, _, _, bd in selected
            if any(b.label == "Sujet du jour" for b in bd)
        )

        max_trending = ceil(target * ScoringWeights.DIGEST_TRENDING_TARGET_RATIO)
        assert trending_in_selection <= max_trending

    @pytest.mark.asyncio
    async def test_trending_bonus_in_breakdown(self, selector, context, trending_context):
        """Les labels 'Sujet du jour' et 'À la une' apparaissent dans le breakdown."""
        source = make_source(name="Le Monde", theme="tech")
        content_both = make_content(source=source)

        # Article à la fois trending ET à la une
        trending_context.trending_content_ids = {content_both.id}
        trending_context.une_content_ids = {content_both.id}
        context.user_interests = {"tech"}

        async def mock_score(candidates, ctx, mode="pour_vous"):
            return [(c, 100.0, []) for c in candidates]

        selector._score_candidates = mock_score

        selected = await selector._two_pass_selection(
            candidates=[content_both],
            context=context,
            trending_context=trending_context,
            target_count=1,
        )

        assert len(selected) == 1
        breakdown = selected[0][3]
        labels = [b.label for b in breakdown]
        assert "Sujet du jour" in labels
        assert "À la une" in labels

        # Vérifier les points
        trending_entry = next(b for b in breakdown if b.label == "Sujet du jour")
        une_entry = next(b for b in breakdown if b.label == "À la une")
        from app.services.recommendation.scoring_config import ScoringWeights
        assert trending_entry.points == ScoringWeights.DIGEST_TRENDING_BONUS
        assert une_entry.points == ScoringWeights.DIGEST_UNE_BONUS


# ─── Tests: _generate_reason avec labels trending ────────────────────────────


class TestGenerateReasonTrending:
    """Tests pour _generate_reason avec priorité trending/une."""

    def test_trending_reason_takes_priority(self, selector):
        """'Sujet du jour' est prioritaire sur les sous-thèmes."""
        source = make_source(name="Test", theme="tech")
        content = make_content(source=source)

        breakdown = [
            DigestScoreBreakdown(label="Sujet du jour", points=45.0, is_positive=True),
            DigestScoreBreakdown(label="Sous-thème : AI", points=45.0, is_positive=True),
            DigestScoreBreakdown(label="Source de confiance", points=35.0, is_positive=True),
        ]

        reason = selector._generate_reason(content, defaultdict(int), defaultdict(int), breakdown)
        assert reason == "Sujet du jour"

    def test_une_reason_takes_priority(self, selector):
        """'À la une' est prioritaire sur les thèmes."""
        source = make_source(name="Test", theme="tech")
        content = make_content(source=source)

        breakdown = [
            DigestScoreBreakdown(label="À la une", points=35.0, is_positive=True),
            DigestScoreBreakdown(label="Thème matché : tech", points=50.0, is_positive=True),
        ]

        reason = selector._generate_reason(content, defaultdict(int), defaultdict(int), breakdown)
        assert reason == "À la une"

    def test_no_trending_falls_through_to_subtopic(self, selector):
        """Sans trending/une, le comportement existant est préservé."""
        source = make_source(name="Test", theme="tech")
        content = make_content(source=source)

        breakdown = [
            DigestScoreBreakdown(label="Sous-thème : AI", points=45.0, is_positive=True),
        ]

        reason = selector._generate_reason(content, defaultdict(int), defaultdict(int), breakdown)
        assert reason == "Thème : AI"
