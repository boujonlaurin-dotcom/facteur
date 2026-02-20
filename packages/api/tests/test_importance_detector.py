"""Tests unitaires pour ImportanceDetector.

Story 4.4: Top 3 Briefing Quotidien
Valide le clustering Jaccard et la détection de sujets tendance.
"""
import pytest
import uuid
from datetime import datetime
from unittest.mock import MagicMock

from app.services.briefing.importance_detector import ImportanceDetector, TopicCluster, FRENCH_STOP_WORDS


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
        tokens = detector.normalize_title("Le président de la France est en visite")
        
        # "le", "de", "la", "est", "en" sont des stop words
        assert "le" not in tokens
        assert "de" not in tokens
        assert "la" not in tokens
        
        # "president", "france", "visite" devraient rester
        assert "president" in tokens
        assert "france" in tokens
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
        tokens = detector.normalize_title("Un AI va révolutionner le monde")
        
        # "ai" et "va" ont moins de 3 caractères
        assert "ai" not in tokens
        assert "va" not in tokens
        # "revolutionner" et "monde" restent
        assert "revolutionner" in tokens
        assert "monde" in tokens

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
        # Titres avec Jaccard > 0.4 (mots clés: macron, reforme, retraites)
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_c = uuid.uuid4()

        contents = [
            self._create_mock_content("Macron réforme retraites annonce plan", source_a),
            self._create_mock_content("Macron réforme retraites présentation officielle", source_b),
            self._create_mock_content("Macron annonce réforme retraites France", source_c),
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
            self._create_mock_content("Macron réforme retraites annonce plan", source_a),
            self._create_mock_content("Macron réforme retraites présentation officielle", source_a),
            self._create_mock_content("Macron annonce réforme retraites France", source_a),
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
            # Cluster 1 (Jaccard > 0.4 : mots communs macron, reforme, retraites)
            self._create_mock_content("Macron réforme retraites annonce plan", source_a),
            self._create_mock_content("Macron réforme retraites présentation officielle", source_b),
            self._create_mock_content("Macron annonce réforme retraites France", source_c),
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


class TestBuildTopicClusters:
    """Tests pour build_topic_clusters — clustering universel."""

    def _create_mock_content(self, title: str, source_id=None, theme=None):
        mock = MagicMock()
        mock.id = uuid.uuid4()
        mock.source_id = source_id or uuid.uuid4()
        mock.title = title
        mock.guid = str(uuid.uuid4())
        mock.theme = theme
        mock.source = MagicMock()
        mock.source.theme = theme
        return mock

    def test_empty_input(self):
        detector = ImportanceDetector()
        clusters = detector.build_topic_clusters([])
        assert clusters == []

    def test_single_content_returns_singleton_cluster(self):
        detector = ImportanceDetector()
        content = self._create_mock_content("Macron annonce une réforme")
        clusters = detector.build_topic_clusters([content])
        assert len(clusters) == 1
        assert len(clusters[0].contents) == 1
        assert clusters[0].contents[0] is content

    def test_similar_titles_grouped(self):
        """Articles avec titres similaires doivent former un seul cluster."""
        detector = ImportanceDetector(similarity_threshold=0.4)
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_c = uuid.uuid4()

        # Titres avec Jaccard > 0.4 (mots communs : macron, reforme, retraites)
        contents = [
            self._create_mock_content("Macron réforme retraites annonce plan", source_a),
            self._create_mock_content("Macron réforme retraites présentation officielle", source_b),
            self._create_mock_content("Macron annonce réforme retraites France", source_c),
        ]

        clusters = detector.build_topic_clusters(contents)
        # Should form 1 cluster with 3 articles
        assert len(clusters) == 1
        assert len(clusters[0].contents) == 3
        assert len(clusters[0].source_ids) == 3

    def test_dissimilar_titles_separate_clusters(self):
        """Articles très différents doivent former des clusters séparés."""
        detector = ImportanceDetector(similarity_threshold=0.4)
        contents = [
            self._create_mock_content("Macron annonce une grande réforme"),
            self._create_mock_content("Apple lance un nouveau smartphone révolutionnaire"),
        ]
        clusters = detector.build_topic_clusters(contents)
        assert len(clusters) == 2

    def test_clusters_sorted_by_size(self):
        """Les clusters doivent être triés par taille décroissante."""
        detector = ImportanceDetector(similarity_threshold=0.4)
        src1, src2, src3 = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()

        contents = [
            # Cluster 1: unique article
            self._create_mock_content("Apple lance un nouveau produit"),
            # Cluster 2: 3 articles (should be first after sort)
            self._create_mock_content("Macron réforme retraites annonce plan", src1),
            self._create_mock_content("Macron réforme retraites présentation officielle", src2),
            self._create_mock_content("Macron annonce réforme retraites France", src3),
        ]

        clusters = detector.build_topic_clusters(contents)
        assert len(clusters[0].contents) >= len(clusters[-1].contents)

    def test_topic_cluster_properties(self):
        """Vérifie is_trending et is_multi_source."""
        detector = ImportanceDetector(similarity_threshold=0.4)
        src1, src2, src3 = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()

        contents = [
            self._create_mock_content("Macron réforme retraites annonce plan", src1),
            self._create_mock_content("Macron réforme retraites présentation officielle", src2),
            self._create_mock_content("Macron annonce réforme retraites France", src3),
        ]

        clusters = detector.build_topic_clusters(contents)
        cluster = clusters[0]
        assert cluster.is_multi_source is True
        assert cluster.is_trending is True  # 3 sources

    def test_two_sources_multi_source_not_trending(self):
        """Cluster avec 2 sources : is_multi_source=True, is_trending=False."""
        detector = ImportanceDetector(similarity_threshold=0.4)
        src1, src2 = uuid.uuid4(), uuid.uuid4()

        contents = [
            self._create_mock_content("Macron réforme retraites annonce plan", src1),
            self._create_mock_content("Macron réforme retraites présentation officielle", src2),
        ]

        clusters = detector.build_topic_clusters(contents)
        cluster = clusters[0]
        assert cluster.is_multi_source is True
        assert cluster.is_trending is False

    def test_threshold_override(self):
        """Le paramètre similarity_threshold override le seuil de l'instance."""
        detector = ImportanceDetector(similarity_threshold=0.9)  # Très strict
        src1, src2 = uuid.uuid4(), uuid.uuid4()

        # Jaccard entre ces 2 titres ≈ 0.43
        contents = [
            self._create_mock_content("Macron réforme retraites annonce plan", src1),
            self._create_mock_content("Macron réforme retraites présentation officielle", src2),
        ]

        # Avec seuil d'instance strict (0.9) : 2 clusters séparés
        clusters_strict = detector.build_topic_clusters(contents)
        assert len(clusters_strict) == 2

        # Avec override à 0.3 : devrait grouper
        clusters_loose = detector.build_topic_clusters(contents, similarity_threshold=0.3)
        assert len(clusters_loose) == 1

    def test_cluster_has_uuid_id(self):
        """Chaque cluster doit avoir un cluster_id UUID valide."""
        detector = ImportanceDetector()
        content = self._create_mock_content("Test article")
        clusters = detector.build_topic_clusters([content])
        assert clusters[0].cluster_id  # non-empty
        uuid.UUID(clusters[0].cluster_id)  # should not raise

    def test_theme_from_content(self):
        """Le thème dominant est extrait des contenus."""
        detector = ImportanceDetector(similarity_threshold=0.3)
        src1, src2 = uuid.uuid4(), uuid.uuid4()

        contents = [
            self._create_mock_content("Macron réforme retraites annonce plan", src1, theme="politics"),
            self._create_mock_content("Macron réforme retraites présentation officielle", src2, theme="politics"),
        ]

        clusters = detector.build_topic_clusters(contents)
        assert clusters[0].theme == "politics"

    def test_detect_trending_uses_build_topic_clusters(self):
        """detect_trending_clusters doit retourner le même résultat qu'avant le refactoring."""
        detector = ImportanceDetector(similarity_threshold=0.4, min_sources_for_trending=3)
        src1, src2, src3 = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()

        contents = [
            self._create_mock_content("Macron réforme retraites annonce plan", src1),
            self._create_mock_content("Macron réforme retraites présentation officielle", src2),
            self._create_mock_content("Macron annonce réforme retraites France", src3),
        ]

        trending_ids = detector.detect_trending_clusters(contents)
        assert len(trending_ids) == 3
        for c in contents:
            assert c.id in trending_ids
