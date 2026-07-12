"""Tests for the synthetic WordPress feed endpoint (Story 12.2, T1b)."""

import socket

import feedparser
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app

_POSTS = [
    {
        "title": {"rendered": "Un post"},
        "link": "https://blog.example.com/1",
        "date_gmt": "2026-07-01T10:00:00",
        "excerpt": {"rendered": "extrait"},
        "content": {"rendered": "corps"},
    }
]


@pytest.fixture
def public_dns(monkeypatch):
    def _getaddrinfo(host, *args, **kwargs):
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 443))]

    monkeypatch.setattr(socket, "getaddrinfo", _getaddrinfo)


async def _get(params):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        return await ac.get("/internal/feed/wp", params=params)


@pytest.mark.asyncio
async def test_wp_feed_happy_path(monkeypatch, public_dns):
    async def fake_posts(root, limit):
        return _POSTS

    async def fake_info(root):
        return {"name": "Blog Example", "description": None}

    monkeypatch.setattr("app.routers.internal_feed.fetch_wp_posts", fake_posts)
    monkeypatch.setattr("app.routers.internal_feed.fetch_wp_site_info", fake_info)

    resp = await _get({"host": "blog.example.com"})
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("application/rss+xml")
    feed = feedparser.parse(resp.text)
    assert not feed.bozo
    assert feed.feed.title == "Blog Example"
    assert feed.entries[0].link == "https://blog.example.com/1"


@pytest.mark.asyncio
async def test_wp_feed_rejects_localhost():
    # SSRF: a localhost host is blocked before any outbound fetch.
    resp = await _get({"host": "localhost"})
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_wp_feed_rejects_loopback_ip():
    resp = await _get({"host": "127.0.0.1"})
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_wp_feed_502_when_no_posts(monkeypatch, public_dns):
    async def fake_posts(root, limit):
        return None

    monkeypatch.setattr("app.routers.internal_feed.fetch_wp_posts", fake_posts)
    resp = await _get({"host": "blog.example.com"})
    assert resp.status_code == 502
