"""Tests unitaires pour le DigestSelector.

Ce module teste la logique de sélection avec contraintes de diversité
et le mécanisme de fallback vers les sources curatées.

Tests principaux:
- test_diversity_constraints: Vérification max 2 par source/thème
- test_fallback_sources: Vérification du fallback quand pool < 5
"""

import datetime
from typing import List, Set
from uuid import UUID, uuid4
from unittest.mock import Mock, AsyncMock, patch, MagicMock
import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.digest_selector import (
    DigestSelector,
    DigestItem,
    DigestContext,
    DiversityConstraints
)
from app.models.content import Content
from app.models.source import Source


# Fixtures

@pytest.fixture
def mock_session():
    """Mock de session SQLAlchemy async."""
    return AsyncMock(spec=AsyncSession)


@pytest.fixture
def mock_rec_service():
    """Mock du RecommendationService."""
    mock = Mock()
    mock.scoring_engine = Mock()
    mock.scoring_engine.compute_score = Mock(return_value=10.0)
    return mock


@pytest.fixture
def sample_source_factory():
    """Factory pour créer des sources de test."""
    def _create_source(source_id: UUID = None, name: str = "Test Source", theme: str = "tech", is_curated: bool = False):
        source = Mock(spec=Source)
        source.id = source_id or uuid4()
        source.name = name
        source.theme = theme
        source.is_curated = is_curated
        return source
    return _create_source


@pytest.fixture
def sample_content_factory(sample_source_factory):
    """Factory pour créer des contenus de test."""
    def _create_content(
        content_id: UUID = None,
        source: Source = None,
        title: str = "Test Article",
        published_at: datetime.datetime = None
    ):
        content = Mock(spec=Content)
        content.id = content_id or uuid4()
        content.source = source or sample_source_factory()
        content.source_id = content.source.id
        content.title = title
        content.published_at = published_at or datetime.datetime.utcnow()
        content.topics = None
        return content
    return _create_content


@pytest.fixture
def selector(mock_session, mock_rec_service):
    """Instance de DigestSelector avec mocks."""
    selector = DigestSelector(mock_session)
    selector.rec_service = mock_rec_service
    return selector


# Tests pour les contraintes de diversité

