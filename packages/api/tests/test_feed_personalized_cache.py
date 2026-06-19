"""Unit tests for the personalized-section cache eligibility + variant key
(app-load slowdown fix). Pure predicate functions — no DB / app needed."""

from __future__ import annotations

from app.models.enums import ContentType, FeedFilterMode
from app.routers.feed import (
    _is_default_view,
    _is_personalized_section_view,
    _personalized_variant,
)


def _section_kwargs(**overrides):
    """A baseline personalized theme-section call (the cold-open shape)."""
    base = {
        "offset": 0,
        "content_type": None,
        "mode": None,
        "theme": "tech",
        "topic": None,
        "saved_only": False,
        "has_note": False,
        "source_id": None,
        "entity": None,
        "keyword": None,
        "include_unfollowed": False,
        "followed_only": False,
        "personalized": True,
    }
    base.update(overrides)
    return base


def test_theme_section_is_eligible() -> None:
    assert _is_personalized_section_view(**_section_kwargs())


def test_topic_section_is_eligible() -> None:
    assert _is_personalized_section_view(
        **_section_kwargs(theme=None, topic="123e4567-e89b-12d3-a456-426614174000")
    )


def test_source_section_is_eligible() -> None:
    assert _is_personalized_section_view(
        **_section_kwargs(theme=None, source_id="src-uuid")
    )


def test_not_eligible_without_personalized() -> None:
    assert not _is_personalized_section_view(**_section_kwargs(personalized=False))


def test_not_eligible_with_offset() -> None:
    """Pagination (loadMoreTheme) must bypass the cache."""
    assert not _is_personalized_section_view(**_section_kwargs(offset=20))


def test_not_eligible_with_two_selectors() -> None:
    """Ambiguous selector (theme + source) is not cached."""
    assert not _is_personalized_section_view(
        **_section_kwargs(theme="tech", source_id="src-uuid")
    )


def test_not_eligible_with_no_selector() -> None:
    assert not _is_personalized_section_view(**_section_kwargs(theme=None))


def test_not_eligible_with_extra_filters() -> None:
    for override in (
        {"saved_only": True},
        {"has_note": True},
        {"entity": "Macron"},
        {"keyword": "ia"},
        {"include_unfollowed": True},
        {"followed_only": True},
        {"mode": FeedFilterMode.INSPIRATION},
        {"content_type": ContentType.ARTICLE},
    ):
        assert not _is_personalized_section_view(**_section_kwargs(**override)), (
            override
        )


def test_personalized_view_is_not_default_view() -> None:
    """A personalized section must never match the default-view predicate
    (else it would collide on the variant=None key)."""
    assert not _is_default_view(
        limit=12,
        offset=0,
        content_type=None,
        mode=None,
        serein=False,
        theme="tech",
        topic=None,
        saved_only=False,
        has_note=False,
        source_id=None,
        entity=None,
        keyword=None,
        personalized=True,
    )


def test_variant_is_stable_and_distinct() -> None:
    base = {
        "theme": "tech",
        "topic": None,
        "source_id": None,
        "serein": False,
        "limit": 12,
    }
    v1 = _personalized_variant(**base)
    v2 = _personalized_variant(**base)
    assert v1 == v2  # deterministic
    # Each axis changes the key.
    assert v1 != _personalized_variant(**{**base, "theme": "science"})
    assert v1 != _personalized_variant(**{**base, "serein": True})
    assert v1 != _personalized_variant(**{**base, "limit": 20})
    assert v1 != _personalized_variant(
        **{**base, "theme": None, "source_id": "src-uuid"}
    )


def test_variant_is_never_none() -> None:
    """Always non-None so it never collides with the default-view key."""
    v = _personalized_variant(
        theme=None, topic=None, source_id="src", serein=True, limit=12
    )
    assert isinstance(v, str) and v
