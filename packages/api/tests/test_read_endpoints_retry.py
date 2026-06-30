"""S1-D resilience tests for the two read-only endpoints wrapped with
``retry_db_op`` (cold-open hot reads): ``collections.list_collections`` and
``feed.get_tab_counts``.

Model: ``tests/test_sources_resilience.py``. We assert the endpoint replays a
single transient pool error and returns OK — the helper ``retry_db_op`` itself
is already unit-covered by ``TestRetryDbOp`` there, so we do not duplicate it.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, Mock, patch
from uuid import uuid4

import pytest
from sqlalchemy.exc import OperationalError


def _op_error(msg: str = "pool gone") -> OperationalError:
    return OperationalError("SELECT 1", {}, Exception(msg))


class TestListCollectionsRetry:
    @pytest.mark.asyncio
    async def test_retries_transient_then_succeeds(self):
        from app.routers import collections as col_mod

        mock_session = MagicMock()
        mock_session.rollback = AsyncMock()

        payload = [{"id": uuid4(), "name": "Lecture"}]
        service = MagicMock()
        service.list_collections = AsyncMock(side_effect=[_op_error(), payload])

        with patch.object(col_mod, "CollectionService", return_value=service):
            result = await col_mod.list_collections(
                db=mock_session, current_user_id=str(uuid4())
            )

        assert result == payload
        # First await raises, second succeeds → 2 awaits, 1 rollback.
        assert service.list_collections.await_count == 2
        assert mock_session.rollback.await_count == 1

    @pytest.mark.asyncio
    async def test_succeeds_on_first_try_no_rollback(self):
        from app.routers import collections as col_mod

        mock_session = MagicMock()
        mock_session.rollback = AsyncMock()

        payload = [{"id": uuid4(), "name": "Lecture"}]
        service = MagicMock()
        service.list_collections = AsyncMock(return_value=payload)

        with patch.object(col_mod, "CollectionService", return_value=service):
            result = await col_mod.list_collections(
                db=mock_session, current_user_id=str(uuid4())
            )

        assert result == payload
        service.list_collections.assert_awaited_once()
        mock_session.rollback.assert_not_called()


class TestTabCountsRetry:
    @pytest.mark.asyncio
    async def test_retries_transient_then_succeeds(self):
        from app.routers import feed as feed_mod
        from app.schemas.feed import TabCountsResponse

        # On the recovering attempt, return no followed sources so _load_counts
        # early-returns total=0 (keeps the retry assertion focused).
        empty_result = MagicMock()
        empty_result.all = Mock(return_value=[])
        empty_scalars = MagicMock()
        empty_scalars.all = Mock(return_value=[])

        mock_db = MagicMock()
        mock_db.rollback = AsyncMock()
        mock_db.execute = AsyncMock(side_effect=[_op_error(), empty_result])
        mock_db.scalars = AsyncMock(return_value=empty_scalars)

        result = await feed_mod.get_tab_counts(db=mock_db, current_user_id=str(uuid4()))

        assert isinstance(result, TabCountsResponse)
        assert result.total == 0
        # 1st attempt raises on execute, 2nd attempt executes the followed query.
        assert mock_db.execute.await_count == 2
        assert mock_db.rollback.await_count == 1
