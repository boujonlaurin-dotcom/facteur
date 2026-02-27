"""Tests unitaires pour ImportanceDetector.

Story 4.4: Top 3 Briefing Quotidien
Valide le clustering Jaccard et la détection de sujets tendance.
"""
import pytest
import uuid
from datetime import datetime
from unittest.mock import MagicMock

from app.services.briefing.importance_detector import ImportanceDetector, FRENCH_STOP_WORDS


class TestNormalizeTitle:
    """Tests pour la normalisation des titres."""

    def test_normalize_basic_title(self):
        """Test normalisation d'un titre simple."""
        detector = ImportanceDetector()
        tokens = detector.normalize_title("Macron annonce des réformes économiques")
        
        # Devrait contenir les mots clés (sans stop words)
        assert "macron" in tokens
        assert "annonce" in tokens
        assert "reformes" in tokens  # sans accent
        assert "economiques" in tokens  # sans accent

    def test_normalize_removes_stop_words(self):
        """Test que les stop words sont filtrés."""
        detector = ImportanceDetector()
        tokens = detector.normalize_title("Le directeur de la startup est en visite")

        # "le", "de", "la", "est", "en" sont des stop words
        assert "le" not in tokens
        assert "de" not in tokens
        assert "la" not in tokens

        # "directeur", "startup", "visite" devraient rester
        assert "directeur" in tokens
        assert "startup" in tokens
        assert "visite" in tokens

    def test_normalize_removes_accents(self):
        """Test que les accents sont supprimés."""
        detector = ImportanceDetector()
        tokens = detector.normalize_title("Éléphant économique à Genève")
        
        assert "elephant" in tokens
        assert "economique" in tokens
        assert "geneve" in tokens

    def test_normalize_removes_short_words(self):
        """Test que les mots < 3 caractères sont filtrés."""
        detector = ImportanceDetector()
        tokens = detector.normalize_title("Un AI va révolutionner la planète")

        # "ai" et "va" ont moins de 3 caractères
        assert "ai" not in tokens
        assert "va" not in tokens
        # "revolutionner" et "planete" restent
        assert "revolutionner" in tokens
        assert "planete" in tokens

    def test_normalize_empty_string(self):
        """Test avec une chaîne vide."""
        detector = ImportanceDetector()
        tokens = detector.normalize_title("")
        
        assert tokens == set()

    def test_normalize_only_stop_words(self):
        """Test avec uniquement des stop words."""
        detector = ImportanceDetector()
        tokens = detector.normalize_title("Le la les un une des")
        
        assert tokens == set()


class TestJaccardSimilarity:
    """Tests pour le calcul de similarité Jaccard."""

    def test_identical_sets(self):
        """Test avec deux ensembles identiques."""
        detector = ImportanceDetector()
        tokens = {"macron", "reforme", "economie"}
        
        sim = detector.jaccard_similarity(tokens, tokens)
        
        assert sim == 1.0

    def test_completely_different_sets(self):
        """Test avec deux ensembles sans intersection."""
        detector = ImportanceDetector()
        tokens_a = {"macron", "reforme", "economie"}
        tokens_b = {"guerre", "ukraine", "russie"}
        
        sim = detector.jaccard_similarity(tokens_a, tokens_b)
        
        assert sim == 0.0

    def test_partial_overlap(self):
        """Test avec intersection partielle."""
        detector = ImportanceDetector()
        tokens_a = {"macron", "reforme", "economie", "france"}
        tokens_b = {"macron", "annonce", "reforme", "loi"}
        
        # Intersection: {macron, reforme} = 2
        # Union: {macron, reforme, economie, france, annonce, loi} = 6
        # Jaccard = 2/6 = 0.333...
        
        sim = detector.jaccard_similarity(tokens_a, tokens_b)
        
        assert 0.33 <= sim <= 0.34

    def test_empty_set_a(self):
        """Test avec premier ensemble vide."""
        detector = ImportanceDetector()
        tokens_a = set()
        tokens_b = {"macron", "reforme"}
        
        sim = detector.jaccard_similarity(tokens_a, tokens_b)
        
        assert sim == 0.0

    def test_empty_set_b(self):
        """Test avec deuxième ensemble vide."""
        detector = ImportanceDetector()
        tokens_a = {"macron", "reforme"}
        tokens_b = set()
        
        sim = detector.jaccard_similarity(tokens_a, tokens_b)
        
        assert sim == 0.0

    def test_both_empty(self):
        """Test avec les deux ensembles vides."""
        detector = ImportanceDetector()
        
        sim = detector.jaccard_similarity(set(), set())
        
        assert sim == 0.0


