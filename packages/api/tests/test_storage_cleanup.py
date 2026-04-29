"""Tests for storage cleanup worker."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime, timedelta, timezone
from uuid import uuid4


@pytest.fixture(autouse=True)
def _empty_referenced_ids():
    """By default, pretend no digest references any content.

    The digest-reference exclusion query is not the subject of the legacy
    tests below — they care about bookmarks / deep sources. Tests that need
    to exercise the reference exclusion override this explicitly.
    """
    with patch(
        "app.workers.storage_cleanup._collect_referenced_content_ids",
        new=AsyncMock(return_value=set()),
    ):
        yield


@pytest.mark.asyncio
async def test_cleanup_deletes_old_articles():
    """Verify cleanup deletes articles older than retention period."""
    mock_session = AsyncMock()

    # Mock count query (to_delete): 150 articles to delete
    mock_count_to_delete = MagicMock()
    mock_count_to_delete.scalar_one.return_value = 150

    # Mock count query (preserved bookmarks): 10 bookmarks preserved
    mock_count_preserved = MagicMock()
    mock_count_preserved.scalar_one.return_value = 10

    # Mock count query (preserved deep): 5 deep source articles preserved
    mock_count_deep = MagicMock()
    mock_count_deep.scalar_one.return_value = 5

    # Mock delete result: 150 rows deleted
    mock_delete_result = MagicMock()
    mock_delete_result.rowcount = 150

    mock_session.execute.side_effect = [
        mock_count_to_delete,
        mock_count_preserved,
        mock_count_deep,
        mock_delete_result
    ]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.safe_async_session", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 20

        from app.workers.storage_cleanup import cleanup_old_articles
        result = await cleanup_old_articles()

    assert result["deleted_count"] == 150
    assert result["retention_days"] == 20
    assert result["preserved_bookmarks"] == 10
    mock_session.commit.assert_called_once()


@pytest.mark.asyncio
async def test_cleanup_skips_when_no_old_articles():
    """Verify cleanup skips gracefully when no articles to delete."""
    mock_session = AsyncMock()

    # Mock count query (to_delete): 0 articles to delete
    mock_count_to_delete = MagicMock()
    mock_count_to_delete.scalar_one.return_value = 0

    # Mock count query (preserved): 5 bookmarks preserved
    mock_count_preserved = MagicMock()
    mock_count_preserved.scalar_one.return_value = 5

    # Mock count query (preserved deep): 2 deep source articles preserved
    mock_count_deep = MagicMock()
    mock_count_deep.scalar_one.return_value = 2

    mock_session.execute.side_effect = [mock_count_to_delete, mock_count_preserved, mock_count_deep]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.safe_async_session", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 20

        from app.workers.storage_cleanup import cleanup_old_articles
        result = await cleanup_old_articles()

    assert result["deleted_count"] == 0
    assert result["retention_days"] == 20
    assert result["preserved_bookmarks"] == 5
    # No commit needed when nothing to delete
    mock_session.commit.assert_not_called()


@pytest.mark.asyncio
async def test_cleanup_rollback_on_error():
    """Verify cleanup rolls back on database error."""
    mock_session = AsyncMock()

    # Mock count queries succeed
    mock_count_to_delete = MagicMock()
    mock_count_to_delete.scalar_one.return_value = 50

    mock_count_preserved = MagicMock()
    mock_count_preserved.scalar_one.return_value = 5

    mock_count_deep = MagicMock()
    mock_count_deep.scalar_one.return_value = 2

    # Mock delete raises an error
    mock_session.execute.side_effect = [
        mock_count_to_delete,
        mock_count_preserved,
        mock_count_deep,
        Exception("DB connection lost"),
    ]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.safe_async_session", mock_session_maker), \
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

    with patch("app.workers.storage_cleanup.safe_async_session", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 7

        from app.workers.storage_cleanup import cleanup_old_articles
        result = await cleanup_old_articles()

    assert result["retention_days"] == 7


@pytest.mark.asyncio
async def test_cleanup_logs_statistics():
    """Verify cleanup logs start, completion, and skip events."""
    mock_session = AsyncMock()

    mock_count_to_delete = MagicMock()
    mock_count_to_delete.scalar_one.return_value = 100

    mock_count_preserved = MagicMock()
    mock_count_preserved.scalar_one.return_value = 15

    mock_count_deep = MagicMock()
    mock_count_deep.scalar_one.return_value = 3

    mock_delete_result = MagicMock()
    mock_delete_result.rowcount = 100

    mock_session.execute.side_effect = [
        mock_count_to_delete,
        mock_count_preserved,
        mock_count_deep,
        mock_delete_result
    ]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.safe_async_session", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings, \
         patch("app.workers.storage_cleanup.logger") as mock_logger:
        mock_settings.rss_retention_days = 20

        from app.workers.storage_cleanup import cleanup_old_articles
        await cleanup_old_articles()

    # Verify start and completion logs
    log_events = [call.args[0] for call in mock_logger.info.call_args_list]
    assert "storage_cleanup_started" in log_events
    assert "storage_cleanup_completed" in log_events


@pytest.mark.asyncio
async def test_cleanup_preserves_bookmarked_articles():
    """Verify bookmarked articles are excluded from cleanup."""
    mock_session = AsyncMock()

    # Mock: 200 old articles total, but 50 are bookmarked
    mock_count_to_delete = MagicMock()
    mock_count_to_delete.scalar_one.return_value = 150  # 200 - 50 bookmarked

    mock_count_preserved = MagicMock()
    mock_count_preserved.scalar_one.return_value = 50

    mock_count_deep = MagicMock()
    mock_count_deep.scalar_one.return_value = 8

    mock_delete_result = MagicMock()
    mock_delete_result.rowcount = 150

    mock_session.execute.side_effect = [
        mock_count_to_delete,
        mock_count_preserved,
        mock_count_deep,
        mock_delete_result
    ]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.safe_async_session", mock_session_maker), \
         patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 20

        from app.workers.storage_cleanup import cleanup_old_articles
        result = await cleanup_old_articles()

    # Verify bookmarks were preserved
    assert result["deleted_count"] == 150  # Only non-bookmarked deleted
    assert result["preserved_bookmarks"] == 50  # Bookmarks kept
    assert result["preserved_deep"] == 8  # Deep source articles kept
    assert result["retention_days"] == 20
    mock_session.commit.assert_called_once()


@pytest.mark.asyncio
async def test_cleanup_preserves_digest_referenced_content():
    """Content referenced by a recent digest must be excluded from cleanup.

    Regression for the ``editorial_article_not_found`` → 503 loop: if a
    Content row referenced by today's editorial_v1 digest gets purged by
    the RSS cleanup worker, ``_build_editorial_response`` crashes on
    ``content_map.get(content_id)`` for every subsequent request.
    """
    referenced_id = uuid4()
    mock_session = AsyncMock()

    mock_count_to_delete = MagicMock()
    mock_count_to_delete.scalar_one.return_value = 100

    mock_count_preserved = MagicMock()
    mock_count_preserved.scalar_one.return_value = 5

    mock_count_deep = MagicMock()
    mock_count_deep.scalar_one.return_value = 2

    mock_delete_result = MagicMock()
    mock_delete_result.rowcount = 100

    mock_session.execute.side_effect = [
        mock_count_to_delete,
        mock_count_preserved,
        mock_count_deep,
        mock_delete_result,
    ]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    # Override the autouse fixture: signal that one content is referenced.
    with patch(
        "app.workers.storage_cleanup._collect_referenced_content_ids",
        new=AsyncMock(return_value={referenced_id}),
    ), patch(
        "app.workers.storage_cleanup.safe_async_session", mock_session_maker
    ), patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 20

        from app.workers.storage_cleanup import cleanup_old_articles

        result = await cleanup_old_articles()

    assert result["preserved_digest_refs"] == 1
    # The DELETE statement must reference a NOT IN clause that excludes
    # the digest-referenced content. The last execute() call is the DELETE.
    delete_call_args = mock_session.execute.call_args_list[-1]
    delete_stmt = delete_call_args.args[0]
    # Compile to bound SQL so we can assert the param made it through.
    # SQLAlchemy renders PG UUIDs in hex form, without dashes.
    compiled = str(
        delete_stmt.compile(compile_kwargs={"literal_binds": True})
    )
    assert referenced_id.hex in compiled
    # And the DELETE has an extra NOT IN clause beyond the bookmarks /
    # deep-source ones — signalled by multiple "NOT IN" occurrences.
    assert compiled.count("NOT IN") >= 3


@pytest.mark.asyncio
async def test_cleanup_skip_path_reports_preserved_digest_refs():
    """Even when nothing is deleted, the preserved_digest_refs stat is returned."""
    referenced_id = uuid4()
    mock_session = AsyncMock()

    mock_count_to_delete = MagicMock()
    mock_count_to_delete.scalar_one.return_value = 0  # nothing to delete

    mock_count_preserved = MagicMock()
    mock_count_preserved.scalar_one.return_value = 0

    mock_count_deep = MagicMock()
    mock_count_deep.scalar_one.return_value = 0

    mock_session.execute.side_effect = [
        mock_count_to_delete,
        mock_count_preserved,
        mock_count_deep,
    ]

    mock_session_maker = MagicMock()
    mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch(
        "app.workers.storage_cleanup._collect_referenced_content_ids",
        new=AsyncMock(return_value={referenced_id}),
    ), patch(
        "app.workers.storage_cleanup.safe_async_session", mock_session_maker
    ), patch("app.workers.storage_cleanup.settings") as mock_settings:
        mock_settings.rss_retention_days = 20

        from app.workers.storage_cleanup import cleanup_old_articles

        result = await cleanup_old_articles()

    assert result["deleted_count"] == 0
    assert result["preserved_digest_refs"] == 1
    mock_session.commit.assert_not_called()
