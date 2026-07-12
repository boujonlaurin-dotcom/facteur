"""Tests for URL normalization + WordPress detect() rungs (Story 12.2, T0.1/T1a/T1b)."""

import socket
from unittest.mock import AsyncMock

import pytest

from app.services.rss_parser import DetectedFeed, RSSParser, normalize_input_url

_WP_HOME = (
    "<html><head>"
    '<meta name="generator" content="WordPress 6.5">'
    "</head><body>hello</body></html>"
)
_WP_RSS = (
    '<?xml version="1.0"?><rss version="2.0"><channel><title>Mon Blog</title>'
    "<item><title>Post 1</title><link>https://blog.fr/1</link>"
    "<guid>1</guid></item></channel></rss>"
)


class _FakeResp:
    def __init__(self, status_code=200, text="", content_type="text/html"):
        self.status_code = status_code
        self.text = text
        self.headers = {"content-type": content_type}

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")


@pytest.fixture
def public_dns(monkeypatch):
    def _getaddrinfo(*_a, **_k):
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 443))]

    monkeypatch.setattr(socket, "getaddrinfo", _getaddrinfo)


# ─── T0.1 normalize_input_url (pure) ──────────────────────────────


def test_normalize_strips_tracking_keeps_feed_param():
    out = normalize_input_url(
        "https://Example.com/blog?utm_source=nl&fbclid=x&feed=rss2#frag"
    )
    assert out == "https://example.com/blog?feed=rss2"


def test_normalize_is_idempotent():
    once = normalize_input_url("https://EX.com/?utm_medium=a&gclid=b")
    assert normalize_input_url(once) == once == "https://ex.com/"


def test_normalize_leaves_non_url_untouched():
    assert normalize_input_url("mediapart") == "mediapart"
    assert normalize_input_url("") == ""


def test_normalize_preserves_port_and_path():
    out = normalize_input_url("https://Host.COM:8443/Path/To?igshid=zz")
    assert out == "https://host.com:8443/Path/To"


# ─── T1a: WordPress canonical feed via curl-cffi (Stage 4b) ───────


@pytest.mark.asyncio
async def test_detect_wordpress_feed_via_curl_cffi(monkeypatch, public_dns):
    parser = RSSParser()

    async def fake_safe_get(url, **kwargs):
        # Homepage → WP html (generator meta); every suffix probe → 404.
        if url.rstrip("/") == "https://blog.fr":
            return _FakeResp(200, _WP_HOME, "text/html")
        return _FakeResp(404, "", "text/html")

    monkeypatch.setattr(parser, "_safe_get", AsyncMock(side_effect=fake_safe_get))
    # /feed/ is UA-blocked over httpx but recovered via curl-cffi.
    monkeypatch.setattr(
        parser, "_fetch_with_impersonation", AsyncMock(return_value=_WP_RSS)
    )

    detected = await parser.detect("https://blog.fr")
    assert detected.feed_url == "https://blog.fr/feed/"
    assert detected.title == "Mon Blog"
    await parser.close()


# ─── T1b: WordPress REST → synthetic internal feed (Stage 4c) ─────


@pytest.mark.asyncio
async def test_detect_wordpress_rest_synthetic(monkeypatch, public_dns):
    parser = RSSParser()

    async def fake_safe_get(url, **kwargs):
        if url.rstrip("/") == "https://blog.fr":
            return _FakeResp(200, _WP_HOME, "text/html")
        return _FakeResp(404, "", "text/html")

    monkeypatch.setattr(parser, "_safe_get", AsyncMock(side_effect=fake_safe_get))
    # Canonical /feed/ truly gone → curl-cffi returns nothing.
    monkeypatch.setattr(
        parser, "_fetch_with_impersonation", AsyncMock(return_value=None)
    )
    # A self base URL is configured, and the REST API has posts.
    monkeypatch.setattr(
        "app.services.rss_parser.internal_feed_base_url",
        lambda: "https://api-staging.example.app",
    )
    monkeypatch.setattr(
        "app.services.rss_parser.fetch_wp_posts",
        AsyncMock(
            return_value=[
                {
                    "title": {"rendered": "P1"},
                    "link": "https://blog.fr/1",
                    "date_gmt": "2026-07-01T10:00:00",
                }
            ]
        ),
    )
    monkeypatch.setattr(
        "app.services.rss_parser.fetch_wp_site_info",
        AsyncMock(return_value={"name": "Blog FR", "description": "desc"}),
    )

    detected = await parser.detect("https://blog.fr")
    assert detected.feed_url == (
        "https://api-staging.example.app/internal/feed/wp?host=blog.fr"
    )
    assert detected.title == "Blog FR"
    assert isinstance(detected, DetectedFeed)
    await parser.close()


@pytest.mark.asyncio
async def test_detect_wordpress_rest_disabled_without_base_url(monkeypatch, public_dns):
    parser = RSSParser()

    async def fake_safe_get(url, **kwargs):
        if url.rstrip("/") == "https://blog.fr":
            return _FakeResp(200, _WP_HOME, "text/html")
        return _FakeResp(404, "", "text/html")

    monkeypatch.setattr(parser, "_safe_get", AsyncMock(side_effect=fake_safe_get))
    monkeypatch.setattr(
        parser, "_fetch_with_impersonation", AsyncMock(return_value=None)
    )
    # No self base URL → Stage 4c is skipped (no broken feed_url persisted).
    monkeypatch.setattr("app.services.rss_parser.internal_feed_base_url", lambda: None)

    with pytest.raises(ValueError, match="No RSS feed found"):
        await parser.detect("https://blog.fr")
    await parser.close()
