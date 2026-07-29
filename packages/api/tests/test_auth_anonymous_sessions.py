"""Sessions anonymes Supabase (story 31.1 — onboarding sans compte).

Une session anonyme n'a par construction ni email ni `email_confirmed_at` : sans
ces gardes, tout l'onboarding (sources, sous-sujets, profil) répondrait 403 avant
même que l'utilisateur ait vu un écran.
"""

from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException

from app.dependencies import get_current_user_id

_JWKS = {"keys": [{"kid": "test-key"}]}


def _decode_patch(payload: dict):
    return patch("app.dependencies.jwt.decode", return_value=payload)


@pytest.mark.asyncio
async def test_anonymous_jwt_is_accepted_without_db_roundtrip():
    credentials = SimpleNamespace(credentials="anon-token")

    with (
        patch(
            "app.dependencies.jwt.get_unverified_header",
            return_value={"alg": "ES256"},
        ),
        patch("app.dependencies.fetch_jwks", new=AsyncMock(return_value=_JWKS)),
        _decode_patch(
            {
                "sub": "anon-user-1",
                "is_anonymous": True,
                "app_metadata": {"provider": "email"},
            }
        ),
        patch(
            "app.dependencies._check_email_confirmed_with_retry",
            new=AsyncMock(return_value=False),
        ) as mock_db_check,
    ):
        user_id = await get_current_user_id(credentials)

    assert user_id == "anon-user-1"
    # Le claim suffit : pas de requête DB sur le chemin chaud de l'onboarding.
    mock_db_check.assert_not_awaited()


@pytest.mark.asyncio
async def test_unconfirmed_non_anonymous_still_blocked():
    """La garde historique reste intacte : `is_anonymous` absent ⇒ 403."""
    credentials = SimpleNamespace(credentials="unconfirmed-token")

    with (
        patch(
            "app.dependencies.jwt.get_unverified_header",
            return_value={"alg": "ES256"},
        ),
        patch("app.dependencies.fetch_jwks", new=AsyncMock(return_value=_JWKS)),
        _decode_patch(
            {
                "sub": "user-42",
                "app_metadata": {"provider": "email"},
            }
        ),
        patch(
            "app.dependencies._check_email_confirmed_with_retry",
            new=AsyncMock(return_value=False),
        ),
        pytest.raises(HTTPException) as exc_info,
    ):
        await get_current_user_id(credentials)

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "Email not confirmed"


@pytest.mark.asyncio
async def test_db_fallback_accepts_anonymous_row():
    """JWT sans claim (token émis avant la conversion) : la DB tranche.

    `_check_email_confirmed_with_retry` lit désormais `is_anonymous` en plus de
    `email_confirmed_at`, donc une ligne anonyme remonte `True`.
    """
    from app.dependencies import (
        _check_email_confirmed_with_retry,
        _email_confirmed_cache,
    )

    _email_confirmed_cache.clear()

    class _FakeResult:
        def fetchone(self):
            return (None, True)

    class _FakeSession:
        async def execute(self, *args, **kwargs):
            return _FakeResult()

    class _FakeSessionCtx:
        async def __aenter__(self):
            return _FakeSession()

        async def __aexit__(self, *args):
            return False

    with patch("app.database.safe_async_session", return_value=_FakeSessionCtx()):
        confirmed = await _check_email_confirmed_with_retry("anon-user-2")

    assert confirmed is True
    _email_confirmed_cache.clear()