class TestDetectTrendingClusters:
    """Tests pour la détection de clusters trending."""

    def _create_mock_content(self, title: str, source_id: uuid.UUID = None) -> MagicMock:
        """Helper pour créer un mock Content."""
        mock = MagicMock()
        mock.id = uuid.uuid4()
        mock.source_id = source_id or uuid.uuid4()
        mock.title = title
        mock.guid = str(uuid.uuid4())
        return mock

    def test_trending_with_3_sources(self):
        """Test détection d'un cluster avec 3 sources différentes."""
        detector = ImportanceDetector(similarity_threshold=0.4, min_sources_for_trending=3)
        
        # Créer 3 articles sur le même sujet de 3 sources différentes
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_c = uuid.uuid4()
        
        contents = [
            self._create_mock_content("Macron annonce réforme fiscale majeure", source_a),
            self._create_mock_content("Macron réforme fiscale annonce Bercy", source_b),
            self._create_mock_content("Macron annonce réforme fiscale contestée", source_c),
        ]
        
        trending = detector.detect_trending_clusters(contents)
        
        # Les 3 articles devraient être marqués comme trending
        assert len(trending) == 3
        for content in contents:
            assert content.id in trending

    def test_not_trending_with_2_sources(self):
        """Test qu'un cluster avec 2 sources n'est pas trending (seuil = 3)."""
        detector = ImportanceDetector(similarity_threshold=0.4, min_sources_for_trending=3)
        
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        
        contents = [
            self._create_mock_content("Macron annonce une grande réforme", source_a),
            self._create_mock_content("Macron présente sa réforme majeure", source_b),
        ]
        
        trending = detector.detect_trending_clusters(contents)
        
        # Aucun article ne devrait être trending
        assert len(trending) == 0

    def test_not_trending_same_source(self):
        """Test qu'un cluster avec une seule source n'est pas trending."""
        detector = ImportanceDetector(similarity_threshold=0.4, min_sources_for_trending=3)
        
        source_a = uuid.uuid4()
        
        contents = [
            self._create_mock_content("Macron annonce une grande réforme", source_a),
            self._create_mock_content("Macron présente sa réforme majeure", source_a),
            self._create_mock_content("La réforme de Macron enfin dévoilée", source_a),
        ]
        
        trending = detector.detect_trending_clusters(contents)
        
        # Tous de la même source, donc pas trending
        assert len(trending) == 0

    def test_multiple_clusters(self):
        """Test avec plusieurs clusters distincts."""
        detector = ImportanceDetector(similarity_threshold=0.4, min_sources_for_trending=3)
        
        # Cluster 1: Sujet Macron (3 sources -> trending)
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_c = uuid.uuid4()
        
        # Cluster 2: Sujet Ukraine (2 sources -> pas trending)
        source_d = uuid.uuid4()
        source_e = uuid.uuid4()
        
        contents = [
            # Cluster 1
            self._create_mock_content("Macron annonce une grande réforme", source_a),
            self._create_mock_content("Macron présente sa réforme", source_b),
            self._create_mock_content("Réforme Macron dévoilée", source_c),
            # Cluster 2
            self._create_mock_content("Ukraine attaque Russie", source_d),
            self._create_mock_content("L'Ukraine contre-attaque", source_e),
        ]
        
        trending = detector.detect_trending_clusters(contents)
        
        # Seuls les 3 premiers articles devraient être trending
        assert len(trending) == 3

    def test_empty_contents(self):
        """Test avec une liste vide."""
        detector = ImportanceDetector()
        
        trending = detector.detect_trending_clusters([])
        
        assert trending == set()


class TestIdentifyUneContents:
    """Tests pour l'identification des contenus Une."""

    def _create_mock_content(self, guid: str) -> MagicMock:
        """Helper pour créer un mock Content avec un GUID spécifique."""
        mock = MagicMock()
        mock.id = uuid.uuid4()
        mock.source_id = uuid.uuid4()
        mock.guid = guid
        return mock

    def test_identify_matching_guids(self):
        """Test identification avec des GUIDs correspondants."""
        detector = ImportanceDetector()
        
        contents = [
            self._create_mock_content("guid-1"),
            self._create_mock_content("guid-2"),
            self._create_mock_content("guid-3"),
        ]
        
        une_guids = {"guid-1", "guid-3"}
        
        une_content_ids = detector.identify_une_contents(contents, une_guids)
        
        # Contenus 1 et 3 devraient être identifiés
        assert contents[0].id in une_content_ids
        assert contents[1].id not in une_content_ids
        assert contents[2].id in une_content_ids

    def test_no_matching_guids(self):
        """Test sans correspondance."""
        detector = ImportanceDetector()
        
        contents = [
            self._create_mock_content("guid-1"),
            self._create_mock_content("guid-2"),
        ]
        
        une_guids = {"other-guid"}
        
        une_content_ids = detector.identify_une_contents(contents, une_guids)
        
        assert len(une_content_ids) == 0

    def test_empty_une_guids(self):
        """Test avec un set de GUIDs vide."""
        detector = ImportanceDetector()
        
        contents = [
            self._create_mock_content("guid-1"),
        ]
        
        une_content_ids = detector.identify_une_contents(contents, set())
        
        assert len(une_content_ids) == 0


class TestImportanceDetectorInit:
    """Tests pour l'initialisation du détecteur."""

    def test_default_values(self):
        """Test des valeurs par défaut."""
        detector = ImportanceDetector()
        
        assert detector.similarity_threshold == 0.4
        assert detector.min_sources_for_trending == 3

    def test_custom_values(self):
        """Test avec des valeurs personnalisées."""
        detector = ImportanceDetector(similarity_threshold=0.5, min_sources_for_trending=4)
        
        assert detector.similarity_threshold == 0.5
        assert detector.min_sources_for_trending == 4

    def test_invalid_threshold_too_high(self):
        """Test avec un seuil trop élevé."""
        with pytest.raises(ValueError):
            ImportanceDetector(similarity_threshold=1.5)

    def test_invalid_threshold_negative(self):
        """Test avec un seuil négatif."""
        with pytest.raises(ValueError):
            ImportanceDetector(similarity_threshold=-0.1)

    def test_invalid_min_sources(self):
        """Test avec min_sources < 2."""
        with pytest.raises(ValueError):
            ImportanceDetector(min_sources_for_trending=1)
