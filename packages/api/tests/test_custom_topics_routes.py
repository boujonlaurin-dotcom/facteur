"""Anti-regression test: custom_topics route ordering.

Verifies that static routes (/disambiguate, /suggestions) are NOT shadowed
by parameterized routes (/{topic_id}). When /{topic_id} is registered before
static routes, FastAPI matches "disambiguate" as a topic_id and returns 405.

This bug has regressed 3 times — this test prevents it from happening again.
See docs/bugs/bug-custom-topics-405-recurring.md
"""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_post_disambiguate_not_405():
    """POST /disambiguate must not return 405 Method Not Allowed.

    If /{topic_id} is registered before /disambiguate, FastAPI matches
    the path but finds no POST handler → 405.
    """
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post(
            "/api/personalization/topics/disambiguate",
            json={"name": "test topic"},
            headers={"Authorization": "Bearer fake-token"},
        )
        # 401 (auth) or 422 (validation) are fine — 405 means route ordering is broken
        assert resp.status_code != 405, (
            "POST /disambiguate returned 405 — /{topic_id} route is shadowing static routes. "
            "Parameterized routes MUST be registered LAST in custom_topics.py"
        )


@pytest.mark.asyncio
async def test_get_suggestions_not_405():
    """GET /suggestions must not return 405 Method Not Allowed."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get(
            "/api/personalization/topics/suggestions",
            headers={"Authorization": "Bearer fake-token"},
        )
        assert resp.status_code != 405, (
            "GET /suggestions returned 405 — /{topic_id} route is shadowing static routes. "
            "Parameterized routes MUST be registered LAST in custom_topics.py"
        )


@pytest.mark.asyncio
async def test_post_create_topic_not_405():
    """POST / (create topic) must not return 405 Method Not Allowed."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post(
            "/api/personalization/topics/",
            json={"name": "test topic"},
            headers={"Authorization": "Bearer fake-token"},
        )
        assert resp.status_code != 405, (
            "POST /topics/ returned 405 — route registration is broken in custom_topics.py"
        )


@pytest.mark.asyncio
async def test_get_popular_entities_not_405():
    """GET /popular-entities must not return 405 Method Not Allowed."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get(
            "/api/personalization/topics/popular-entities",
            headers={"Authorization": "Bearer fake-token"},
        )
        assert resp.status_code != 405, (
            "GET /popular-entities returned 405 — route registration is broken in custom_topics.py"
        )