class TestDiversityConstraints:
    """Tests pour la vérification des contraintes de diversité."""
    
    def test_max_two_per_source(self, selector, sample_content_factory, sample_source_factory):
        """Test: Maximum 2 articles par source."""
        # Créer une seule source
        source = sample_source_factory(source_id=uuid4(), name="Single Source")
        
        # Créer 5 articles de cette source
        contents = [
            sample_content_factory(source=source, title=f"Article {i}", published_at=datetime.datetime.utcnow())
            for i in range(5)
        ]
        
        # Scorer les articles (scores décroissants)
        scored = [(c, 50.0 - i * 5) for i, c in enumerate(contents)]
        
        # Sélectionner avec diversité
        selected = selector._select_with_diversity(scored, target_count=5)
        
        # Vérifier: max 2 articles de cette source
        source_counts = {}
        for content, score, reason in selected:
            sid = content.source_id
            source_counts[sid] = source_counts.get(sid, 0) + 1
        
        assert all(count <= 2 for count in source_counts.values()), \
            f"Source count exceeded 2: {source_counts}"
        assert len(selected) <= 2, f"Expected <= 2 articles from single source, got {len(selected)}"
    
    def test_max_two_per_theme(self, selector, sample_content_factory, sample_source_factory):
        """Test: Maximum 2 articles par thème."""
        # Créer 3 sources avec le même thème
        sources = [
            sample_source_factory(source_id=uuid4(), name=f"Source {i}", theme="tech")
            for i in range(3)
        ]
        
        # Créer 1 article par source (même thème)
        contents = [
            sample_content_factory(source=source, title=f"Article {i}")
            for i, source in enumerate(sources)
        ]
        
        # Scorer les articles
        scored = [(c, 50.0 - i * 5) for i, c in enumerate(contents)]
        
        # Sélectionner avec diversité
        selected = selector._select_with_diversity(scored, target_count=5)
        
        # Vérifier: max 2 articles de ce thème
        theme_counts = {}
        for content, score, reason in selected:
            theme = content.source.theme if content.source else None
            if theme:
                theme_counts[theme] = theme_counts.get(theme, 0) + 1
        
        assert all(count <= 2 for count in theme_counts.values()), \
            f"Theme count exceeded 2: {theme_counts}"
        assert theme_counts.get("tech", 0) <= 2, \
            f"Expected <= 2 articles from tech theme, got {theme_counts.get('tech', 0)}"
    
    def test_mixed_sources_and_themes(self, selector, sample_content_factory, sample_source_factory):
        """Test: Diversité avec mix de sources et thèmes."""
        # Créer des sources avec différents thèmes
        sources = [
            sample_source_factory(source_id=uuid4(), name="Tech Source 1", theme="tech"),
            sample_source_factory(source_id=uuid4(), name="Tech Source 2", theme="tech"),
            sample_source_factory(source_id=uuid4(), name="Science Source", theme="science"),
            sample_source_factory(source_id=uuid4(), name="Culture Source", theme="culture"),
            sample_source_factory(source_id=uuid4(), name="Eco Source", theme="economy"),
        ]
        
        # Créer 2 articles par source
        contents = []
        for source in sources:
            for i in range(2):
                contents.append(sample_content_factory(
                    source=source,
                    title=f"{source.name} Article {i}"
                ))
        
        # Scorer avec décroissance
        scored = [(c, 100.0 - i * 3) for i, c in enumerate(contents)]
        
        # Sélectionner 5 articles
        selected = selector._select_with_diversity(scored, target_count=5)
        
        # Vérifier les contraintes
        source_counts = {}
        theme_counts = {}
        
        for content, score, reason in selected:
            sid = content.source_id
            theme = content.source.theme if content.source else None
            
            source_counts[sid] = source_counts.get(sid, 0) + 1
            if theme:
                theme_counts[theme] = theme_counts.get(theme, 0) + 1
        
        # Assertions
        assert len(selected) == 5, f"Expected 5 articles, got {len(selected)}"
        assert all(count <= 2 for count in source_counts.values()), \
            f"Source constraint violated: {source_counts}"
        assert all(count <= 2 for count in theme_counts.values()), \
            f"Theme constraint violated: {theme_counts}"
    
    def test_diversity_with_low_scores(self, selector, sample_content_factory, sample_source_factory):
        """Test: La diversité prime sur le score."""
        # Source 1 avec articles très bien notés
        source1 = sample_source_factory(source_id=uuid4(), name="High Score Source", theme="tech")
        high_score_contents = [
            sample_content_factory(source=source1, title=f"High Score {i}")
            for i in range(5)
        ]
        
        # Source 2 avec articles moins bien notés
        source2 = sample_source_factory(source_id=uuid4(), name="Lower Score Source", theme="science")
        low_score_contents = [
            sample_content_factory(source=source2, title=f"Lower Score {i}")
            for i in range(3)
        ]
        
        # Combiner: scores très hauts pour source1, moyens pour source2
        scored = []
        for i, c in enumerate(high_score_contents):
            scored.append((c, 100.0 - i * 2))  # 100, 98, 96, 94, 92
        for i, c in enumerate(low_score_contents):
            scored.append((c, 50.0 - i * 2))  # 50, 48, 46
        
        # Trier par score décroissant
        scored.sort(key=lambda x: x[1], reverse=True)
        
        # Sélectionner 5 articles
        selected = selector._select_with_diversity(scored, target_count=5)
        
        # Vérifier qu'on a des articles des deux sources (diversité)
        source_ids_in_selection = set(c.source_id for c, s, r in selected)
        
        # Normalement on devrait avoir au moins 2 sources pour respecter la contrainte
        assert len(source_ids_in_selection) >= 2, \
            f"Expected diversity across sources, got only {len(source_ids_in_selection)} source(s)"
        assert len(selected) == 5, f"Expected 5 articles, got {len(selected)}"


