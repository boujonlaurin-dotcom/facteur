"""Tests for YouTube video integration in sync_service.

Covers HD thumbnail extraction, description-to-html conversion,
XSS sanitization, and video ID extraction from various URL formats.
"""

import pytest
from unittest.mock import MagicMock, AsyncMock
from uuid import uuid4

from app.services.sync_service import SyncService
from app.models.source import Source
from app.models.enums import SourceType, ContentType


@pytest.fixture
def mock_session():
    session = AsyncMock()
    mock_result = MagicMock()
    mock_scalars = MagicMock()
    mock_result.scalars.return_value = mock_scalars
    mock_scalars.first.return_value = None
    session.execute.return_value = mock_result
    return session


@pytest.fixture
def sync_service(mock_session):
    return SyncService(mock_session)


def _make_youtube_entry(
    link: str,
    title: str = "Test Video",
    description: str = "Video description",
    thumbnail_url: str | None = "https://img.youtube.com/vi/abc123/hqdefault.jpg",
    has_media_group: bool = True,
):
    """Build a mock feedparser entry for a YouTube source."""
    entry = MagicMock()
    data = {
        "title": title,
        "link": link,
        "id": f"yt:video:{link.split('/')[-1]}",
        "published_parsed": (2024, 6, 15, 10, 0, 0, 0, 0, 0),
        "summary": description,
    }
    entry.get.side_effect = lambda k, default=None: data.get(k, default)
    entry.published_parsed = data["published_parsed"]
    entry.summary = description

    if has_media_group:
        media_group = MagicMock()
        media_group.__contains__.side_effect = (
            lambda k: k in ["media_thumbnail", "media_description"]
        )
        media_group.media_thumbnail = (
            [{"url": thumbnail_url}] if thumbnail_url else []
        )
        media_group.media_description = description
        entry.media_group = media_group
        entry.__contains__.side_effect = (
            lambda k: k in data or k == "media_group"
        )
    else:
        entry.__contains__.side_effect = lambda k: k in data

    return entry


@pytest.fixture
def youtube_source():
    return Source(id=uuid4(), type=SourceType.YOUTUBE)


# ---------------------------------------------------------------------------
# 1. HD Thumbnail Extraction
# ---------------------------------------------------------------------------


def test_youtube_hd_thumbnail_extraction(sync_service, youtube_source):
    """YouTube sync should produce an HD maxresdefault thumbnail URL."""
    entry = _make_youtube_entry(
        link="https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        thumbnail_url="https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
    )

    result = sync_service._parse_entry(entry, youtube_source)

    assert result is not None
    assert result["content_type"] == ContentType.YOUTUBE
    assert (
        result["thumbnail_url"]
        == "https://img.youtube.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"
    )


# ---------------------------------------------------------------------------
# 2. Description -> html_content conversion + content_quality
# ---------------------------------------------------------------------------


def test_youtube_description_to_html_content_full(sync_service, youtube_source):
    """Long YouTube descriptions (>500 chars) get content_quality='full'."""
    long_desc = "A" * 501 + "\nSecond line"
    entry = _make_youtube_entry(
        link="https://www.youtube.com/watch?v=abc123",
        description=long_desc,
    )

    result = sync_service._parse_entry(entry, youtube_source)

    assert result is not None
    assert result["html_content"] is not None
    assert "<br>" in result["html_content"]
    assert result["html_content"].startswith("<p>")
    assert result["html_content"].endswith("</p>")
    assert result["content_quality"] == "full"


def test_youtube_description_to_html_content_partial(sync_service, youtube_source):
    """Short YouTube descriptions (<=500 chars) get content_quality='partial'."""
    short_desc = "Short description"
    entry = _make_youtube_entry(
        link="https://www.youtube.com/watch?v=abc123",
        description=short_desc,
    )

    result = sync_service._parse_entry(entry, youtube_source)

    assert result is not None
    assert result["html_content"] == f"<p>{short_desc}</p>"
    assert result["content_quality"] == "partial"


# ---------------------------------------------------------------------------
# 3. XSS Sanitization
# ---------------------------------------------------------------------------


def test_youtube_description_html_sanitized(sync_service, youtube_source):
    """Script tags in YouTube descriptions must be HTML-escaped."""
    xss_desc = "<script>alert('xss')</script>"
    entry = _make_youtube_entry(
        link="https://www.youtube.com/watch?v=abc123",
        description=xss_desc,
    )

    result = sync_service._parse_entry(entry, youtube_source)

    assert result is not None
    assert "<script>" not in result["html_content"]
    assert "&lt;script&gt;" in result["html_content"]


# ---------------------------------------------------------------------------
# 4. Video ID Extraction from various URL formats
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "url, expected_id",
    [
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://youtube.com/watch?v=abc-123_XY", "abc-123_XY"),
        ("https://youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/watch?v=abc&list=PLxyz", "abc"),
        ("", None),
        ("https://example.com/no-video-here", None),
    ],
)
def test_youtube_video_id_extraction(url, expected_id):
    """_extract_youtube_video_id handles various YouTube URL formats."""
    assert SyncService._extract_youtube_video_id(url) == expected_id


# ---------------------------------------------------------------------------
# 5. HD Thumbnail Fallback
# ---------------------------------------------------------------------------


def test_youtube_hd_thumbnail_fallback(sync_service, youtube_source):
    """When video ID can't be extracted, the RSS thumbnail is kept (optimized)."""
    entry = _make_youtube_entry(
        link="https://example.com/not-a-youtube-url",
        thumbnail_url="https://img.youtube.com/vi/xyz/hqdefault.jpg",
    )

    result = sync_service._parse_entry(entry, youtube_source)

    assert result is not None
    # Video ID can't be extracted from the link, so _optimize_thumbnail_url is
    # called on the original RSS thumbnail. The optimizer extracts 'xyz' via
    # the /vi/ pattern, so it still gets an HD URL.  But the key point is that
    # the code didn't crash and thumbnail_url is not None.
    assert result["thumbnail_url"] is not None
    # The original thumbnail should be preserved (possibly optimized)
    assert "youtube.com" in result["thumbnail_url"]


def test_youtube_hd_thumbnail_fallback_no_thumbnail(sync_service, youtube_source):
    """When there's no thumbnail and no extractable video ID, thumbnail is None."""
    entry = _make_youtube_entry(
        link="https://example.com/not-a-youtube-url",
        thumbnail_url=None,
        has_media_group=False,
    )

    result = sync_service._parse_entry(entry, youtube_source)

    assert result is not None
    assert result["thumbnail_url"] is None
