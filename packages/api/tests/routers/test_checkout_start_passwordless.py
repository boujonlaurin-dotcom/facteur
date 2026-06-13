"""Tests pour POST /api/checkout/start-passwordless."""

import json
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest

from app.routers.checkout import _build_checkout_url


def test_build_checkout_url_default():
    user_id = "abc-123"
    url = _build_checkout_url("default", user_id)
    assert url.startswith("https://pay.rev.cat/facteur-premium")
    assert f"app_user_id={user_id}" in url


def test_build_checkout_url_founder():
    user_id = "abc-123"
    url = _build_checkout_url("founder", user_id)
    assert url.startswith("https://pay.rev.cat/facteur-founder")
    assert f"app_user_id={user_id}" in url


@pytest.mark.asyncio
async def test_start_passwordless_creates_new_user(db_session):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.database import get_db
    from app.routers.checkout import router

    app = FastAPI()
    app.include_router(router, prefix="/api/checkout")
    app.dependency_overrides[get_db] = lambda: db_session

    new_user_id = str(uuid4())

    with patch(
        "app.routers.checkout._supabase_admin_lookup_user_by_email",
        new=AsyncMock(return_value=None),
    ), patch(
        "app.routers.checkout._supabase_admin_create_user",
        new=AsyncMock(return_value=new_user_id),
    ):
        with TestClient(app) as client:
            resp = client.post(
                "/api/checkout/start-passwordless",
                content=json.dumps({"email": "newbie@example.com"}),
                headers={"Content-Type": "application/json"},
            )

    assert resp.status_code == 200
    body = resp.json()
    assert body["user_id"] == new_user_id
    assert body["is_new_user"] is True
    assert "app_user_id" in body["checkout_url"]


@pytest.mark.asyncio
async def test_start_passwordless_reuses_existing_user(db_session):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.database import get_db
    from app.routers.checkout import router

    app = FastAPI()
    app.include_router(router, prefix="/api/checkout")
    app.dependency_overrides[get_db] = lambda: db_session

    existing_user_id = str(uuid4())

    with patch(
        "app.routers.checkout._supabase_admin_lookup_user_by_email",
        new=AsyncMock(return_value=existing_user_id),
    ):
        with TestClient(app) as client:
            resp = client.post(
                "/api/checkout/start-passwordless",
                json={"email": "existing@example.com", "offering": "founder"},
            )

    assert resp.status_code == 200
    body = resp.json()
    assert body["user_id"] == existing_user_id
    assert body["is_new_user"] is False
    assert "facteur-founder" in body["checkout_url"]
