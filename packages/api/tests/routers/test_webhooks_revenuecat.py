"""Tests for POST /api/webhooks/revenuecat."""

from datetime import datetime, timedelta
from unittest.mock import MagicMock
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.database import get_db
from app.main import app
from app.models.subscription import UserSubscription
from app.routers import webhooks as webhooks_router


@pytest_asyncio.fixture
async def seeded_subscription(db_session):
    """Seed a UserSubscription row in the trial state and override get_db."""
    user_id = uuid4()
    sub = UserSubscription(
        id=uuid4(),
        user_id=user_id,
        status="trial",
        trial_start=datetime.utcnow(),
        trial_end=datetime.utcnow() + timedelta(days=7),
    )
    db_session.add(sub)
    await db_session.commit()

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_db] = _fake_db
    try:
        yield user_id
    finally:
        app.dependency_overrides.pop(get_db, None)


def _set_webhook_secret(monkeypatch, secret: str | None):
    """Force `get_settings()` returned object to expose a chosen secret."""
    monkeypatch.setattr(
        webhooks_router,
        "get_settings",
        lambda: MagicMock(revenuecat_webhook_secret=secret or ""),
    )


@pytest.mark.asyncio
async def test_missing_authorization_returns_401(monkeypatch):
    _set_webhook_secret(monkeypatch, "shh")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post("/api/webhooks/revenuecat", json={"event": {}})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_invalid_authorization_returns_401(monkeypatch):
    _set_webhook_secret(monkeypatch, "shh")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post(
            "/api/webhooks/revenuecat",
            headers={"Authorization": "Bearer wrong"},
            json={"event": {}},
        )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_initial_purchase_activates_subscription(
    monkeypatch, seeded_subscription, db_session
):
    _set_webhook_secret(monkeypatch, "shh")
    expiration_ms = int((datetime.utcnow() + timedelta(days=30)).timestamp() * 1000)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post(
            "/api/webhooks/revenuecat",
            headers={"Authorization": "Bearer shh"},
            json={
                "event": {
                    "type": "INITIAL_PURCHASE",
                    "app_user_id": str(seeded_subscription),
                    "product_id": "facteur_premium_monthly",
                    "expiration_at_ms": expiration_ms,
                }
            },
        )
    assert resp.status_code == 200
    assert resp.json() == {"status": "processed"}

    sub = (
        await db_session.execute(
            select(UserSubscription).where(
                UserSubscription.user_id == seeded_subscription
            )
        )
    ).scalar_one()
    assert sub.status == "active"
    assert sub.product_id == "facteur_premium_monthly"
    assert sub.current_period_end is not None


@pytest.mark.asyncio
async def test_expiration_marks_subscription_expired(
    monkeypatch, seeded_subscription, db_session
):
    _set_webhook_secret(monkeypatch, "shh")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post(
            "/api/webhooks/revenuecat",
            headers={"Authorization": "Bearer shh"},
            json={
                "event": {
                    "type": "EXPIRATION",
                    "app_user_id": str(seeded_subscription),
                }
            },
        )
    assert resp.status_code == 200

    sub = (
        await db_session.execute(
            select(UserSubscription).where(
                UserSubscription.user_id == seeded_subscription
            )
        )
    ).scalar_one()
    assert sub.status == "expired"


@pytest.mark.asyncio
async def test_event_without_app_user_id_is_ignored(monkeypatch):
    _set_webhook_secret(monkeypatch, "shh")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post(
            "/api/webhooks/revenuecat",
            headers={"Authorization": "Bearer shh"},
            json={"event": {"type": "INITIAL_PURCHASE"}},
        )
    assert resp.status_code == 200
    assert resp.json() == {"status": "ignored"}


@pytest.mark.asyncio
async def test_unknown_event_type_does_not_error(monkeypatch, seeded_subscription):
    _set_webhook_secret(monkeypatch, "shh")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post(
            "/api/webhooks/revenuecat",
            headers={"Authorization": "Bearer shh"},
            json={
                "event": {
                    "type": "PRODUCT_CHANGE",
                    "app_user_id": str(seeded_subscription),
                }
            },
        )
    assert resp.status_code == 200
    assert resp.json() == {"status": "processed"}


@pytest.mark.asyncio
async def test_no_secret_configured_skips_auth(monkeypatch):
    """If `REVENUECAT_WEBHOOK_SECRET` is unset (dev), don't require auth."""
    _set_webhook_secret(monkeypatch, "")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post(
            "/api/webhooks/revenuecat",
            json={"event": {"type": "RENEWAL"}},
        )
    assert resp.status_code == 200