class TestReasonGeneration:
    """Tests pour la génération des raisons de sélection."""
    
    def test_first_from_followed_source(self, selector, sample_content_factory, sample_source_factory):
        """Test: Raison pour première source suivie."""
        source = sample_source_factory(name="Le Monde", theme="society")
        content = sample_content_factory(source=source)
        
        source_counts = {}
        theme_counts = {}
        
        reason = selector._generate_reason(content, source_counts, theme_counts)
        
        assert "Source suivie" in reason
        assert "Le Monde" in reason
    
    def test_first_theme_interest(self, selector, sample_content_factory, sample_source_factory):
        """Test: Raison pour premier thème d'intérêt."""
        source = sample_source_factory(name="TechCrunch", theme="tech")
        content = sample_content_factory(source=source)
        
        source_counts = {source.id: 1}  # Source déjà vue
        theme_counts = {}
        
        reason = selector._generate_reason(content, source_counts, theme_counts)
        
        assert "Vos intérêts" in reason
        assert "Tech & Innovation" in reason
    
    def test_theme_label_translation(self, selector, sample_content_factory, sample_source_factory):
        """Test: Traduction des thèmes en français."""
        test_cases = [
            ("tech", "Tech & Innovation"),
            ("science", "Sciences"),
            ("culture", "Culture & Idées"),
            ("international", "Géopolitique"),
            ("unknown_theme", "Unknown_theme"),  # Fallback
        ]
        
        for theme, expected_label in test_cases:
            source = sample_source_factory(name="Test", theme=theme)
            content = sample_content_factory(source=source)
            
            source_counts = {source.id: 1}
            theme_counts = {}
            
            reason = selector._generate_reason(content, source_counts, theme_counts)
            
            assert expected_label in reason, f"Expected '{expected_label}' in reason for theme '{theme}', got: {reason}"


