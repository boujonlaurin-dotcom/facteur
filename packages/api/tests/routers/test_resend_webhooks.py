"""Vérification cryptographique des webhooks Resend."""

import base64
import hashlib
import hmac
from types import SimpleNamespace
from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.routers.resend_webhooks import _verify_resend_signature


def _signature(secret: str, event_id: str, timestamp: str, payload: bytes) -> str:
    key = base64.b64decode(secret.removeprefix("whsec_") + "===")
    signed = b".".join((event_id.encode(), timestamp.encode(), payload))
    value = base64.b64encode(hmac.new(key, signed, hashlib.sha256).digest()).decode()
    return f"v1,{value}"


def test_resend_signature_accepts_raw_payload():
    secret = "whsec_c2VjcmV0"
    payload = b'{"type":"email.delivered"}'
    with patch(
        "app.routers.resend_webhooks.get_settings",
        return_value=SimpleNamespace(resend_webhook_secret=secret),
    ):
        _verify_resend_signature(
            payload,
            svix_id="msg_1",
            svix_timestamp="1710000000",
            svix_signature=_signature(secret, "msg_1", "1710000000", payload),
        )


def test_resend_signature_rejects_tampered_payload():
    secret = "whsec_c2VjcmV0"
    payload = b'{"type":"email.delivered"}'
    with (
        patch(
            "app.routers.resend_webhooks.get_settings",
            return_value=SimpleNamespace(resend_webhook_secret=secret),
        ),
        pytest.raises(HTTPException, match="Invalid Resend signature"),
    ):
        _verify_resend_signature(
            payload + b"x",
            svix_id="msg_1",
            svix_timestamp="1710000000",
            svix_signature=_signature(secret, "msg_1", "1710000000", payload),
        )
