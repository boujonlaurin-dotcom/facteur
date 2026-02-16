"""Tests for config validation."""

import pytest
from pydantic import ValidationError
from unittest.mock import patch
import os


def test_rss_retention_days_rejects_negative_values():
    """Verify negative rss_retention_days raises ValidationError."""
    # Mock environment to override default
    with patch.dict(os.environ, {"RSS_RETENTION_DAYS": "-1"}):
        from app.config import Settings

        with pytest.raises(ValidationError) as exc_info:
            Settings()

        # Verify error message mentions the dangerous behavior
        error_msg = str(exc_info.value)
        assert "rss_retention_days" in error_msg.lower()
        assert "non-negative" in error_msg.lower()


def test_rss_retention_days_accepts_zero():
    """Verify zero retention days is accepted (edge case: keep nothing)."""
    with patch.dict(os.environ, {"RSS_RETENTION_DAYS": "0"}):
        from app.config import Settings

        # Should not raise - zero means "delete everything older than now"
        settings = Settings()
        assert settings.rss_retention_days == 0


def test_rss_retention_days_accepts_positive_values():
    """Verify positive retention days work correctly."""
    with patch.dict(os.environ, {"RSS_RETENTION_DAYS": "30"}):
        from app.config import Settings

        settings = Settings()
        assert settings.rss_retention_days == 30


def test_rss_retention_days_default_is_14():
    """Verify default retention is 14 days."""
    # Clear env var if set
    with patch.dict(os.environ, {}, clear=True):
        from app.config import Settings

        settings = Settings()
        assert settings.rss_retention_days == 14