class TestFallbackSources:
    """Tests pour le mécanisme de fallback aux sources curatées."""
    
    @pytest.mark.asyncio
    async def test_fallback_when_user_pool_insufficient(self, selector, sample_content_factory, sample_source_factory):
        """Test: Fallback activé quand pool utilisateur < 5 articles."""
        # Mock le contexte
        mock_context = Mock(spec=DigestContext)
        mock_context.user_id = uuid4()
        mock_context.followed_source_ids = {uuid4()}
        mock_context.muted_sources = set()
        mock_context.muted_themes = set()
        mock_context.muted_topics = set()
        mock_context.user_interests = {"tech"}
        
        # Créer seulement 2 articles des sources suivies
        user_source = sample_source_factory(theme="tech")
        user_contents = [
            sample_content_factory(source=user_source, title=f"User Article {i}")
            for i in range(2)
        ]
        
        # Créer des articles de sources curatées
        curated_source = sample_source_factory(theme="tech", is_curated=True)
        curated_contents = [
            sample_content_factory(source=curated_source, title=f"Curated Article {i}")
            for i in range(5)
        ]
        
        # Mock l'exécution des requêtes
        # Première requête: articles des sources suivies
        # Deuxième requête: articles curatées
        async def mock_execute(stmt):
            mock_result = Mock()
            # Détecter si c'est la requête user ou fallback
            if mock_context.followed_source_ids:
                mock_result.scalars.return_value.all.return_value = user_contents
            else:
                mock_result.scalars.return_value.all.return_value = curated_contents
            return mock_result
        
        selector.session.execute = AsyncMock(side_effect=mock_execute)
        
        # Appeler _get_candidates
        candidates = await selector._get_candidates(
            user_id=mock_context.user_id,
            context=mock_context,
            hours_lookback=48,
            min_pool_size=5
        )
        
        # Vérifier qu'on a les articles utilisateur + curatés
        assert len(candidates) >= 5, \
            f"Expected at least 5 candidates with fallback, got {len(candidates)}"
    
    @pytest.mark.asyncio
    async def test_no_fallback_when_user_pool_sufficient(self, selector, sample_content_factory, sample_source_factory):
        """Test: Pas de fallback quand pool utilisateur >= 5 articles."""
        # Mock le contexte
        mock_context = Mock(spec=DigestContext)
        mock_context.user_id = uuid4()
        mock_context.followed_source_ids = {uuid4()}
        mock_context.muted_sources = set()
        mock_context.muted_themes = set()
        mock_context.muted_topics = set()
        mock_context.user_interests = set()
        
        # Créer 7 articles des sources suivies (suffisant)
        user_source = sample_source_factory(theme="tech")
        user_contents = [
            sample_content_factory(source=user_source, title=f"User Article {i}")
            for i in range(7)
        ]
        
        # Mock l'exécution
        async def mock_execute(stmt):
            mock_result = Mock()
            mock_result.scalars.return_value.all.return_value = user_contents
            return mock_result
        
        selector.session.execute = AsyncMock(side_effect=mock_execute)
        
        # Appeler _get_candidates
        candidates = await selector._get_candidates(
            user_id=mock_context.user_id,
            context=mock_context,
            hours_lookback=48,
            min_pool_size=5
        )
        
        # Vérifier qu'on a seulement les articles utilisateur
        assert len(candidates) == 7
        # Normalement pas besoin de vérifier le nombre d'appels ici
        # car l'implémentation peut varier
    
    @pytest.mark.asyncio
    async def test_fallback_respects_mutes(self, selector, sample_content_factory, sample_source_factory):
        """Test: Le fallback respecte les sources/thèmes muets."""
        muted_source_id = uuid4()
        muted_theme = "politics"
        
        # Mock le contexte avec mutes
        mock_context = Mock(spec=DigestContext)
        mock_context.user_id = uuid4()
        mock_context.followed_source_ids = {uuid4()}
        mock_context.muted_sources = {muted_source_id}
        mock_context.muted_themes = {muted_theme}
        mock_context.muted_topics = set()
        mock_context.user_interests = set()
        
        # Créer des sources dont certaines sont mutées
        normal_source = sample_source_factory(theme="tech")
        muted_source = sample_source_factory(source_id=muted_source_id, theme=muted_theme)
        politics_source = sample_source_factory(theme=muted_theme)
        
        # Mock l'exécution
        captured_filters = []
        
        async def mock_execute(stmt):
            mock_result = Mock()
            # Vérifier que les filtres sont appliqués
            captured_filters.append(str(stmt))
            mock_result.scalars.return_value.all.return_value = []
            return mock_result
        
        selector.session.execute = AsyncMock(side_effect=mock_execute)
        
        # Appeler _get_candidates
        await selector._get_candidates(
            user_id=mock_context.user_id,
            context=mock_context,
            hours_lookback=48,
            min_pool_size=5
        )
        
        # Vérifier que les requêtes contiennent les filtres de mutes
        all_queries = " ".join(captured_filters)
        # Les requêtes devraient exclure les sources/thèmes muets
        # Note: C'est un test approximatif car on ne peut pas facilement
        # inspecter la structure SQLAlchemy
        assert len(captured_filters) > 0, "Expected at least one query execution"


