"""Tests for POST /api/feed/refresh and POST /api/feed/refresh/undo.

Covers:
- refresh_feed returns `previous_impressions` backup (NULL for new rows, datetime for existing)
- undo_refresh restores previous values (NULL and datetime)
- undo_refresh is idempotent (re-running with same backup produces no change)
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentType
from app.routers.feed import refresh_feed, undo_refresh
from app.schemas.content import (
    FeedRefreshRequest,
    FeedRefreshUndoRequest,
    PreviousImpression,
)


@pytest.fixture
async def test_contents(db_session, test_source):
    """Create 3 test Content rows."""
    contents = []
    for i in range(3):
        c = Content(
            id=uuid4(),
            source_id=test_source.id,
            title=f"Refresh test article {i}",
            url=f"https://example.com/refresh-{i}-{uuid4()}",
            guid=f"refresh-guid-{uuid4()}",
            published_at=datetime.utcnow(),
            content_type=ContentType.ARTICLE,
        )
        db_session.add(c)
        contents.append(c)
    await db_session.commit()
    return contents


@pytest.fixture
def fake_user_id():
    return str(uuid4())


async def _get_last_impressed(db_session, user_id_str, content_id):
    """Fetch current last_impressed_at for (user, content)."""
    from uuid import UUID as _UUID

    result = await db_session.execute(
        select(UserContentStatus.last_impressed_at)
        .where(UserContentStatus.user_id == _UUID(user_id_str))
        .where(UserContentStatus.content_id == content_id)
    )
    row = result.first()
    return row[0] if row else None


class TestRefreshFeedBackup:
    """refresh_feed should return previous_impressions for undo."""

    async def test_refresh_first_time_returns_null_previous(
        self, db_session, test_contents, fake_user_id
    ):
        """First refresh on fresh content → all previous_last_impressed_at are None."""
        body = FeedRefreshRequest(content_ids=[c.id for c in test_contents])

        response = await refresh_feed(
            body=body, db=db_session, current_user_id=fake_user_id
        )

        assert response.refreshed == 3
        assert len(response.previous_impressions) == 3
        assert all(
            p.previous_last_impressed_at is None for p in response.previous_impressions
        )
        # All content_ids are represented
        assert {p.content_id for p in response.previous_impressions} == {
            c.id for c in test_contents
        }

        # And DB now has last_impressed_at set
        for c in test_contents:
            ts = await _get_last_impressed(db_session, fake_user_id, c.id)
            assert ts is not None

    async def test_refresh_second_time_returns_first_timestamp(
        self, db_session, test_contents, fake_user_id
    ):
        """Second refresh returns the datetime set by the first refresh."""
        ids = [c.id for c in test_contents]

        # First refresh
        first = await refresh_feed(
            body=FeedRefreshRequest(content_ids=ids),
            db=db_session,
            current_user_id=fake_user_id,
        )
        first_timestamps = {
            await _get_last_impressed(db_session, fake_user_id, cid) for cid in ids
        }
        assert all(ts is not None for ts in first_timestamps)

        # Second refresh
        second = await refresh_feed(
            body=FeedRefreshRequest(content_ids=ids),
            db=db_session,
            current_user_id=fake_user_id,
        )

        # previous_impressions of second should equal the timestamps set by first
        assert second.refreshed == 3
        assert len(second.previous_impressions) == 3
        for entry in second.previous_impressions:
            assert entry.previous_last_impressed_at is not None


class TestUndoRefresh:
    """undo_refresh should restore previous last_impressed_at values."""

    async def test_undo_after_first_refresh_restores_null(
        self, db_session, test_contents, fake_user_id
    ):
        """Undo after initial refresh → last_impressed_at back to NULL."""
        ids = [c.id for c in test_contents]

        # Refresh first
        refresh_resp = await refresh_feed(
            body=FeedRefreshRequest(content_ids=ids),
            db=db_session,
            current_user_id=fake_user_id,
        )

        # Verify rows have impressions set
        for cid in ids:
            assert await _get_last_impressed(db_session, fake_user_id, cid) is not None

        # Undo
        undo_resp = await undo_refresh(
            body=FeedRefreshUndoRequest(
                previous_impressions=refresh_resp.previous_impressions
            ),
            db=db_session,
            current_user_id=fake_user_id,
        )

        assert undo_resp == {"restored": 3}

        # Verify rows are back to NULL
        for cid in ids:
            assert await _get_last_impressed(db_session, fake_user_id, cid) is None

    async def test_undo_after_second_refresh_restores_first_timestamp(
        self, db_session, test_contents, fake_user_id
    ):
        """Undo after second refresh → restores first refresh timestamp."""
        ids = [c.id for c in test_contents]

        # First refresh
        await refresh_feed(
            body=FeedRefreshRequest(content_ids=ids),
            db=db_session,
            current_user_id=fake_user_id,
        )
        first_ts = {
            cid: await _get_last_impressed(db_session, fake_user_id, cid) for cid in ids
        }

        # Wait a bit (simulated by modifying one timestamp to be clearly earlier)
        # Then second refresh
        second = await refresh_feed(
            body=FeedRefreshRequest(content_ids=ids),
            db=db_session,
            current_user_id=fake_user_id,
        )

        # Undo second refresh
        await undo_refresh(
            body=FeedRefreshUndoRequest(
                previous_impressions=second.previous_impressions
            ),
            db=db_session,
            current_user_id=fake_user_id,
        )

        # Each row should be back to the first refresh timestamp
        for cid in ids:
            restored_ts = await _get_last_impressed(db_session, fake_user_id, cid)
            assert restored_ts is not None
            # Restored timestamp should match the one captured after first refresh
            assert abs((restored_ts - first_ts[cid]).total_seconds()) < 0.001

    async def test_undo_is_idempotent(
        self, db_session, test_contents, fake_user_id
    ):
        """Running undo twice with the same backup is safe (no-op on 2nd run)."""
        ids = [c.id for c in test_contents]

        refresh_resp = await refresh_feed(
            body=FeedRefreshRequest(content_ids=ids),
            db=db_session,
            current_user_id=fake_user_id,
        )

        # First undo
        await undo_refresh(
            body=FeedRefreshUndoRequest(
                previous_impressions=refresh_resp.previous_impressions
            ),
            db=db_session,
            current_user_id=fake_user_id,
        )

        # Second undo with the SAME backup → should be a no-op
        await undo_refresh(
            body=FeedRefreshUndoRequest(
                previous_impressions=refresh_resp.previous_impressions
            ),
            db=db_session,
            current_user_id=fake_user_id,
        )

        # Rows should still be NULL
        for cid in ids:
            assert await _get_last_impressed(db_session, fake_user_id, cid) is None

    async def test_undo_with_empty_list(self, db_session, fake_user_id):
        """Undo with no entries is a valid no-op."""
        resp = await undo_refresh(
            body=FeedRefreshUndoRequest(previous_impressions=[]),
            db=db_session,
            current_user_id=fake_user_id,
        )
        assert resp == {"restored": 0}

    async def test_undo_with_preset_datetime(
        self, db_session, test_contents, fake_user_id
    ):
        """Undo with an arbitrary previous datetime restores it exactly."""
        from uuid import UUID as _UUID

        cid = test_contents[0].id
        preset_ts = datetime.now(UTC) - timedelta(hours=10)

        # Directly set an arbitrary value to simulate prior state
        from sqlalchemy.dialects.postgresql import insert

        from app.models.enums import ContentStatus

        now = datetime.now(UTC)
        stmt = insert(UserContentStatus).values(
            user_id=_UUID(fake_user_id),
            content_id=cid,
            status=ContentStatus.UNSEEN.value,
            last_impressed_at=now,  # current
            created_at=now,
            updated_at=now,
        )
        await db_session.execute(stmt)
        await db_session.commit()

        # Undo should set it back to preset_ts
        await undo_refresh(
            body=FeedRefreshUndoRequest(
                previous_impressions=[
                    PreviousImpression(
                        content_id=cid, previous_last_impressed_at=preset_ts
                    )
                ]
            ),
            db=db_session,
            current_user_id=fake_user_id,
        )

        restored = await _get_last_impressed(db_session, fake_user_id, cid)
        assert restored is not None
        assert abs((restored - preset_ts).total_seconds()) < 0.001
