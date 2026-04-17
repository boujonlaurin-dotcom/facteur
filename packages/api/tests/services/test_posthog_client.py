"""Tests for the PostHog wrapper (Story 14.1)."""

from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.services.posthog_client import PostHogClient, derive_cohort_properties


def test_disabled_when_flag_false_no_capture_call():
    client = PostHogClient(api_key="phc_test", host="https://eu", enabled=False)
    # _client is None when disabled — no .capture() attribute, no network.
    assert client._client is None
    assert client.enabled is False
    # Must not raise
    client.capture(user_id=uuid4(), event="anything", properties={})


def test_disabled_when_api_key_empty():
    client = PostHogClient(api_key="", host="https://eu", enabled=True)
    assert client.enabled is False
    assert client._client is None
    client.capture(user_id="abc", event="x")


def test_capture_forwards_to_sdk_when_enabled():
    client = PostHogClient.__new__(PostHogClient)
    client.enabled = True
    mock_sdk = MagicMock()
    client._client = mock_sdk

    uid = uuid4()
    client.capture(user_id=uid, event="waitlist_signup", properties={"source": "web"})

    mock_sdk.capture.assert_called_once_with(
        distinct_id=str(uid),
        event="waitlist_signup",
        properties={"source": "web"},
    )


def test_capture_swallows_sdk_exceptions():
    client = PostHogClient.__new__(PostHogClient)
    client.enabled = True
    mock_sdk = MagicMock()
    mock_sdk.capture.side_effect = RuntimeError("network down")
    client._client = mock_sdk

    # Must not raise — analytics failures never block user flows.
    client.capture(user_id="u", event="x")


def test_identify_forwards_properties():
    client = PostHogClient.__new__(PostHogClient)
    client.enabled = True
    mock_sdk = MagicMock()
    client._client = mock_sdk

    client.identify(user_id="u-1", properties={"acquisition_source": "waitlist"})

    mock_sdk.identify.assert_called_once_with(
        distinct_id="u-1",
        properties={"acquisition_source": "waitlist"},
    )


def test_identify_noop_when_disabled():
    client = PostHogClient(api_key="", host="https://eu", enabled=False)
    # Must not raise, must not call anything.
    client.identify(user_id="u", properties={"a": 1})


def test_derive_cohort_properties_empty_email_returns_false_flags():
    props = derive_cohort_properties(None)
    assert props == {
        "is_creator_ytbeur": False,
        "is_close_to_laurin": False,
    }


def test_derive_cohort_properties_case_insensitive_match():
    with patch("app.services.posthog_client.get_settings") as mock_settings:
        mock_settings.return_value.posthog_creator_emails = "Creator@X.com, other@x.com"
        mock_settings.return_value.posthog_close_circle_emails = "LAURIN@example.com"

        creator_match = derive_cohort_properties("creator@x.com")
        close_match = derive_cohort_properties("laurin@example.com")
        no_match = derive_cohort_properties("random@user.com")

    assert creator_match == {
        "is_creator_ytbeur": True,
        "is_close_to_laurin": False,
    }
    assert close_match == {
        "is_creator_ytbeur": False,
        "is_close_to_laurin": True,
    }
    assert no_match == {
        "is_creator_ytbeur": False,
        "is_close_to_laurin": False,
    }
