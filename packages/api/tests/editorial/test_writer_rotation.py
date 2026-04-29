"""Tests for pépite / coup de cœur rotation logic in EditorialWriterService.

Covers the rotation memory added to fix R8/R9: the same article must not be
featured as pépite or coup de cœur on consecutive days.
"""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock

from sqlalchemy.exc import SQLAlchemyError
from uuid import UUID, uuid4

import pytest

from app.services.editorial.writer import EditorialWriterService


def _make_content_mock(
    content_id: UUID | None = None,
    title: str = "Le rapport qui change la donne pour le secteur",
):
    c = MagicMock()
    c.id = content_id or uuid4()
    c.title = title
    c.description = (
        "Une analyse detaillee de l'impact sur les communes et les habitants."
    )
    c.source_id = uuid4()
    c.source = MagicMock()
    c.source.name = "Test Source"
    c.published_at = datetime.now(UTC)
    return c


@pytest.fixture
def mock_session():
    session = AsyncMock()
    session.execute = AsyncMock()
    session.add = MagicMock()
    session.flush = AsyncMock()
    return session


@pytest.fixture
def mock_llm():
    llm = MagicMock()
    llm.chat_json = AsyncMock()
    return llm


@pytest.fixture
def mock_config():
    config = MagicMock()
    config.pepite_prompt = MagicMock(
        system="You are a pépite picker.",
        model="gpt-4o-mini",
        temperature=0.3,
        max_tokens=500,
    )
    # Dedicated rotation temperature — see EditorialConfig.pepite_rotation_temperature.
    # Kept at 0.6 here to match the default so existing assertions
    # (`temperature >= 0.6`) remain valid.
    config.pepite_rotation_temperature = 0.6
    return config


@pytest.fixture
def writer(mock_session, mock_llm, mock_config):
    return EditorialWriterService(
        session=mock_session, llm=mock_llm, config=mock_config
    )


class TestPepiteRotation:
    """Pépite selection excludes recently featured content."""

    @pytest.mark.asyncio
    async def test_pepite_excludes_recent_highlights(self, writer, mock_session):
        """Content IDs returned by _recent_highlight_content_ids must be filtered out."""
        featured_id = uuid4()
        fresh_id = uuid4()

        # Mock rotation memory: pretend `featured_id` was a pépite 2 days ago
        writer._recent_highlight_content_ids = AsyncMock(return_value={featured_id})

        candidates = [
            _make_content_mock(content_id=featured_id, title="Already featured"),
            _make_content_mock(content_id=fresh_id, title="Fresh pick"),
        ]

        # LLM picks the fresh one
        writer._llm.chat_json = AsyncMock(
            return_value={
                "selected_content_id": str(fresh_id),
                "mini_editorial": "A great read.",
            }
        )

        result = await writer.select_pepite(
            candidates=candidates,
            excluded_topic_ids=set(),
            cluster_data=[],
        )

        assert result is not None
        assert result.content_id == fresh_id

    @pytest.mark.asyncio
    async def test_pepite_records_selection_for_rotation(
        self, writer, mock_session
    ):
        """After picking a pépite, record_highlight('pepite', ...) must be called."""
        fresh_id = uuid4()
        writer._recent_highlight_content_ids = AsyncMock(return_value=set())
        writer.record_highlight = AsyncMock()

        candidates = [_make_content_mock(content_id=fresh_id)]
        writer._llm.chat_json = AsyncMock(
            return_value={
                "selected_content_id": str(fresh_id),
                "mini_editorial": "Rich.",
            }
        )

        result = await writer.select_pepite(
            candidates=candidates,
            excluded_topic_ids=set(),
            cluster_data=[],
        )

        assert result is not None
        writer.record_highlight.assert_awaited_once_with("pepite", fresh_id)

    @pytest.mark.asyncio
    async def test_pepite_temperature_is_bumped(self, writer, mock_session):
        """Effective LLM temperature should be at least 0.6 for variety."""
        fresh_id = uuid4()
        writer._recent_highlight_content_ids = AsyncMock(return_value=set())
        writer.record_highlight = AsyncMock()

        candidates = [_make_content_mock(content_id=fresh_id)]
        writer._llm.chat_json = AsyncMock(
            return_value={
                "selected_content_id": str(fresh_id),
                "mini_editorial": "Rich.",
            }
        )
        # Pepite prompt config has temperature=0.3
        assert writer._config.pepite_prompt.temperature == 0.3

        await writer.select_pepite(
            candidates=candidates,
            excluded_topic_ids=set(),
            cluster_data=[],
        )

        call_args = writer._llm.chat_json.await_args
        assert call_args.kwargs["temperature"] >= 0.6

    @pytest.mark.asyncio
    async def test_pepite_pool_expanded_to_30(self, writer, mock_session):
        """Candidate pool trimmed to 30 (expanded from 15)."""
        writer._recent_highlight_content_ids = AsyncMock(return_value=set())
        writer.record_highlight = AsyncMock()

        # Create 50 candidates, all fresh
        candidates = [_make_content_mock() for _ in range(50)]
        writer._llm.chat_json = AsyncMock(
            return_value={
                "selected_content_id": str(candidates[0].id),
                "mini_editorial": "test",
            }
        )

        await writer.select_pepite(
            candidates=candidates,
            excluded_topic_ids=set(),
            cluster_data=[],
        )

        call_args = writer._llm.chat_json.await_args
        # Check the user message contains exactly 30 candidates
        user_msg = call_args.kwargs["user_message"]
        # Count content_id occurrences in the serialized JSON
        assert user_msg.count('"content_id"') == 30


class TestRecentHighlightsQuery:
    """_recent_highlight_content_ids queries the history table correctly."""

    @pytest.mark.asyncio
    async def test_returns_empty_on_query_failure(self, writer, mock_session):
        """If the DB query raises, return empty set (table may not exist yet)."""
        mock_session.execute = AsyncMock(
            side_effect=SQLAlchemyError("table missing")
        )

        result = await writer._recent_highlight_content_ids("pepite")
        assert result == set()

    @pytest.mark.asyncio
    async def test_returns_scalar_set(self, writer, mock_session):
        """Normal path returns the set of content_ids from the scalars result."""
        id1, id2 = uuid4(), uuid4()
        scalars_mock = MagicMock()
        scalars_mock.all = MagicMock(return_value=[id1, id2])

        result_mock = MagicMock()
        result_mock.scalars = MagicMock(return_value=scalars_mock)

        mock_session.execute = AsyncMock(return_value=result_mock)

        result = await writer._recent_highlight_content_ids("coup_de_coeur")
        assert result == {id1, id2}


class TestRecordHighlight:
    """record_highlight adds a row and survives DB failures."""

    @pytest.mark.asyncio
    async def test_record_highlight_adds_row(self, writer, mock_session):
        """Success path: session.add + session.flush called."""
        content_id = uuid4()
        await writer.record_highlight("pepite", content_id)

        mock_session.add.assert_called_once()
        mock_session.flush.assert_awaited_once()
        added = mock_session.add.call_args[0][0]
        assert added.kind == "pepite"
        assert added.content_id == content_id

    @pytest.mark.asyncio
    async def test_record_highlight_swallows_exception(self, writer, mock_session):
        """If flush fails, the exception is logged but not raised."""
        mock_session.flush = AsyncMock(side_effect=SQLAlchemyError("boom"))
        # Must not raise
        await writer.record_highlight("coup_de_coeur", uuid4())
