"""Tests for ContentExtractor logging severity classification."""

import urllib3
from structlog.testing import capture_logs

from app.services.content_extractor import ContentExtractor, ExtractedContent


def test_expected_fetch_failure_logged_as_warning(monkeypatch):
    """MaxRetryError (network/paywall) → warning, not error."""

    def boom(url, config=None):
        raise urllib3.exceptions.MaxRetryError(pool=None, url=url, reason=None)

    monkeypatch.setattr("trafilatura.fetch_url", boom)

    extractor = ContentExtractor()
    with capture_logs() as logs:
        result = extractor.extract("https://example.com/paywalled")

    assert isinstance(result, ExtractedContent)
    assert result.html_content is None
    fetch_failed = [log for log in logs if log.get("event") == "content_extractor_fetch_failed"]
    error_logs = [log for log in logs if log.get("event") == "content_extractor_error"]
    assert len(fetch_failed) == 1
    assert fetch_failed[0]["log_level"] == "warning"
    assert fetch_failed[0]["error_type"] == "MaxRetryError"
    assert error_logs == []


def test_unexpected_bug_logged_as_error(monkeypatch):
    """AttributeError (real programming bug) → error with exc_info."""

    def boom(url, config=None):
        raise AttributeError("boom")

    monkeypatch.setattr("trafilatura.fetch_url", boom)

    extractor = ContentExtractor()
    with capture_logs() as logs:
        result = extractor.extract("https://example.com/article")

    assert isinstance(result, ExtractedContent)
    error_logs = [log for log in logs if log.get("event") == "content_extractor_error"]
    fetch_failed = [log for log in logs if log.get("event") == "content_extractor_fetch_failed"]
    assert len(error_logs) == 1
    assert error_logs[0]["log_level"] == "error"
    assert error_logs[0].get("exc_info") is True
    assert fetch_failed == []
