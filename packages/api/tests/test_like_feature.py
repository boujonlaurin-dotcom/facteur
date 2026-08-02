"""Tests for like feature: set_like_status, subtopic weight adjustments."""

from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from app.models.content import UserContentStatus
from app.services.content_service import ContentService


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
        # Like = signal explicite → allow_create=True (C-1).
        mock_adjust.assert_called_once_with(
            user_id, content_id, 0.15, allow_create=True
        )


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
        # Unlike (delta < 0) : allow_create=True mais la branche update-only
        # s'applique de toute façon (pas de création sur signal négatif).
        mock_adjust.assert_called_once_with(
            user_id, content_id, -0.15, allow_create=True
        )


# NB : le cap 3.0, le clamp 0.1, la création sur like et le "no-create" sur
# lecture de `_adjust_subtopic_weights` sont désormais couverts contre une vraie
# DB (l'implémentation est passée d'une mutation ORM à un upsert Postgres Core,
# non observable via un mock de session) — cf.
# `tests/test_subtopic_weight_concurrency.py`.


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
        # Bookmark = signal explicite → allow_create=True (C-1).
        mock_adjust.assert_called_once_with(
            user_id, content_id, 0.05, allow_create=True
        )