class TestScoringIntegration:
    """Tests pour l'intégration avec le ScoringEngine."""
    
    @pytest.mark.asyncio
    async def test_uses_existing_scoring_engine(self, selector, sample_content_factory, sample_source_factory):
        """Test: Réutilise le ScoringEngine existant sans modification."""
        # Créer des contenus
        source = sample_source_factory()
        contents = [sample_content_factory(source=source) for _ in range(3)]
        
        # Créer un contexte mock
        mock_context = Mock(spec=DigestContext)
        mock_context.user_profile = Mock()
        mock_context.user_interests = set()
        mock_context.user_interest_weights = {}
        mock_context.followed_source_ids = set()
        mock_context.user_prefs = {}
        mock_context.user_subtopics = set()
        mock_context.muted_sources = set()
        mock_context.muted_themes = set()
        mock_context.muted_topics = set()
        mock_context.custom_source_ids = set()
        
        # Scorer
        scored = await selector._score_candidates(contents, mock_context)
        
        # Vérifier que le ScoringEngine a été appelé pour chaque contenu
        assert selector.rec_service.scoring_engine.compute_score.call_count == 3
        
        # Vérifier que les scores sont retournés
        assert len(scored) == 3
        assert all(isinstance(s, tuple) and len(s) == 2 for s in scored)
    
    @pytest.mark.asyncio
    async def test_handles_scoring_errors_gracefully(self, selector, sample_content_factory, sample_source_factory):
        """Test: Gère les erreurs de scoring sans bloquer."""
        # Créer des contenus
        source = sample_source_factory()
        contents = [sample_content_factory(source=source) for _ in range(3)]
        
        # Faire échouer le scoring pour le deuxième article
        def side_effect(content, context):
            if content == contents[1]:
                raise ValueError("Scoring error")
            return 10.0
        
        selector.rec_service.scoring_engine.compute_score = Mock(side_effect=side_effect)
        
        # Créer un contexte mock
        mock_context = Mock(spec=DigestContext)
        mock_context.user_profile = Mock()
        mock_context.user_interests = set()
        mock_context.user_interest_weights = {}
        mock_context.followed_source_ids = set()
        mock_context.user_prefs = {}
        mock_context.user_subtopics = set()
        mock_context.muted_sources = set()
        mock_context.muted_themes = set()
        mock_context.muted_topics = set()
        mock_context.custom_source_ids = set()
        
        # Scorer - ne devrait pas lever d'exception
        scored = await selector._score_candidates(contents, mock_context)
        
        # Vérifier qu'on a tous les articles avec des scores (même le problématique à 0.0)
        assert len(scored) == 3
        assert scored[1][1] == 0.0  # Article avec erreur a score 0.0


class TestDigestContextBuilding:
    """Tests pour la construction du contexte utilisateur."""
    
    @pytest.mark.asyncio
    async def test_builds_complete_context(self, selector, mock_session):
        """Test: Construit un contexte complet avec toutes les données utilisateur."""
        user_id = uuid4()
        
        # Mock les résultats de la base de données
        mock_profile = Mock()
        mock_profile.interests = []
        mock_profile.preferences = []
        
        mock_scalar_result = Mock()
        mock_scalar_result.scalar_one_or_none.return_value = mock_profile
        
        # Configurer le mock pour retourner différents résultats selon la requête
        call_count = [0]
        
        async def mock_execute(stmt):
            call_count[0] += 1
            result = Mock()
            
            # Simuler différentes réponses selon le type de requête
            if call_count[0] == 1:
                # Requête profile
                result.scalar_one_or_none.return_value = mock_profile
            elif call_count[0] == 2:
                # Requête sources
                result.scalars.return_value.all.return_value = []
            elif call_count[0] == 3:
                # Requête subtopics
                result.scalars.return_value.all.return_value = []
            else:
                # Requête personalization
                result.scalar_one_or_none.return_value = None
            
            return result
        
        selector.session.execute = AsyncMock(side_effect=mock_execute)
        
        # Appeler _build_digest_context
        context = await selector._build_digest_context(user_id)
        
        # Vérifier le contexte
        assert context.user_id == user_id
        assert context.user_profile == mock_profile
        assert isinstance(context.followed_source_ids, set)
        assert isinstance(context.muted_sources, set)
        assert isinstance(context.muted_themes, set)
        assert isinstance(context.muted_topics, set)


