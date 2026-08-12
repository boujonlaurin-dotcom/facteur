"""L'adresse de soutien provient du JWT déjà vérifié, pas de l'Admin API."""

from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.dependencies import get_current_user_identity


@pytest.mark.asyncio
async def test_current_user_identity_uses_email_claim_after_validation():
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials="token")
    verified_payload = {"sub": "user-1", "email": "u@x.co"}
    with patch(
        "app.dependencies._authenticate_token",
        new=AsyncMock(return_value=verified_payload),
    ):
        identity = await get_current_user_identity(credentials)

    assert identity.user_id == "user-1"
    assert identity.email == "u@x.co"


@pytest.mark.asyncio
async def test_current_user_identity_rejects_missing_email_claim():
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials="token")
    with patch(
        "app.dependencies._authenticate_token",
        new=AsyncMock(return_value={"sub": "user-1"}),
    ):
        with pytest.raises(HTTPException) as exc:
            await get_current_user_identity(credentials)

    assert exc.value.status_code == 422
