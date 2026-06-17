"""JWT algorithm hardening tests."""

from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException

from app.dependencies import get_current_user_id


@pytest.mark.asyncio
async def test_hs256_token_rejected_before_decode():
    credentials = SimpleNamespace(credentials="hs256-token")

    with (
        patch(
            "app.dependencies.jwt.get_unverified_header",
            return_value={"alg": "HS256"},
        ),
        patch("app.dependencies.jwt.decode") as mock_decode,
        pytest.raises(HTTPException) as exc_info,
    ):
        await get_current_user_id(credentials)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Invalid token: unsupported algorithm"
    mock_decode.assert_not_called()


@pytest.mark.asyncio
async def test_es256_token_decodes_with_supabase_jwks_and_returns_sub():
    credentials = SimpleNamespace(credentials="es256-token")
    jwks = {"keys": [{"kid": "test-key"}]}

    with (
        patch(
            "app.dependencies.jwt.get_unverified_header",
            return_value={"alg": "ES256"},
        ),
        patch(
            "app.dependencies.fetch_jwks",
            new=AsyncMock(return_value=jwks),
        ) as mock_fetch,
        patch(
            "app.dependencies.jwt.decode",
            return_value={
                "sub": "user-123",
                "email_confirmed_at": "2026-06-17T09:00:00Z",
            },
        ) as mock_decode,
    ):
        user_id = await get_current_user_id(credentials)

    assert user_id == "user-123"
    mock_fetch.assert_awaited_once()
    mock_decode.assert_called_once_with(
        "es256-token",
        jwks,
        algorithms=["ES256"],
        audience="authenticated",
    )
