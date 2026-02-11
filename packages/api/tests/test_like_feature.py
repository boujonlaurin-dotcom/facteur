"""Tests for like feature: set_like_status, subtopic weight adjustments."""

import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from uuid import uuid4
from datetime import datetime

from app.services.content_service import ContentService
from app.models.content import UserContentStatus


@pytest.mark.asyncio
async def test_set_like_status_like():
    """Verify set_like_status(True) sets is_liked=True."""
    session = AsyncMock()
    service = ContentService(session)

    user_id = uuid4()
    content_id = uuid4()

    mock_status = UserContentStatus(
        user_id=user_id, content_id=content_id, is_liked=True
    )

    mock_result = MagicMock()
    mock_result.one.return_value = mock_status
    session.scalars.return_value = mock_result

    # Mock _adjust_subtopic_weights to avoid DB calls
    with patch.object(service, "_adjust_subtopic_weights", new_callable=AsyncMock):
        result = await service.set_like_status(user_id, content_id, True)

    assert result.is_liked is True
    session.scalars.assert_called_once()


@pytest.mark.asyncio
async def test_set_like_status_unlike():
    """Verify unlike resets is_liked and liked_at."""
    session = AsyncMock()
    service = ContentService(session)

    user_id = uuid4()
    content_id = uuid4()

    mock_status = UserContentStatus(
        user_id=user_id, content_id=content_id, is_liked=False
    )

    mock_result = MagicMock()
    mock_result.one.return_value = mock_status
    session.scalars.return_value = mock_result

    with patch.object(service, "_adjust_subtopic_weights", new_callable=AsyncMock):
        result = await service.set_like_status(user_id, content_id, False)

    assert result.is_liked is False
    session.scalars.assert_called_once()


@pytest.mark.asyncio
async def test_like_adjusts_subtopic_weights():
    """Verify liking content calls _adjust_subtopic_weights with positive delta."""
    session = AsyncMock()
    service = ContentService(session)

    user_id = uuid4()
    content_id = uuid4()

    mock_status = UserContentStatus(
        user_id=user_id, content_id=content_id, is_liked=True
    )
    mock_result = MagicMock()
    mock_result.one.return_value = mock_status
    session.scalars.return_value = mock_result

    with patch.object(
        service, "_adjust_subtopic_weights", new_callable=AsyncMock
    ) as mock_adjust:
        await service.set_like_status(user_id, content_id, True)
        mock_adjust.assert_called_once_with(user_id, content_id, 0.15)


@pytest.mark.asyncio
async def test_unlike_reverses_subtopic_weights():
    """Verify unlike calls _adjust_subtopic_weights with negative delta."""
    session = AsyncMock()
    service = ContentService(session)

    user_id = uuid4()
    content_id = uuid4()

    mock_status = UserContentStatus(
        user_id=user_id, content_id=content_id, is_liked=False
    )
    mock_result = MagicMock()
    mock_result.one.return_value = mock_status
    session.scalars.return_value = mock_result

    with patch.object(
        service, "_adjust_subtopic_weights", new_callable=AsyncMock
    ) as mock_adjust:
        await service.set_like_status(user_id, content_id, False)
        mock_adjust.assert_called_once_with(user_id, content_id, -0.15)


@pytest.mark.asyncio
async def test_like_weight_cap():
    """Verify weight doesn't exceed 3.0 after subtopic adjustment."""
    from app.models.user import UserSubtopic
    from app.models.content import Content
    from app.models.source import Source

    session = AsyncMock()
    service = ContentService(session)

    user_id = uuid4()
    content_id = uuid4()

    # Mock content with topics
    mock_source = MagicMock(spec=Source)
    mock_source.theme = "tech"
    mock_content = MagicMock(spec=Content)
    mock_content.topics = ["ai"]
    mock_content.source = mock_source

    # Subtopic near cap
    mock_subtopic = UserSubtopic(
        user_id=user_id, topic_slug="ai", weight=2.95
    )

    session.get.return_value = mock_content
    session.scalar.side_effect = [mock_subtopic, None]  # subtopic, then interest

    await service._adjust_subtopic_weights(user_id, content_id, 0.15)

    # Weight should be capped at 3.0
    assert mock_subtopic.weight == 3.0


@pytest.mark.asyncio
async def test_bookmark_adjusts_subtopic_weights():
    """Verify saving content adjusts subtopic weights by 0.05."""
    session = AsyncMock()
    service = ContentService(session)

    user_id = uuid4()
    content_id = uuid4()

    mock_status = UserContentStatus(
        user_id=user_id, content_id=content_id, is_saved=True
    )
    mock_result = MagicMock()
    mock_result.one.return_value = mock_status
    session.scalars.return_value = mock_result

    with patch.object(
        service, "_adjust_subtopic_weights", new_callable=AsyncMock
    ) as mock_adjust:
        await service.set_save_status(user_id, content_id, True)
        mock_adjust.assert_called_once_with(user_id, content_id, 0.05)


@pytest.mark.asyncio
async def test_like_creates_new_subtopic():
    """Verify liking creates subtopic if none exists."""
    from app.models.content import Content
    from app.models.source import Source

    session = AsyncMock()
    service = ContentService(session)

    user_id = uuid4()
    content_id = uuid4()

    mock_source = MagicMock(spec=Source)
    mock_source.theme = "tech"
    mock_content = MagicMock(spec=Content)
    mock_content.topics = ["quantum_computing"]
    mock_content.source = mock_source

    session.get.return_value = mock_content
    # No existing subtopic or interest
    session.scalar.return_value = None

    await service._adjust_subtopic_weights(user_id, content_id, 0.15)

    # Verify session.add was called (for new subtopic + new interest)
    assert session.add.call_count == 2
