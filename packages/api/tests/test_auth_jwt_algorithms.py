"""JWT verification hardening tests."""

from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.dependencies import get_current_user_id


def _credentials(token: str = "token") -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


@pytest.mark.asyncio
async def test_hs256_token_is_rejected_without_decode():
    with patch(
        "app.dependencies.jwt.get_unverified_header",
        return_value={"alg": "HS256"},
    ), patch("app.dependencies.jwt.decode") as mock_decode:
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user_id(_credentials())

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Invalid token algorithm"
    mock_decode.assert_not_called()


@pytest.mark.asyncio
async def test_es256_token_uses_jwks_and_returns_user_id():
    payload = {
        "sub": "00000000-0000-0000-0000-000000000001",
        "email_confirmed_at": "2026-06-16T00:00:00Z",
    }

    with patch(
        "app.dependencies.jwt.get_unverified_header",
        return_value={"alg": "ES256"},
    ), patch(
        "app.dependencies.fetch_jwks",
        new=AsyncMock(return_value={"keys": []}),
    ) as mock_fetch_jwks, patch(
        "app.dependencies.jwt.decode",
        return_value=payload,
    ) as mock_decode:
        user_id = await get_current_user_id(_credentials())

    assert user_id == payload["sub"]
    mock_fetch_jwks.assert_awaited_once()
    mock_decode.assert_called_once_with(
        "token",
        {"keys": []},
        algorithms=["ES256"],
        audience="authenticated",
    )
