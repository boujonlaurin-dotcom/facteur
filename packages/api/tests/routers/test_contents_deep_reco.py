"""Unit tests for the pre-computed « Pas de recul » wiring in the perspectives
endpoint (reader integration, story 27.1).

The deep recommendation is now pre-computed once per batch in the editorial
pipeline and persisted in ``content_deep_recommendations``. The reader only
*reads* that store — no LLM call at open time. These tests cover:
- ``_deep_row_to_dict`` — renders a stored reco (matched Content + reason) as
  the mobile-ready card dict, with a neutral default reason.
- ``_attach_deep_from_store`` — maps the stored row (match / sentinel / absent)
  onto ``deep_recommendation`` + ``deep_pending`` (always resolved).
"""

from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.models.enums import ContentType
from app.routers.contents import _attach_deep_from_store, _deep_row_to_dict


def _make_matched_content() -> SimpleNamespace:
    return SimpleNamespace(
        id=uuid4(),
        title="Pourquoi le système de retraite craque",
        url="https://theconversation.com/retraites-123",
        thumbnail_url="https://img.example/thumb.jpg",
        content_type=ContentType.ARTICLE,
        source_id=uuid4(),
        source=SimpleNamespace(
            name="The Conversation", logo_url="https://img.example/logo.png"
        ),
        published_at=datetime(2026, 1, 5, tzinfo=UTC),
        description="Un éclairage de fond.",
    )


class _FakeResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value

    def scalars(self):
        return self

    def first(self):
        return self._value


class _FakeDB:
    """Returns queued results for successive ``execute`` calls."""

    def __init__(self, *values):
        self._values = list(values)

    async def execute(self, _stmt):
        return _FakeResult(self._values.pop(0))


class TestDeepRowToDict:
    def test_renders_full_card(self):
        content = _make_matched_content()
        d = _deep_row_to_dict(content, "Analyse structurelle du modèle")

        assert d["content_id"] == str(content.id)
        assert d["title"] == content.title
        assert d["url"] == content.url
        assert d["thumbnail_url"] == content.thumbnail_url
        assert d["content_type"] == "article"
        assert d["source_name"] == "The Conversation"
        assert d["source_logo_url"] == "https://img.example/logo.png"
        assert d["published_at"] == content.published_at.isoformat()
        assert d["match_reason"] == "Analyse structurelle du modèle"
        assert d["description"] == content.description

    def test_default_reason_when_none(self):
        d = _deep_row_to_dict(_make_matched_content(), None)
        assert d["match_reason"]  # non-empty neutral fallback

    def test_youtube_content_type_serialized_as_string(self):
        content = _make_matched_content()
        content.content_type = ContentType.YOUTUBE
        d = _deep_row_to_dict(content, "r")
        assert d["content_type"] == "youtube"


@pytest.mark.asyncio
class TestAttachDeepFromStore:
    async def test_absent_row_yields_no_card(self):
        body: dict = {}
        await _attach_deep_from_store(_FakeDB(None), body, uuid4())
        assert body["deep_recommendation"] is None
        assert body["deep_pending"] is False

    async def test_sentinel_row_yields_no_card(self):
        row = SimpleNamespace(matched_content_id=None, match_reason=None)
        body: dict = {}
        await _attach_deep_from_store(_FakeDB(row), body, uuid4())
        assert body["deep_recommendation"] is None
        assert body["deep_pending"] is False

    async def test_match_renders_card(self):
        matched = _make_matched_content()
        row = SimpleNamespace(
            matched_content_id=matched.id, match_reason="Pour comprendre le fond"
        )
        body: dict = {}
        await _attach_deep_from_store(_FakeDB(row, matched), body, uuid4())

        assert body["deep_pending"] is False
        assert body["deep_recommendation"]["content_id"] == str(matched.id)
        assert body["deep_recommendation"]["match_reason"] == "Pour comprendre le fond"

    async def test_dangling_match_yields_no_card(self):
        # Row points to a matched_content_id that no longer exists.
        row = SimpleNamespace(matched_content_id=uuid4(), match_reason="r")
        body: dict = {}
        await _attach_deep_from_store(_FakeDB(row, None), body, uuid4())
        assert body["deep_recommendation"] is None
        assert body["deep_pending"] is False
