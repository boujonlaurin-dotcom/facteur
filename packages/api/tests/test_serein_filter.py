"""Tests for apply_serein_filter() with is_serene primary + keyword fallback."""

from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.services.recommendation.filter_presets import apply_serein_filter


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
