"""Tests for the WordPress REST → synthetic RSS renderer (Story 12.2, T1b)."""

import feedparser

from app.services.wordpress_feed import (
    internal_feed_base_url,
    post_entries,
    render_wp_rss,
    wp_rest_posts_url,
)

_POSTS = [
    {
        "title": {"rendered": "Premier post &amp; suite"},
        "link": "https://blog.example.com/1",
        "guid": {"rendered": "https://blog.example.com/?p=1"},
        "date_gmt": "2026-07-01T10:00:00",
        "excerpt": {"rendered": "<p>Extrait 1</p>"},
        "content": {
            "rendered": "<p>Corps <img src='https://blog.example.com/i.jpg'></p>"
        },
    },
    {
        "title": {"rendered": "Deuxième"},
        "link": "https://blog.example.com/2",
        "date_gmt": "2026-06-30T09:00:00",
        "excerpt": {"rendered": "Extrait 2"},
        "content": {"rendered": "Corps 2"},
    },
]


def test_wp_rest_posts_url_caps_per_page():
    url = wp_rest_posts_url("https://blog.example.com/", 999)
    assert url.startswith("https://blog.example.com/wp-json/wp/v2/posts?")
    assert "per_page=50" in url  # capped at MAX_POSTS
    assert "orderby=date" in url and "order=desc" in url


def test_render_wp_rss_is_parseable():
    xml = render_wp_rss(
        "https://blog.example.com",
        _POSTS,
        site_name="Blog Example",
        site_description="Un blog",
    )
    feed = feedparser.parse(xml)
    assert not feed.bozo, feed.get("bozo_exception")
    assert feed.feed.title == "Blog Example"
    assert len(feed.entries) == 2
    # HTML entities in the title are unescaped by the renderer.
    assert feed.entries[0].title == "Premier post & suite"
    assert feed.entries[0].link == "https://blog.example.com/1"
    # content:encoded is preserved so SyncService can extract a thumbnail.
    assert "i.jpg" in feed.entries[0].content[0].value


def test_render_wp_rss_empty_posts():
    xml = render_wp_rss("https://blog.example.com", [])
    feed = feedparser.parse(xml)
    assert not feed.bozo
    assert feed.entries == []


def test_post_entries_shape():
    entries = post_entries(_POSTS, limit=1)
    assert len(entries) == 1
    assert entries[0]["title"] == "Premier post & suite"
    assert entries[0]["link"] == "https://blog.example.com/1"
    assert entries[0]["published_at"]  # RFC-822 string


def test_internal_feed_base_url_defaults_none(monkeypatch):
    # No setting + no RAILWAY_PUBLIC_DOMAIN → disabled (returns None).
    monkeypatch.delenv("RAILWAY_PUBLIC_DOMAIN", raising=False)
    from app.config import get_settings

    get_settings.cache_clear()
    monkeypatch.setenv("INTERNAL_FEED_BASE_URL", "")
    get_settings.cache_clear()
    assert internal_feed_base_url() is None

    # RAILWAY_PUBLIC_DOMAIN fallback.
    monkeypatch.setenv("RAILWAY_PUBLIC_DOMAIN", "api-staging.up.railway.app")
    assert internal_feed_base_url() == "https://api-staging.up.railway.app"
    get_settings.cache_clear()
