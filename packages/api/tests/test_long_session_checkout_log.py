"""Unit tests for the long_session_checkout log enrichment."""

import time
from types import SimpleNamespace
from unittest.mock import MagicMock

from app import database
from app.database import _maybe_log_long_checkout
from app.middleware.request_context import (
    current_request_method,
    current_request_path,
)


def _make_record(age_seconds: float | None) -> SimpleNamespace:
    """Build a connection_record stub with the given checkout age."""
    checkout_time = None if age_seconds is None else time.monotonic() - age_seconds
    return SimpleNamespace(_checkout_time=checkout_time)


def test_long_checkout_log_includes_endpoint_and_method(monkeypatch):
    """Happy path: endpoint and method from ContextVar propagate to the log."""
    mock_logger = MagicMock()
    monkeypatch.setattr(database, "logger", mock_logger)

    path_token = current_request_path.set("/api/feed/chrono")
    method_token = current_request_method.set("GET")
    try:
        record = _make_record(age_seconds=15.0)
        _maybe_log_long_checkout(record)
    finally:
        current_request_path.reset(path_token)
        current_request_method.reset(method_token)

    assert mock_logger.warning.call_count == 1
    args, kwargs = mock_logger.warning.call_args
    assert args == ("long_session_checkout",)
    assert kwargs["endpoint"] == "/api/feed/chrono"
    assert kwargs["method"] == "GET"
    assert kwargs["duration_s"] >= 15.0
    assert record._checkout_time is None


def test_long_checkout_log_defaults_to_unknown_when_context_missing(monkeypatch):
    """Checkin fired outside an HTTP cycle (e.g. scheduler) falls back to 'unknown'."""
    mock_logger = MagicMock()
    monkeypatch.setattr(database, "logger", mock_logger)

    record = _make_record(age_seconds=12.0)
    _maybe_log_long_checkout(record)

    mock_logger.warning.assert_called_once()
    kwargs = mock_logger.warning.call_args.kwargs
    assert kwargs["endpoint"] == "unknown"
    assert kwargs["method"] == "unknown"


def test_short_checkout_does_not_log(monkeypatch):
    """Duration under threshold must not emit the warning."""
    mock_logger = MagicMock()
    monkeypatch.setattr(database, "logger", mock_logger)

    record = _make_record(age_seconds=1.0)
    _maybe_log_long_checkout(record)

    mock_logger.warning.assert_not_called()
    assert record._checkout_time is None


def test_missing_checkout_time_is_noop(monkeypatch):
    """Absence of _checkout_time attribute must not log or raise."""
    mock_logger = MagicMock()
    monkeypatch.setattr(database, "logger", mock_logger)

    record = _make_record(age_seconds=None)
    _maybe_log_long_checkout(record)

    mock_logger.warning.assert_not_called()
