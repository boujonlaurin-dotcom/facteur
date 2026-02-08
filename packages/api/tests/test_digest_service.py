"""Tests unitaires pour DigestService — actions et complétion.

Couvre:
- apply_action: gestion des actions READ, SAVE, NOT_INTERESTED, UNDO
- complete_digest: enregistrement de complétion et stats
- _get_existing_digest: vérification d'existence de digest

Note: Ces tests mockent la session DB et les dépendances internes.
Ils vérifient le comportement logique, pas l'intégration DB.
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch, MagicMock, PropertyMock
from uuid import uuid4
from datetime import date, datetime, timezone, timedelta

from app.schemas.digest import DigestAction
from app.models.enums import ContentStatus


# ─── Fixtures ─────────────────────────────────────────────────────────────────


@pytest.fixture
def mock_session():
    """Mock de session SQLAlchemy async."""
    session = AsyncMock()
    session.flush = AsyncMock()
    session.add = Mock()
    session.scalar = AsyncMock(return_value=None)
    session.execute = AsyncMock()
    session.get = AsyncMock(return_value=None)
    return session


@pytest.fixture
def service(mock_session):
    """Instance de DigestService avec toutes les dépendances mockées."""
    with patch('app.services.digest_service.DigestSelector'), \
         patch('app.services.digest_service.StreakService') as mock_streak_cls:
        
        mock_streak = Mock()
        mock_streak.increment_consumption = AsyncMock()
        mock_streak_cls.return_value = mock_streak
        
        from app.services.digest_service import DigestService
        svc = DigestService(mock_session)
        svc.streak_service = mock_streak
        
    return svc


# ─── Tests: apply_action ──────────────────────────────────────────────────────


class TestApplyAction:
    """Tests pour DigestService.apply_action()."""

    @pytest.mark.asyncio
    async def test_read_action_marks_consumed(self, service, mock_session):
        """READ action sets content status to CONSUMED."""
        digest_id = uuid4()
        user_id = uuid4()
        content_id = uuid4()

        # Mock _get_or_create_content_status returns a mock status
        mock_status = Mock()
        mock_status.status = ContentStatus.UNSEEN
        mock_status.is_saved = False
        mock_status.is_hidden = False
        mock_status.hidden_reason = None
        
        with patch.object(service, '_get_or_create_content_status', new_callable=AsyncMock, return_value=mock_status):
            result = await service.apply_action(
                digest_id=digest_id,
                user_id=user_id,
                content_id=content_id,
                action=DigestAction.READ
            )

        assert result["success"] is True
        assert result["action"] == DigestAction.READ
        assert result["content_id"] == content_id
        assert mock_status.status == ContentStatus.CONSUMED
        assert mock_status.is_hidden is False

    @pytest.mark.asyncio
    async def test_save_action_sets_saved(self, service, mock_session):
        """SAVE action sets is_saved to True."""
        mock_status = Mock()
        mock_status.status = ContentStatus.UNSEEN
        mock_status.is_saved = False
        mock_status.is_hidden = False
        mock_status.saved_at = None

        with patch.object(service, '_get_or_create_content_status', new_callable=AsyncMock, return_value=mock_status):
            result = await service.apply_action(
                digest_id=uuid4(),
                user_id=uuid4(),
                content_id=uuid4(),
                action=DigestAction.SAVE
            )

        assert result["success"] is True
        assert mock_status.is_saved is True
        assert mock_status.is_hidden is False
        assert mock_status.saved_at is not None

    @pytest.mark.asyncio
    async def test_not_interested_hides_content(self, service, mock_session):
        """NOT_INTERESTED action hides the content and triggers mute."""
        mock_status = Mock()
        mock_status.status = ContentStatus.UNSEEN
        mock_status.is_saved = False
        mock_status.is_hidden = False
        mock_status.hidden_reason = None

        with patch.object(service, '_get_or_create_content_status', new_callable=AsyncMock, return_value=mock_status), \
             patch.object(service, '_trigger_personalization_mute', new_callable=AsyncMock) as mock_mute:
            result = await service.apply_action(
                digest_id=uuid4(),
                user_id=uuid4(),
                content_id=uuid4(),
                action=DigestAction.NOT_INTERESTED
            )

        assert result["success"] is True
        assert mock_status.is_hidden is True
        assert mock_status.hidden_reason == "not_interested"
        mock_mute.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_undo_resets_all_states(self, service, mock_session):
        """UNDO action resets status to UNSEEN and clears all flags."""
        mock_status = Mock()
        mock_status.status = ContentStatus.CONSUMED
        mock_status.is_saved = True
        mock_status.is_hidden = True
        mock_status.hidden_reason = "not_interested"

        with patch.object(service, '_get_or_create_content_status', new_callable=AsyncMock, return_value=mock_status):
            result = await service.apply_action(
                digest_id=uuid4(),
                user_id=uuid4(),
                content_id=uuid4(),
                action=DigestAction.UNDO
            )

        assert result["success"] is True
        assert mock_status.status == ContentStatus.UNSEEN
        assert mock_status.is_saved is False
        assert mock_status.is_hidden is False
        assert mock_status.hidden_reason is None

    @pytest.mark.asyncio
    async def test_action_returns_applied_at_timestamp(self, service, mock_session):
        """Result includes applied_at timestamp."""
        mock_status = Mock()
        mock_status.status = ContentStatus.UNSEEN
        mock_status.is_saved = False
        mock_status.is_hidden = False

        with patch.object(service, '_get_or_create_content_status', new_callable=AsyncMock, return_value=mock_status):
            result = await service.apply_action(
                digest_id=uuid4(),
                user_id=uuid4(),
                content_id=uuid4(),
                action=DigestAction.READ
            )

        assert "applied_at" in result
        assert isinstance(result["applied_at"], datetime)


# ─── Tests: complete_digest ───────────────────────────────────────────────────


class TestCompleteDigest:
    """Tests pour DigestService.complete_digest()."""

    @pytest.mark.asyncio
    async def test_complete_returns_success(self, service, mock_session):
        """Completing a digest returns success with stats."""
        digest_id = uuid4()
        user_id = uuid4()

        # Mock the digest lookup
        mock_digest = Mock()
        mock_digest.id = digest_id
        mock_digest.target_date = date.today()
        mock_digest.items = [
            {"content_id": str(uuid4()), "rank": i, "reason": "test"}
            for i in range(1, 6)
        ]
        mock_session.get = AsyncMock(return_value=mock_digest)

        # Mock action stats
        with patch.object(service, '_get_digest_action_stats', new_callable=AsyncMock, return_value={
            "read": 3, "saved": 1, "dismissed": 1
        }), \
             patch.object(service, '_update_closure_streak', new_callable=AsyncMock, return_value={
                 "current": 5, "longest": 10, "message": "Série de 5 jours !"
             }):
            result = await service.complete_digest(
                digest_id=digest_id,
                user_id=user_id,
                closure_time_seconds=120
            )

        assert result["success"] is True
        assert result["digest_id"] == digest_id
        assert result["articles_read"] == 3
        assert result["articles_saved"] == 1
        assert result["articles_dismissed"] == 1
        assert result["closure_time_seconds"] == 120
        assert result["closure_streak"] == 5
        assert result["streak_message"] == "Série de 5 jours !"

    @pytest.mark.asyncio
    async def test_complete_nonexistent_digest_raises(self, service, mock_session):
        """Completing a nonexistent digest raises ValueError."""
        mock_session.get = AsyncMock(return_value=None)

        with pytest.raises(ValueError, match="Digest not found"):
            await service.complete_digest(
                digest_id=uuid4(),
                user_id=uuid4()
            )

    @pytest.mark.asyncio
    async def test_complete_adds_completion_record(self, service, mock_session):
        """Completing a digest adds a DigestCompletion to the session."""
        digest_id = uuid4()
        user_id = uuid4()

        mock_digest = Mock()
        mock_digest.id = digest_id
        mock_digest.target_date = date.today()
        mock_digest.items = []
        mock_session.get = AsyncMock(return_value=mock_digest)

        with patch.object(service, '_get_digest_action_stats', new_callable=AsyncMock, return_value={
            "read": 0, "saved": 0, "dismissed": 0
        }), \
             patch.object(service, '_update_closure_streak', new_callable=AsyncMock, return_value={
                 "current": 1, "longest": 1, "message": "Premier digest complété !"
             }):
            await service.complete_digest(
                digest_id=digest_id,
                user_id=user_id,
                closure_time_seconds=60
            )

        # Verify session.add was called with a DigestCompletion instance
        mock_session.add.assert_called_once()
        added_obj = mock_session.add.call_args[0][0]
        from app.models.digest_completion import DigestCompletion
        assert isinstance(added_obj, DigestCompletion)
        assert added_obj.user_id == user_id
        assert added_obj.target_date == date.today()
