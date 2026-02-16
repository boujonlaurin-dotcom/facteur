"""Tests for storage cleanup worker."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime, timedelta, timezone


@pytest.mark.asyncio
async def test_cleanup_deletes_old_articles():
    """Verify cleanup deletes articles older than retention period."""
    mock_session = AsyncMock()

    # Mock count query: 150 articles to delete
    mock_count_result = MagicMock()
    mock_count_result.scalar_one.return_value = 150

    # Mock delete result: 150 rows deleted
    mock_delete_result = MagicMock()
    mock_delete_result.rowcount = 150

    mock_session.execute.side_effect = [mock_count_result, mock_delete_result]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.async_session_maker", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 14

        from app.workers.storage_cleanup import cleanup_old_articles
        result = await cleanup_old_articles()

    assert result["deleted_count"] == 150
    assert result["retention_days"] == 14
    mock_session.commit.assert_called_once()


@pytest.mark.asyncio
async def test_cleanup_skips_when_no_old_articles():
    """Verify cleanup skips gracefully when no articles to delete."""
    mock_session = AsyncMock()

    # Mock count query: 0 articles to delete
    mock_count_result = MagicMock()
    mock_count_result.scalar_one.return_value = 0

    mock_session.execute.return_value = mock_count_result

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.async_session_maker", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 14

        from app.workers.storage_cleanup import cleanup_old_articles
        result = await cleanup_old_articles()

    assert result["deleted_count"] == 0
    assert result["retention_days"] == 14
    # No commit needed when nothing to delete
    mock_session.commit.assert_not_called()


@pytest.mark.asyncio
async def test_cleanup_rollback_on_error():
    """Verify cleanup rolls back on database error."""
    mock_session = AsyncMock()

    # Mock count query succeeds
    mock_count_result = MagicMock()
    mock_count_result.scalar_one.return_value = 50

    # Mock delete raises an error
    mock_session.execute.side_effect = [mock_count_result, Exception("DB connection lost")]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.async_session_maker", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 14

        from app.workers.storage_cleanup import cleanup_old_articles
        with pytest.raises(Exception, match="DB connection lost"):
            await cleanup_old_articles()

    mock_session.rollback.assert_called_once()
    mock_session.commit.assert_not_called()


@pytest.mark.asyncio
async def test_cleanup_respects_custom_retention_days():
    """Verify cleanup uses configured retention days."""
    mock_session = AsyncMock()

    mock_count_result = MagicMock()
    mock_count_result.scalar_one.return_value = 0
    mock_session.execute.return_value = mock_count_result

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.async_session_maker", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 7

        from app.workers.storage_cleanup import cleanup_old_articles
        result = await cleanup_old_articles()

    assert result["retention_days"] == 7


@pytest.mark.asyncio
async def test_cleanup_logs_statistics():
    """Verify cleanup logs start, completion, and skip events."""
    mock_session = AsyncMock()

    mock_count_result = MagicMock()
    mock_count_result.scalar_one.return_value = 100

    mock_delete_result = MagicMock()
    mock_delete_result.rowcount = 100

    mock_session.execute.side_effect = [mock_count_result, mock_delete_result]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.async_session_maker", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings, \
         patch("app.workers.storage_cleanup.logger") as mock_logger:
        mock_settings.rss_retention_days = 14

        from app.workers.storage_cleanup import cleanup_old_articles
        await cleanup_old_articles()

    # Verify start and completion logs
    log_events = [call.args[0] for call in mock_logger.info.call_args_list]
    assert "storage_cleanup_started" in log_events
    assert "storage_cleanup_completed" in log_events