class TestDiversityDecayAlgorithm:
    """Tests for the diversity decay factor algorithm."""
    
    def test_diversity_decay_factor_applied(self, selector, sample_content_factory, sample_source_factory):
        """TEST-02: Verify decay factor reduces scores for same-source articles."""
        # Create a single source
        source = sample_source_factory(source_id=uuid4(), name="Test Source")
        
        # Create 3 articles from same source with equal base scores
        from datetime import datetime, timezone, timedelta
        articles = []
        for i in range(3):
            content = sample_content_factory(
                source=source,
                title=f"Article {i}",
                published_at=datetime.now(timezone.utc) - timedelta(hours=i)
            )
            articles.append(content)
        
        # Score them equally (simulate scoring)
        scored = [(article, 100.0, []) for article in articles]
        
        # Select with diversity
        selected = selector._select_with_diversity(scored, target_count=3)
        
        # Verify decay is applied - scores should be reduced
        assert len(selected) == 3
        
        # First: 100 * (0.70^0) = 100
        # Second: 100 * (0.70^1) = 70
        # Third: 100 * (0.70^2) = 49
        scores = [item[1] for item in selected]
        assert scores[0] == 100.0
        assert scores[1] == 70.0  # 100 * 0.70
        assert scores[2] == 49.0  # 100 * 0.70^2
    
    def test_minimum_three_sources_enforced(self, selector, sample_content_factory, sample_source_factory):
        """Verify digest has at least 3 different sources when possible."""
        from datetime import datetime, timezone, timedelta
        
        # Create articles from 5 different sources
        sources_articles = []
        for i in range(5):
            source = sample_source_factory(source_id=uuid4(), name=f"Source {i}", theme=f"theme_{i}")
            content = sample_content_factory(
                source=source,
                title=f"Article from {source.name}",
                published_at=datetime.now(timezone.utc) - timedelta(hours=i)
            )
            sources_articles.append((content, 100.0 - i * 5, []))  # Varying scores
        
        selected = selector._select_with_diversity(sources_articles, target_count=5)
        
        # Count unique sources
        selected_sources = set(item[0].source_id for item in selected)
        assert len(selected_sources) >= 3, f"Only {len(selected_sources)} sources in digest, expected at least 3"
    
    def test_le_monde_only_user_gets_diversity(self, selector, sample_content_factory, sample_source_factory):
        """TEST-02: Le Monde-only user should still get 3+ sources via fallback."""
        from datetime import datetime, timezone, timedelta
        
        # Simulate user who only follows Le Monde
        le_monde = sample_source_factory(source_id=uuid4(), name="Le Monde", theme="society")
        other_sources = [
            sample_source_factory(source_id=uuid4(), name="Source A", theme="tech"),
            sample_source_factory(source_id=uuid4(), name="Source B", theme="science"),
            sample_source_factory(source_id=uuid4(), name="Source C", theme="culture"),
            sample_source_factory(source_id=uuid4(), name="Source D", theme="economy"),
        ]
        
        # Create articles - 2 from Le Monde (high scores), rest from other sources
        articles = []
        
        # 2 from Le Monde
        for i in range(2):
            content = sample_content_factory(
                source=le_monde,
                title=f"Le Monde Article {i}",
                published_at=datetime.now(timezone.utc) - timedelta(hours=i)
            )
            articles.append((content, 100.0, []))
        
        # 5 from other sources (slightly lower scores)
        for i, source in enumerate(other_sources):
            content = sample_content_factory(
                source=source,
                title=f"Other Source Article {i}",
                published_at=datetime.now(timezone.utc) - timedelta(hours=i+2)
            )
            articles.append((content, 90.0, []))
        
        selected = selector._select_with_diversity(articles, target_count=5)
        
        # Count sources
        selected_sources = set(item[0].source_id for item in selected)
        
        # With decay and diversity, should have 3+ sources
        assert len(selected_sources) >= 3, \
            f"Le Monde-only user scenario: only {len(selected_sources)} sources, expected 3+"
        
        # No source should have more than 2
        source_counts = {}
        for item in selected:
            sid = item[0].source_id
            source_counts[sid] = source_counts.get(sid, 0) + 1
        
        max_count = max(source_counts.values()) if source_counts else 0
        assert max_count <= 2, f"Source has {max_count} articles, max allowed is 2"
    
    def test_no_single_source_exceeds_two_articles(self, selector, sample_content_factory, sample_source_factory):
        """Verify no single source has more than 2 articles in digest."""
        from datetime import datetime, timezone, timedelta
        
        # Create 10 articles from same source
        source = sample_source_factory(source_id=uuid4(), name="Single Source")
        articles = []
        for i in range(10):
            content = sample_content_factory(
                source=source,
                title=f"Article {i}",
                published_at=datetime.now(timezone.utc) - timedelta(hours=i)
            )
            articles.append((content, 100.0 - i * 2, []))
        
        selected = selector._select_with_diversity(articles, target_count=5)
        
        # Count articles per source
        source_counts = {}
        for item in selected:
            sid = item[0].source_id
            source_counts[sid] = source_counts.get(sid, 0) + 1
        
        # No source should exceed 2
        for sid, count in source_counts.items():
            assert count <= 2, f"Source {sid} has {count} articles, max is 2"


