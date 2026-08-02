"""Tests du token signé de checkout soutien (HS256, aud, exp)."""

from datetime import UTC, datetime, timedelta

import pytest
from jose import jwt

from app.config import get_settings
from app.services.checkout_token import (
    _ALGORITHM,
    _AUDIENCE,
    CheckoutTokenError,
    mint_checkout_token,
    verify_checkout_token,
)

_SECRET = "unit-test-checkout-secret-abc123"


@pytest.fixture
def secret(monkeypatch):
    monkeypatch.setattr(get_settings(), "checkout_link_secret", _SECRET)
    return _SECRET


def test_roundtrip_returns_user_and_email(secret):
    token = mint_checkout_token("user-123", "sender@facteur.app")
    claims = verify_checkout_token(token)
    assert claims == {"user_id": "user-123", "email": "sender@facteur.app"}


def test_expired_token_rejected(secret):
    token = mint_checkout_token("u", "a@b.co", ttl_minutes=-1)
    with pytest.raises(CheckoutTokenError):
        verify_checkout_token(token)


def test_wrong_audience_rejected(secret):
    forged = jwt.encode(
        {
            "sub": "u",
            "email": "a@b.co",
            "aud": "not-soutenir",
            "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp()),
        },
        _SECRET,
        algorithm=_ALGORITHM,
    )
    with pytest.raises(CheckoutTokenError):
        verify_checkout_token(forged)


def test_correct_audience_constant():
    # Garde-fou : l'audience attendue reste stable (le web n'a pas à la deviner).
    assert _AUDIENCE == "soutenir"


def test_tampered_signature_rejected(secret):
    token = mint_checkout_token("u", "a@b.co")
    with pytest.raises(CheckoutTokenError):
        verify_checkout_token(token + "tampered")


def test_wrong_secret_rejected(secret, monkeypatch):
    token = mint_checkout_token("u", "a@b.co")
    monkeypatch.setattr(get_settings(), "checkout_link_secret", "another-secret")
    with pytest.raises(CheckoutTokenError):
        verify_checkout_token(token)


def test_missing_secret_raises(monkeypatch):
    monkeypatch.setattr(get_settings(), "checkout_link_secret", "")
    with pytest.raises(CheckoutTokenError):
        mint_checkout_token("u", "a@b.co")
    with pytest.raises(CheckoutTokenError):
        verify_checkout_token("whatever")
