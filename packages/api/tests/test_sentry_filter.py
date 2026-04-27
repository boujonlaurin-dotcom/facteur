"""Sentry before_send filter — drops predictable RSS fetch noise."""

from app.main import _sentry_before_send


def _logentry(logger_name: str, message: str) -> dict:
    return {"logger": logger_name, "logentry": {"message": message}}


def _exc_event(logger_name: str, exc_value: str) -> dict:
    return {
        "logger": logger_name,
        "exception": {"values": [{"type": "Exception", "value": exc_value}]},
    }


def test_drops_trafilatura_download_error():
    event = _logentry("trafilatura.downloads", "download error: cerveauetpsycho.fr/foo")
    assert _sentry_before_send(event, {}) is None


def test_drops_feedparser_not_200():
    event = _logentry("feedparser", "not a 200 response: 403 for https://tldr.tech/x")
    assert _sentry_before_send(event, {}) is None


def test_drops_rss_sync_read_timeout_in_exception():
    event = _exc_event("app.workers.rss_sync", "HTTPSConnectionPool: Read timed out")
    assert _sentry_before_send(event, {}) is None


def test_drops_rss_parser_404():
    event = _logentry("app.services.rss_parser", "404 Client Error: Not Found")
    assert _sentry_before_send(event, {}) is None


def test_keeps_digest_queuepool_error():
    event = _logentry("app.routers.digest", "QueuePool limit of size 50 overflow")
    assert _sentry_before_send(event, {}) is event


def test_keeps_validation_error():
    event = _exc_event("app.services.digest_service", "ValidationError: bad payload")
    assert _sentry_before_send(event, {}) is event


def test_keeps_trafilatura_unrelated_message():
    event = _logentry("trafilatura.core", "extracted main content successfully")
    assert _sentry_before_send(event, {}) is event
