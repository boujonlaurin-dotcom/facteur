"""Unit tests for the « Pas de recul » deep recommendation wiring in the
perspectives endpoint (reader integration, PR 1).

Covers the pure helpers that attach a deep recommendation to a perspectives
response body without hitting the DB:
- ``_deep_reco_to_dict`` — renders a MatchedDeepArticle (+ its Content) as the
  mobile-ready card dict.
- ``_apply_deep_from_cache`` — maps the deep cache state (hit / known-empty /
  pending) onto ``deep_recommendation`` + ``deep_pending``.
- ``_attach_deep_recommendation`` — schedules a background match on a miss.
"""

from datetime import UTC, datetime
from unittest.mock import MagicMock
from uuid import uuid4

import pytest

import app.routers.contents as contents
from app.models.enums import ContentType
from app.routers.contents import (
    _DEEP_NO_MATCH,
    _apply_deep_from_cache,
    _attach_deep_recommendation,
    _deep_reco_to_dict,
)
from app.services.editorial.schemas import MatchedDeepArticle


@pytest.fixture(autouse=True)
def _clear_deep_caches():
    contents._deep_reco_cache.clear()
    contents._deep_reco_inflight.clear()
    yield
    contents._deep_reco_cache.clear()
    contents._deep_reco_inflight.clear()


class _FakeBackgroundTasks:
    def __init__(self):
        self.tasks = []

    def add_task(self, func, *args, **kwargs):
        self.tasks.append((func, args, kwargs))


def _make_matched() -> MatchedDeepArticle:
    return MatchedDeepArticle(
        content_id=uuid4(),
        title="Pourquoi le système de retraite craque",
        source_name="The Conversation",
        source_id=uuid4(),
        published_at=datetime(2026, 1, 5, tzinfo=UTC),
        match_reason="Analyse structurelle du modèle",
        description="Un éclairage de fond.",
    )


def _make_matched_content() -> MagicMock:
    c = MagicMock()
    c.url = "https://theconversation.com/retraites-123"
    c.thumbnail_url = "https://img.example/thumb.jpg"
    c.content_type = ContentType.ARTICLE
    c.source = MagicMock()
    c.source.logo_url = "https://img.example/logo.png"
    return c


class TestDeepRecoToDict:
    def test_renders_full_card(self):
        matched = _make_matched()
        content = _make_matched_content()
        d = _deep_reco_to_dict(matched, content)

        assert d["content_id"] == str(matched.content_id)
        assert d["title"] == matched.title
        assert d["url"] == content.url
        assert d["thumbnail_url"] == content.thumbnail_url
        assert d["content_type"] == "article"
        assert d["source_name"] == "The Conversation"
        assert d["source_logo_url"] == "https://img.example/logo.png"
        assert d["published_at"] == matched.published_at.isoformat()
        assert d["match_reason"] == matched.match_reason
        assert d["description"] == matched.description

    def test_youtube_content_type_serialized_as_string(self):
        content = _make_matched_content()
        content.content_type = ContentType.YOUTUBE
        d = _deep_reco_to_dict(_make_matched(), content)
        assert d["content_type"] == "youtube"


class TestApplyDeepFromCache:
    def test_miss_marks_pending_unresolved(self):
        body: dict = {}
        resolved = _apply_deep_from_cache(body, "k")
        assert resolved is False
        assert body["deep_recommendation"] is None
        assert body["deep_pending"] is True

    def test_no_match_sentinel_resolves_empty(self):
        contents._deep_reco_cache["k"] = _DEEP_NO_MATCH
        body: dict = {}
        resolved = _apply_deep_from_cache(body, "k")
        assert resolved is True
        assert body["deep_recommendation"] is None
        assert body["deep_pending"] is False

    def test_hit_resolves_with_dict(self):
        deep = {"content_id": "abc", "title": "T"}
        contents._deep_reco_cache["k"] = deep
        body: dict = {}
        resolved = _apply_deep_from_cache(body, "k")
        assert resolved is True
        assert body["deep_recommendation"] == deep
        assert body["deep_pending"] is False

    def test_miss_preserves_prior_pending_state(self):
        # A background perspectives refresh rebuilds the body; an in-flight
        # deep match must not be erased.
        prev = {"deep_recommendation": None, "deep_pending": True}
        body: dict = {}
        resolved = _apply_deep_from_cache(body, "k", prev_body=prev)
        assert resolved is False
        assert body["deep_pending"] is True


class TestAttachDeepRecommendation:
    def test_schedules_background_match_on_miss(self):
        body: dict = {}
        bg = _FakeBackgroundTasks()
        cid = uuid4()
        _attach_deep_recommendation(body, str(cid), cid, "user-1", bg)

        assert body["deep_pending"] is True
        assert len(bg.tasks) == 1
        func, args, _ = bg.tasks[0]
        assert func is contents._compute_deep_reco_background
        assert args == (str(cid), "user-1")

    def test_no_schedule_when_resolved(self):
        contents._deep_reco_cache["kk"] = _DEEP_NO_MATCH
        body: dict = {}
        bg = _FakeBackgroundTasks()
        _attach_deep_recommendation(body, "kk", uuid4(), "user-1", bg)

        assert body["deep_pending"] is False
        assert bg.tasks == []