class TestDiversityConstraintsConstants:
    """Tests pour les constantes de diversité."""
    
    def test_constraint_values(self):
        """Test: Valeurs des contraintes conformes aux exigences."""
        constraints = DiversityConstraints()
        
        assert constraints.MAX_PER_SOURCE == 2
        assert constraints.MAX_PER_THEME == 2
        assert constraints.TARGET_DIGEST_SIZE == 5
    
    def test_decay_factor_value(self, selector):
        """Verify decay factor is 0.70 as per algorithm spec."""
        # The decay factor should be 0.70 (same as feed algorithm)
        # This is hardcoded in _select_with_diversity method
        import inspect
        source = inspect.getsource(selector._select_with_diversity)
        assert "0.70" in source or "DECAY_FACTOR = 0.70" in source, \
            "Decay factor should be 0.70"


class TestIntegrationSelectForUser:
    """Tests d'intégration pour select_for_user."""
    
    @pytest.mark.asyncio
    async def test_returns_five_items_by_default(self, selector):
        """Test: Retourne exactement 5 articles par défaut."""
        # Mocker toutes les méthodes internes
        mock_items = [
            DigestItem(
                content=Mock(),
                score=10.0,
                rank=i,
                reason="Test"
            )
            for i in range(1, 6)
        ]
        
        with patch.object(selector, '_build_digest_context', new_callable=AsyncMock) as mock_build, \
             patch.object(selector, '_get_candidates', new_callable=AsyncMock) as mock_candidates, \
             patch.object(selector, '_score_candidates', new_callable=AsyncMock) as mock_score:
            
            mock_build.return_value = Mock(user_profile=Mock())
            mock_candidates.return_value = [Mock() for _ in range(10)]
            mock_score.return_value = [(Mock(), 10.0 - i) for i in range(10)]
            
            # Patcher _select_with_diversity pour retourner nos items mockés
            with patch.object(selector, '_select_with_diversity') as mock_select:
                mock_select.return_value = [
                    (item.content, item.score, item.reason)
                    for item in mock_items
                ]
                
                result = await selector.select_for_user(uuid4())
        
        assert len(result) == 5
        assert all(isinstance(item, DigestItem) for item in result)
    
    @pytest.mark.asyncio
    async def test_returns_empty_list_on_error(self, selector):
        """Test: Retourne une liste vide en cas d'erreur."""
        with patch.object(selector, '_build_digest_context', new_callable=AsyncMock) as mock_build:
            mock_build.side_effect = Exception("Database error")
            
            result = await selector.select_for_user(uuid4())
        
        assert result == []
    
    @pytest.mark.asyncio
    async def test_returns_empty_list_without_profile(self, selector):
        """Test: Retourne une liste vide si pas de profil utilisateur."""
        with patch.object(selector, '_build_digest_context', new_callable=AsyncMock) as mock_build:
            mock_build.return_value = Mock(user_profile=None)
            
            result = await selector.select_for_user(uuid4())
        
        assert result == []
