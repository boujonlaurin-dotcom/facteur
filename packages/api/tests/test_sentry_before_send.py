"""Tests for the Sentry before_send filter that drops trafilatura HTTP noise.

See docs/maintenance/maintenance-sentry-trafilatura-filter.md for context.
"""

from app.main import _sentry_before_send


def test_drops_trafilatura_not_a_200_response():
    event = {
        "logger": "trafilatura.downloads",
        "logentry": {"message": "not a 200 response: 404"},
    }
    assert _sentry_before_send(event, {}) is None


def test_drops_trafilatura_download_error():
    event = {
        "logger": "trafilatura",
        "logentry": {"message": "download error: connection refused"},
    }
    assert _sentry_before_send(event, {}) is None


def test_drops_trafilatura_download_error_on_top_level_message():
    # Some Sentry events only carry `message` at the top level, not logentry.
    event = {
        "logger": "trafilatura.core",
        "message": "download error: timeout",
    }
    assert _sentry_before_send(event, {}) is None


def test_passes_trafilatura_event_with_unrelated_message():
    event = {
        "logger": "trafilatura.utils",
        "logentry": {"message": "extracted main content successfully"},
    }
    result = _sentry_before_send(event, {})
    assert result is event


def test_passes_non_trafilatura_logger_with_matching_message():
    # Our own code logging "not a 200 response" must NOT be dropped.
    event = {
        "logger": "app.services.fetcher",
        "logentry": {"message": "not a 200 response from upstream API"},
    }
    result = _sentry_before_send(event, {})
    assert result is event


def test_passes_event_with_no_logger_field():
    event = {
        "logentry": {"message": "not a 200 response"},
    }
    result = _sentry_before_send(event, {})
    assert result is event


def test_case_insensitive_match_on_message():
    event = {
        "logger": "trafilatura.downloads",
        "logentry": {"message": "NOT A 200 RESPONSE: 500"},
    }
    assert _sentry_before_send(event, {}) is None

    event2 = {
        "logger": "trafilatura",
        "logentry": {"message": "Download Error: whatever"},
    }
    assert _sentry_before_send(event2, {}) is None


def test_passes_event_with_empty_message():
    event = {
        "logger": "trafilatura",
        "logentry": {"message": ""},
    }
    result = _sentry_before_send(event, {})
    assert result is event
