"""Unit tests for the Tournée du jour personalized theme mode.

When `?personalized=true` is combined with `?theme=` or `?topic=` on
`/api/feed/`, `_get_candidates` must:
  1. restrict the candidate pool to articles published in the last 24h,
  2. restrict sources to the user's followed sources (with the existing
     two-phase + curated fallback path on empty follow set), and
  3. boost articles whose `Content.topics` overlap `user_subtopics` via a
     secondary ORDER BY (soft boost — does not exclude non-matchers).

When `personalized=False`, the existing exploration mode (chip taps) must
behave exactly as before: no source restriction, no time window, no
subtopic ORDER BY tweak.
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from app.services.recommendation_service import (
    RecommendationService,
    is_personalized_theme_mode,
)


def _stub_scalars(captured: list):
    """Return an async `session.scalars` that captures the compiled SQL."""

    result = MagicMock()
    result.all.return_value = []

    async def _scalars(stmt):
        captured.append(
            stmt.compile(compile_kwargs={"literal_binds": False}).__str__()
        )
        return result

    return _scalars, result


def _make_service():
    session = MagicMock()
    session.rollback = AsyncMock()
    return RecommendationService(session), session


@pytest.mark.asyncio
async def test_personalized_theme_filters_to_followed_sources():
    """personalized=True + theme + followed → SQL restricts to followed sources."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    followed = {uuid4(), uuid4()}

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids=followed,
        ),
        timeout=5.0,
    )

    assert captured, "expected at least one SQL statement to be issued"
    sql = captured[0].lower()
    # Two-phase path → followed-only WHERE clause.
    assert "sources.id in" in sql or "source.id in" in sql, (
        "personalized theme mode should filter on followed sources via "
        f"two-phase. Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_personalized_theme_applies_24h_window():
    """personalized=True + theme → SQL adds Content.published_at >= now-24h."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    assert "published_at" in sql and ">=" in sql, (
        "personalized theme mode should add a published_at >= cutoff filter."
        f" Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_personalized_theme_subtopic_boost_in_order_by():
    """personalized=True + theme + user_subtopics → ORDER BY includes overlap."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids={uuid4()},
            user_subtopics={"ai", "startups"},
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    # `Content.topics.overlap([...])` compiles to the `&&` operator on
    # Postgres dialect; on the default SA dialect it emits "overlap".
    assert "overlap" in sql or "&&" in sql, (
        "subtopic boost should add an overlap-based ORDER BY tie-breaker. "
        f"Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_personalized_theme_no_followed_falls_back_to_curated():
    """personalized=True + theme + no followed sources → curated fallback,
    not two-phase. Section never empty just because user follows nothing."""
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=True,
            followed_source_ids=set(),
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    assert "is_curated" in sql, (
        "personalized theme mode with zero followed sources must fall back "
        f"to the curated query. Got:\n{captured[0]}"
    )


@pytest.mark.asyncio
async def test_explicit_filter_unchanged_when_personalized_false():
    """Regression guard for the exploration chip path.

    theme set + personalized=False → existing behavior: no source
    restriction (all active sources), no 24h window, no subtopic ORDER BY.
    """
    service, session = _make_service()
    captured: list[str] = []
    session.scalars, _ = _stub_scalars(captured)

    await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            theme="tech",
            personalized=False,
            followed_source_ids={uuid4()},
            user_subtopics={"ai"},
        ),
        timeout=5.0,
    )

    sql = captured[0].lower()
    # Exploration mode must NOT restrict on followed sources or curated:
    # neither the followed-source IN-list nor the curated filter applies.
    assert "sources.id in" not in sql and "source.id in" not in sql, (
        "exploration (personalized=False) must not restrict on followed "
        f"sources. Got:\n{captured[0]}"
    )
    # No 24h window either.
    assert ">= " not in sql or "published_at" not in sql, (
        "exploration must not add a 24h published_at filter. "
        f"Got:\n{captured[0]}"
    )
    # No overlap-based ORDER BY.
    assert "overlap" not in sql and "&&" not in sql, (
        "exploration must not add a subtopic overlap ORDER BY. "
        f"Got:\n{captured[0]}"
    )


# ---------------------------------------------------------------------------
# Story 21.2 — Tournée du jour favorite-theme sections fall through to the
# PillarScoringEngine branch instead of the chronological short-circuit.
# ---------------------------------------------------------------------------


class TestPersonalizedThemeModeDispatch:
    """Verify the dispatch flag governing the scoring vs chrono branch."""

    def test_personalized_with_theme_routes_to_scoring(self):
        assert (
            is_personalized_theme_mode(
                personalized=True, theme="tech", topic=None, source_uuid=None
            )
            is True
        )

    def test_personalized_with_topic_routes_to_scoring(self):
        # Story 22.1: custom-topic favorites send `topic=<UUID>` and must
        # also benefit from preference-based ranking on the Tournée.
        assert (
            is_personalized_theme_mode(
                personalized=True, theme=None, topic="some-uuid", source_uuid=None
            )
            is True
        )

    def test_explicit_chip_without_personalized_stays_chronological(self):
        # The exploration / "tout voir" path keeps pure-recency ordering.
        assert (
            is_personalized_theme_mode(
                personalized=False, theme="tech", topic=None, source_uuid=None
            )
            is False
        )

    def test_default_feed_without_theme_is_not_personalized_theme(self):
        # The home /feed (no theme/topic) goes through the standard
        # chronological-diversified or pour_vous scoring path — not this dispatch.
        assert (
            is_personalized_theme_mode(
                personalized=True, theme=None, topic=None, source_uuid=None
            )
            is False
        )

    def test_source_pin_takes_precedence(self):
        # When the caller pins a source (?source_id=…) we keep the existing
        # source-scoped chronological behavior even with personalized=True.
        assert (
            is_personalized_theme_mode(
                personalized=True,
                theme="tech",
                topic=None,
                source_uuid="some-source-uuid",
            )
            is False
        )
