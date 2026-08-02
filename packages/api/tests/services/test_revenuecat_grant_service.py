"""Tests du client grant/revoke RevenueCat (URL, headers, body, erreurs)."""

import pytest

from app.config import get_settings
from app.services.revenuecat_grant_service import (
    RevenueCatGrantError,
    RevenueCatGrantService,
)


class _FakeResp:
    def __init__(self, status_code: int = 200, text: str = ""):
        self.status_code = status_code
        self.text = text


class _FakeClient:
    """Remplace httpx.AsyncClient : enregistre les appels POST."""

    def __init__(self, recorder: list, status_code: int = 200):
        self._rec = recorder
        self._status = status_code

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_a):
        return False

    async def post(self, url, headers=None, json=None):
        self._rec.append({"url": url, "headers": headers, "json": json})
        return _FakeResp(self._status)


def _patch_client(monkeypatch, recorder, status_code=200):
    monkeypatch.setattr(
        "app.services.revenuecat_grant_service.httpx.AsyncClient",
        lambda *_a, **_k: _FakeClient(recorder, status_code),
    )


@pytest.fixture
def configured(monkeypatch):
    monkeypatch.setattr(get_settings(), "revenuecat_rest_api_key", "sk_rc_secret_v1")
    monkeypatch.setattr(get_settings(), "revenuecat_entitlement_id", "premium")


@pytest.mark.asyncio
async def test_grant_posts_to_promotional(configured, monkeypatch):
    rec: list = []
    _patch_client(monkeypatch, rec)
    await RevenueCatGrantService().grant_premium("app-user-1", 1_700_000_000_000)

    assert len(rec) == 1
    assert rec[0]["url"].endswith(
        "/subscribers/app-user-1/entitlements/premium/promotional"
    )
    assert rec[0]["headers"]["Authorization"] == "Bearer sk_rc_secret_v1"
    assert rec[0]["json"] == {"end_time_ms": 1_700_000_000_000}


@pytest.mark.asyncio
async def test_revoke_posts_to_revoke_promotionals(configured, monkeypatch):
    rec: list = []
    _patch_client(monkeypatch, rec)
    await RevenueCatGrantService().revoke_premium("app-user-1")

    assert len(rec) == 1
    assert rec[0]["url"].endswith(
        "/subscribers/app-user-1/entitlements/premium/revoke_promotionals"
    )
    # revoke n'envoie pas de body JSON
    assert rec[0]["json"] is None


@pytest.mark.asyncio
async def test_grant_raises_on_non_2xx(configured, monkeypatch):
    _patch_client(monkeypatch, [], status_code=401)
    with pytest.raises(RevenueCatGrantError):
        await RevenueCatGrantService().grant_premium("u", 1)


@pytest.mark.asyncio
async def test_grant_raises_when_not_configured(monkeypatch):
    monkeypatch.setattr(get_settings(), "revenuecat_rest_api_key", "")
    svc = RevenueCatGrantService()
    assert svc.is_configured is False
    with pytest.raises(RevenueCatGrantError):
        await svc.grant_premium("u", 1)
