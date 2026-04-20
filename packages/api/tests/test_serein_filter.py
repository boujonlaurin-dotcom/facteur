"""Tests for apply_serein_filter() with is_serene primary + keyword fallback."""

from dataclasses import dataclass, field
from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.services.recommendation.filter_presets import (
    apply_serein_filter,
    is_cluster_serein_compatible,
)


@pytest.fixture
async def serein_source(db_session):
    """Source with a neutral theme (not in SEREIN_EXCLUDED_THEMES)."""
    source = Source(
        id=uuid4(),
        name="Science Daily",
        url="https://science.example.com",
        feed_url=f"https://science.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="science",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()
    return source


@pytest.fixture
async def politics_source(db_session):
    """Source with an excluded theme (politics ∈ SEREIN_EXCLUDED_THEMES)."""
    source = Source(
        id=uuid4(),
        name="Political News",
        url="https://politics.example.com",
        feed_url=f"https://politics.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="politics",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()
    return source


async def _create_content(db_session, source, title, description=None, is_serene=None):
    """Helper to create a Content row."""
    content = Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        guid=f"guid-{uuid4()}",
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        description=description,
        is_serene=is_serene,
    )
    db_session.add(content)
    await db_session.commit()
    return content


async def _query_with_serein_filter(db_session, source):
    """Run a SELECT on contents joined with source, applying serein filter."""
    query = select(Content).join(Source, Content.source_id == Source.id)
    query = query.where(Content.source_id == source.id)
    query = apply_serein_filter(query)
    result = await db_session.execute(query)
    return result.scalars().all()


class TestSereinFilterWithIsSerene:
    """Tests for is_serene as primary filter source."""

    async def test_is_serene_true_passes(self, db_session, serein_source):
        """Article with is_serene=True passes the filter."""
        content = await _create_content(
            db_session, serein_source, "Découverte scientifique", is_serene=True
        )
        results = await _query_with_serein_filter(db_session, serein_source)
        assert content.id in [r.id for r in results]

    async def test_is_serene_false_blocked(self, db_session, serein_source):
        """Article with is_serene=False is blocked by the filter."""
        content = await _create_content(
            db_session, serein_source, "Innovation tech", is_serene=False
        )
        results = await _query_with_serein_filter(db_session, serein_source)
        assert content.id not in [r.id for r in results]

    async def test_is_serene_true_overrides_anxious_title(self, db_session, serein_source):
        """is_serene=True lets article pass even with anxious keywords in title."""
        content = await _create_content(
            db_session,
            serein_source,
            "La guerre des étoiles : nouvelle découverte",
            is_serene=True,
        )
        results = await _query_with_serein_filter(db_session, serein_source)
        assert content.id in [r.id for r in results]

    async def test_is_serene_false_overrides_neutral_title(self, db_session, serein_source):
        """is_serene=False blocks article even with neutral title."""
        content = await _create_content(
            db_session,
            serein_source,
            "Nouvelle recette de cuisine japonaise",
            is_serene=False,
        )
        results = await _query_with_serein_filter(db_session, serein_source)
        assert content.id not in [r.id for r in results]


class TestSereinFilterFallbackKeywords:
    """Tests for keyword fallback when is_serene is NULL."""

    async def test_null_serene_neutral_title_passes(self, db_session, serein_source):
        """Article with is_serene=None and neutral title/theme passes via fallback."""
        content = await _create_content(
            db_session,
            serein_source,
            "Les bienfaits de la méditation",
            is_serene=None,
        )
        results = await _query_with_serein_filter(db_session, serein_source)
        assert content.id in [r.id for r in results]

    async def test_null_serene_anxious_title_blocked(self, db_session, serein_source):
        """Article with is_serene=None and anxious keyword in title is blocked."""
        content = await _create_content(
            db_session,
            serein_source,
            "Guerre en Ukraine : escalade du conflit",
            is_serene=None,
        )
        results = await _query_with_serein_filter(db_session, serein_source)
        assert content.id not in [r.id for r in results]

    async def test_null_serene_anxious_description_blocked(self, db_session, serein_source):
        """Article with is_serene=None and anxious keyword in description is blocked."""
        content = await _create_content(
            db_session,
            serein_source,
            "Dernières nouvelles",
            description="Le terrorisme frappe encore la région",
            is_serene=None,
        )
        results = await _query_with_serein_filter(db_session, serein_source)
        assert content.id not in [r.id for r in results]

    async def test_null_serene_excluded_theme_blocked(self, db_session, politics_source):
        """Article with is_serene=None from excluded theme is blocked by fallback."""
        content = await _create_content(
            db_session,
            politics_source,
            "Analyse politique du jour",
            is_serene=None,
        )
        results = await _query_with_serein_filter(db_session, politics_source)
        assert content.id not in [r.id for r in results]


class TestSereinFilterMixed:
    """Tests with mixed is_serene values in the same query."""

    async def test_mixed_serene_values(self, db_session, serein_source):
        """Only is_serene=True and NULL-with-neutral pass; False and NULL-with-anxious blocked."""
        serene_tagged = await _create_content(
            db_session, serein_source, "Belle journée ensoleillée", is_serene=True
        )
        not_serene = await _create_content(
            db_session, serein_source, "Titre neutre", is_serene=False
        )
        null_neutral = await _create_content(
            db_session, serein_source, "Recette de gâteau", is_serene=None
        )
        null_anxious = await _create_content(
            db_session, serein_source, "Violence dans les rues", is_serene=None
        )

        results = await _query_with_serein_filter(db_session, serein_source)
        result_ids = [r.id for r in results]

        assert serene_tagged.id in result_ids
        assert not_serene.id not in result_ids
        assert null_neutral.id in result_ids
        assert null_anxious.id not in result_ids


# --- Fixtures for sensitive_themes tests ---


@pytest.fixture
async def tech_source(db_session):
    """Source with theme 'tech' (normally NOT excluded by default serein filter)."""
    source = Source(
        id=uuid4(),
        name="Tech News",
        url="https://tech.example.com",
        feed_url=f"https://tech.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()
    return source


async def _query_with_serein_filter_custom(db_session, source, sensitive_themes=None):
    """Run a SELECT with serein filter + custom sensitive_themes."""
    query = select(Content).join(Source, Content.source_id == Source.id)
    query = query.where(Content.source_id == source.id)
    query = apply_serein_filter(query, sensitive_themes=sensitive_themes)
    result = await db_session.execute(query)
    return result.scalars().all()


class TestSereinFilterSensitiveThemes:
    """Tests for user-personalized sensitive_themes."""

    async def test_sensitive_theme_excludes_untagged_articles(
        self, db_session, tech_source
    ):
        """Articles from a user-sensitive theme are excluded when is_serene=None."""
        content = await _create_content(
            db_session, tech_source, "Nouveau processeur AMD", is_serene=None
        )
        results = await _query_with_serein_filter_custom(
            db_session, tech_source, sensitive_themes=["tech"]
        )
        assert content.id not in [r.id for r in results]

    async def test_sensitive_theme_overrides_llm_is_serene_true(
        self, db_session, tech_source
    ):
        """User-personalized theme exclusion overrides LLM is_serene=True.

        Nouveau comportement : une fois l'utilisateur personnalisé
        (sensitive_themes non-None), ses exclusions s'appliquent verbatim
        et un choix explicite l'emporte sur la classification LLM.
        """
        content = await _create_content(
            db_session, tech_source, "Innovation IA", is_serene=True
        )
        results = await _query_with_serein_filter_custom(
            db_session, tech_source, sensitive_themes=["tech"]
        )
        assert content.id not in [r.id for r in results]

    async def test_custom_themes_replace_defaults(
        self, db_session, politics_source
    ):
        """Custom sensitive_themes REPLACE defaults (no union).

        New semantic: once the user personalizes, the stored list is used
        verbatim. Default excluded themes no longer apply automatically.
        """
        content = await _create_content(
            db_session, politics_source, "Débat parlementaire", is_serene=None
        )
        results = await _query_with_serein_filter_custom(
            db_session, politics_source, sensitive_themes=["tech"]
        )
        # politics is NOT in ["tech"], so the article passes.
        assert content.id in [r.id for r in results]

    async def test_none_sensitive_themes_applies_defaults(
        self, db_session, tech_source
    ):
        """sensitive_themes=None applies the SEREIN_EXCLUDED_THEMES defaults."""
        content = await _create_content(
            db_session, tech_source, "Article tech neutre", is_serene=None
        )
        results = await _query_with_serein_filter_custom(
            db_session, tech_source, sensitive_themes=None
        )
        # Tech is NOT in default excluded themes, so article passes.
        assert content.id in [r.id for r in results]

    async def test_empty_sensitive_themes_means_no_theme_exclusion(
        self, db_session, politics_source
    ):
        """Personalized empty list = aucune exclusion thématique appliquée.

        Distinct from `None` (defaults). A user who explicitly unchecks every
        theme in the UI persists `sensitive_themes=[]`, and expects no theme
        to be excluded — only the LLM `is_serene` path filters then.
        """
        content = await _create_content(
            db_session, politics_source, "Débat parlementaire", is_serene=None
        )
        results = await _query_with_serein_filter_custom(
            db_session, politics_source, sensitive_themes=[]
        )
        # Politics article passes because the user opted out of all theme
        # exclusions (empty list ≠ defaults).
        assert content.id in [r.id for r in results]


class TestIsClusterSereinCompatibleSensitiveThemes:
    """Tests for is_cluster_serein_compatible with user sensitive_themes."""

    @staticmethod
    def _make_cluster(theme, titles=None):
        """Build a minimal TopicCluster-like object for testing."""

        @dataclass
        class FakeContent:
            title: str | None = None
            description: str | None = None

        @dataclass
        class FakeCluster:
            cluster_id: str = "test"
            label: str = "test"
            tokens: set = field(default_factory=set)
            contents: list = field(default_factory=list)
            source_ids: set = field(default_factory=set)
            theme: str | None = None

        contents = [FakeContent(title=t) for t in (titles or ["Neutral article"])]
        return FakeCluster(theme=theme, contents=contents)

    def test_default_excluded_theme_incompatible(self):
        """Cluster with default excluded theme is incompatible."""
        cluster = self._make_cluster("politics")
        assert not is_cluster_serein_compatible(cluster)

    def test_neutral_theme_compatible_by_default(self):
        """Cluster with non-excluded theme is compatible by default."""
        cluster = self._make_cluster("tech")
        assert is_cluster_serein_compatible(cluster)

    def test_user_sensitive_theme_makes_incompatible(self):
        """Cluster with user-sensitive theme becomes incompatible."""
        cluster = self._make_cluster("tech")
        assert not is_cluster_serein_compatible(cluster, sensitive_themes=["tech"])

    def test_custom_themes_replace_defaults(self):
        """Custom sensitive_themes REPLACE defaults (no union).

        New semantic: user-provided list is used verbatim. Defaults no
        longer apply once the caller passes an explicit list.
        """
        cluster = self._make_cluster("society")
        # society not in ["tech"], so the cluster is now compatible.
        assert is_cluster_serein_compatible(cluster, sensitive_themes=["tech"])

    def test_none_sensitive_themes_backward_compatible(self):
        """sensitive_themes=None applies the defaults (backward compat)."""
        tech_cluster = self._make_cluster("tech")
        politics_cluster = self._make_cluster("politics")
        assert is_cluster_serein_compatible(tech_cluster, sensitive_themes=None)
        assert not is_cluster_serein_compatible(politics_cluster, sensitive_themes=None)

    def test_empty_sensitive_themes_means_no_theme_exclusion(self):
        """Personalized empty list = aucune exclusion thématique (≠ None)."""
        politics_cluster = self._make_cluster("politics")
        # User personalized to exclude no theme → politics passes here.
        assert is_cluster_serein_compatible(politics_cluster, sensitive_themes=[])


# ---------------------------------------------------------------------------
# Quote selection tests
# ---------------------------------------------------------------------------

from unittest.mock import patch

from app.services.digest_service import _select_daily_quote


class TestSelectDailyQuote:
    """Unit tests for deterministic quote selection logic."""

    SAMPLE_QUOTES = [
        {"text": "Il faut imaginer Sisyphe heureux.", "author": "Albert Camus"},
        {"text": "La vie est trop courte pour être petite.", "author": "Benjamin Disraeli"},
        {"text": "On ne naît pas femme, on le devient.", "author": "Simone de Beauvoir"},
    ]

    def test_deterministic_same_user_same_date(self):
        """Same user + same date always returns the same quote."""
        with patch("app.services.digest_service._QUOTES", self.SAMPLE_QUOTES):
            q1 = _select_daily_quote("user-123", "2026-04-09")
            q2 = _select_daily_quote("user-123", "2026-04-09")
        assert q1 is not None
        assert q1["author"] == q2["author"]

    def test_different_date_may_differ(self):
        """Different dates can yield different quotes (not guaranteed but usually differs)."""
        with patch("app.services.digest_service._QUOTES", self.SAMPLE_QUOTES):
            results = {
                _select_daily_quote("user-123", f"2026-04-{d:02d}")["author"]
                for d in range(1, 10)
            }
        # With 3 quotes and 9 dates, at least 2 distinct quotes should appear
        assert len(results) > 1

    def test_empty_pool_returns_none(self):
        """Returns None when the quote pool is empty."""
        with patch("app.services.digest_service._load_quotes", return_value=[]):
            result = _select_daily_quote("user-123", "2026-04-09")
        assert result is None

    def test_missing_yaml_returns_none(self, tmp_path):
        """Returns None gracefully when serein_quotes.yaml is missing."""
        import app.services.digest_service as svc

        bad_path = tmp_path / "nonexistent.yaml"
        original_quotes = svc._QUOTES[:]
        original_path = svc._QUOTES_PATH
        try:
            svc._QUOTES = []
            svc._QUOTES_PATH = bad_path
            result = _select_daily_quote("user-123", "2026-04-09")
        finally:
            svc._QUOTES = original_quotes
            svc._QUOTES_PATH = original_path
        assert result is None

    def test_invalid_yaml_entries_filtered(self, tmp_path):
        """Entries without text or author are excluded from the pool."""
        import app.services.digest_service as svc

        yaml_content = """
quotes:
  - text: "Valid quote."
    author: "Valid Author"
  - author: "Missing text"
  - text: "Missing author"
  - text: ""
    author: "Empty text"
"""
        yaml_file = tmp_path / "quotes.yaml"
        yaml_file.write_text(yaml_content)

        original_quotes = svc._QUOTES[:]
        original_path = svc._QUOTES_PATH
        try:
            svc._QUOTES = []
            svc._QUOTES_PATH = yaml_file
            quotes = svc._load_quotes()
        finally:
            svc._QUOTES = original_quotes
            svc._QUOTES_PATH = original_path

        assert len(quotes) == 1
        assert quotes[0]["author"] == "Valid Author"
