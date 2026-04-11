"""Tests for the Learning Checkpoint service and endpoints (Epic 13)."""

import sys
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4, UUID
from datetime import datetime, UTC, timedelta

import pytest

# Mock feedparser and its deep deps (sgmllib removed in Python 3.x)
# to allow tests to run without full production dependencies
if "feedparser" not in sys.modules:
    sys.modules["feedparser"] = MagicMock()
if "sgmllib" not in sys.modules:
    sys.modules["sgmllib"] = MagicMock()

from app.services.learning_service import (
    LearningService,
    _diversify_proposals,
    CHECKPOINT_MAX_PROPOSALS,
    SIGNAL_WINDOW_DAYS,
)
from app.models.learning import UserLearningProposal, UserEntityPreference
from app.schemas.learning import (
    ApplyProposalsRequest,
    ApplyProposalAction,
    EntityPreferenceRequest,
    LearningCheckpointResponse,
    ProposalResponse,
    SignalContext,
)


# ------------------------------------------------------------------
# _diversify_proposals (pure function)
# ------------------------------------------------------------------


class TestDiversifyProposals:
    def test_empty(self):
        assert _diversify_proposals([], 4) == []

    def test_under_max(self):
        candidates = [
            {"proposal_type": "source_priority", "signal_strength": 0.9},
            {"proposal_type": "mute_entity", "signal_strength": 0.8},
        ]
        result = _diversify_proposals(candidates, 4)
        assert len(result) == 2

    def test_diversifies_types(self):
        candidates = [
            {"proposal_type": "source_priority", "signal_strength": 0.9},
            {"proposal_type": "source_priority", "signal_strength": 0.85},
            {"proposal_type": "source_priority", "signal_strength": 0.8},
            {"proposal_type": "source_priority", "signal_strength": 0.75},
            {"proposal_type": "mute_entity", "signal_strength": 0.7},
            {"proposal_type": "follow_entity", "signal_strength": 0.6},
        ]
        result = _diversify_proposals(candidates, 4)
        assert len(result) == 4
        types = [r["proposal_type"] for r in result]
        # Should include at least one non-source_priority
        assert "source_priority" in types
        assert len([t for t in types if t != "source_priority"]) >= 1

    def test_max_count_respected(self):
        candidates = [
            {"proposal_type": f"type_{i}", "signal_strength": 1.0 - i * 0.1}
            for i in range(10)
        ]
        result = _diversify_proposals(candidates, 4)
        assert len(result) == 4


# ------------------------------------------------------------------
# LearningService (mocked DB)
# ------------------------------------------------------------------


class TestLearningServiceEntityPreference:
    @pytest.mark.asyncio
    async def test_set_entity_preference(self):
        mock_db = AsyncMock()
        service = LearningService(mock_db)

        await service.set_entity_preference(uuid4(), "Elon Musk", "mute")

        assert mock_db.execute.called
        assert mock_db.flush.called

    @pytest.mark.asyncio
    async def test_remove_entity_preference_found(self):
        mock_db = AsyncMock()
        mock_result = MagicMock()
        mock_result.rowcount = 1
        mock_db.execute = AsyncMock(return_value=mock_result)
        service = LearningService(mock_db)

        removed = await service.remove_entity_preference(uuid4(), "Elon Musk")

        assert removed is True
        assert mock_db.flush.called

    @pytest.mark.asyncio
    async def test_remove_entity_preference_not_found(self):
        mock_db = AsyncMock()
        mock_result = MagicMock()
        mock_result.rowcount = 0
        mock_db.execute = AsyncMock(return_value=mock_result)
        service = LearningService(mock_db)

        removed = await service.remove_entity_preference(uuid4(), "Nobody")

        assert removed is False

    @pytest.mark.asyncio
    async def test_get_muted_entities(self):
        mock_db = AsyncMock()
        mock_result = MagicMock()
        mock_result.all.return_value = [("Elon Musk",), ("Jeff Bezos",)]
        mock_db.execute = AsyncMock(return_value=mock_result)
        service = LearningService(mock_db)

        result = await service.get_muted_entities(uuid4())

        assert result == ["Elon Musk", "Jeff Bezos"]


class TestLearningServiceApplyProposals:
    @pytest.mark.asyncio
    async def test_dismiss_proposal(self):
        mock_db = AsyncMock()
        user_id = uuid4()
        proposal_id = uuid4()

        # Create a mock proposal
        mock_proposal = MagicMock(spec=UserLearningProposal)
        mock_proposal.id = proposal_id
        mock_proposal.user_id = user_id
        mock_proposal.status = "pending"
        mock_proposal.proposal_type = "source_priority"

        mock_db.scalar = AsyncMock(return_value=mock_proposal)
        service = LearningService(mock_db)

        results = await service.apply_proposals(
            user_id,
            [{"proposal_id": proposal_id, "action": "dismiss"}],
        )

        assert len(results) == 1
        assert results[0]["success"] is True
        assert results[0]["action"] == "dismiss"
        assert mock_proposal.status == "dismissed"
        assert mock_proposal.resolved_at is not None

    @pytest.mark.asyncio
    async def test_proposal_not_found(self):
        mock_db = AsyncMock()
        mock_db.scalar = AsyncMock(return_value=None)
        service = LearningService(mock_db)

        results = await service.apply_proposals(
            uuid4(),
            [{"proposal_id": uuid4(), "action": "accept"}],
        )

        assert len(results) == 1
        assert results[0]["success"] is False
        assert "not found" in results[0]["detail"]

    @pytest.mark.asyncio
    async def test_accept_source_priority(self):
        mock_db = AsyncMock()
        user_id = uuid4()
        source_id = uuid4()
        proposal_id = uuid4()

        mock_proposal = MagicMock(spec=UserLearningProposal)
        mock_proposal.id = proposal_id
        mock_proposal.user_id = user_id
        mock_proposal.status = "pending"
        mock_proposal.proposal_type = "source_priority"
        mock_proposal.entity_id = str(source_id)
        mock_proposal.proposed_value = "0.5"

        mock_db.scalar = AsyncMock(return_value=mock_proposal)
        service = LearningService(mock_db)

        results = await service.apply_proposals(
            user_id,
            [{"proposal_id": proposal_id, "action": "accept"}],
        )

        assert len(results) == 1
        assert results[0]["success"] is True
        assert mock_proposal.status == "accepted"

    @pytest.mark.asyncio
    async def test_modify_source_priority(self):
        mock_db = AsyncMock()
        user_id = uuid4()
        source_id = uuid4()
        proposal_id = uuid4()

        mock_proposal = MagicMock(spec=UserLearningProposal)
        mock_proposal.id = proposal_id
        mock_proposal.user_id = user_id
        mock_proposal.status = "pending"
        mock_proposal.proposal_type = "source_priority"
        mock_proposal.entity_id = str(source_id)
        mock_proposal.proposed_value = "0.5"

        mock_db.scalar = AsyncMock(return_value=mock_proposal)
        service = LearningService(mock_db)

        results = await service.apply_proposals(
            user_id,
            [{"proposal_id": proposal_id, "action": "modify", "value": "1.0"}],
        )

        assert len(results) == 1
        assert results[0]["success"] is True
        assert mock_proposal.status == "modified"
        assert mock_proposal.user_chosen_value == "1.0"

    @pytest.mark.asyncio
    async def test_accept_mute_entity(self):
        mock_db = AsyncMock()
        user_id = uuid4()
        proposal_id = uuid4()

        mock_proposal = MagicMock(spec=UserLearningProposal)
        mock_proposal.id = proposal_id
        mock_proposal.user_id = user_id
        mock_proposal.status = "pending"
        mock_proposal.proposal_type = "mute_entity"
        mock_proposal.entity_id = "Rachida Dati"
        mock_proposal.proposed_value = "mute"

        mock_db.scalar = AsyncMock(return_value=mock_proposal)
        service = LearningService(mock_db)

        results = await service.apply_proposals(
            user_id,
            [{"proposal_id": proposal_id, "action": "accept"}],
        )

        assert len(results) == 1
        assert results[0]["success"] is True


class TestLearningServiceGetPending:
    @pytest.mark.asyncio
    async def test_get_pending_empty(self):
        mock_db = AsyncMock()
        mock_result = MagicMock()
        mock_result.scalars.return_value.all.return_value = []
        mock_db.execute = AsyncMock(return_value=mock_result)
        service = LearningService(mock_db)

        proposals = await service.get_pending_proposals(uuid4())

        assert proposals == []

    @pytest.mark.asyncio
    async def test_get_pending_increments_shown(self):
        mock_db = AsyncMock()
        mock_proposal = MagicMock(spec=UserLearningProposal)
        mock_proposal.id = uuid4()
        mock_proposal.shown_count = 0

        mock_result = MagicMock()
        mock_result.scalars.return_value.all.return_value = [mock_proposal]
        mock_db.execute = AsyncMock(return_value=mock_result)
        service = LearningService(mock_db)

        proposals = await service.get_pending_proposals(uuid4())

        assert len(proposals) == 1
        # execute called twice: once for select, once for update shown_count
        assert mock_db.execute.call_count == 2
        assert mock_db.flush.called


# ------------------------------------------------------------------
# Personalization Router Endpoints (Epic 13)
# ------------------------------------------------------------------


class TestLearningEndpoints:
    """Tests for the personalization router endpoints.

    These tests import the router module which requires cryptography backend.
    They are skipped if the import chain fails (CI environment without full deps).
    """

    @pytest.mark.asyncio
    async def test_get_learning_proposals_empty(self):
        try:
            from app.routers.personalization import get_learning_proposals
        except BaseException:
            pytest.skip("Router import requires full deps (cryptography)")

        mock_db = AsyncMock()
        user_id = str(uuid4())

        with patch(
            "app.routers.personalization.LearningService"
        ) as mock_cls:
            mock_service = mock_cls.return_value
            mock_service.get_pending_proposals = AsyncMock(return_value=[])
            mock_service.generate_proposals = AsyncMock(return_value=[])

            response = await get_learning_proposals(
                db=mock_db, current_user_id=user_id
            )

        assert isinstance(response, LearningCheckpointResponse)
        assert response.proposals == []
        assert response.total_pending == 0

    @pytest.mark.asyncio
    async def test_apply_proposals_invalid_action(self):
        try:
            from app.routers.personalization import apply_proposals
        except BaseException:
            pytest.skip("Router import requires full deps (cryptography)")

        from fastapi import HTTPException

        mock_db = AsyncMock()
        user_id = str(uuid4())

        request = ApplyProposalsRequest(
            actions=[
                ApplyProposalAction(
                    proposal_id=uuid4(), action="invalid_action"
                )
            ]
        )

        with patch("app.routers.personalization.LearningService"):
            with pytest.raises(HTTPException) as excinfo:
                await apply_proposals(
                    request=request, db=mock_db, current_user_id=user_id
                )
            assert excinfo.value.status_code == 400

    @pytest.mark.asyncio
    async def test_set_entity_preference_invalid(self):
        try:
            from app.routers.personalization import set_entity_preference
        except BaseException:
            pytest.skip("Router import requires full deps (cryptography)")

        from fastapi import HTTPException

        mock_db = AsyncMock()
        user_id = str(uuid4())

        request = EntityPreferenceRequest(
            entity_canonical="Test", preference="invalid"
        )

        with pytest.raises(HTTPException) as excinfo:
            await set_entity_preference(
                request=request, db=mock_db, current_user_id=user_id
            )
        assert excinfo.value.status_code == 400

    @pytest.mark.asyncio
    async def test_set_entity_preference_valid(self):
        try:
            from app.routers.personalization import set_entity_preference
        except BaseException:
            pytest.skip("Router import requires full deps (cryptography)")

        mock_db = AsyncMock()
        user_id = str(uuid4())

        request = EntityPreferenceRequest(
            entity_canonical="Elon Musk", preference="mute"
        )

        with patch(
            "app.routers.personalization.LearningService"
        ) as mock_cls:
            mock_service = mock_cls.return_value
            mock_service.set_entity_preference = AsyncMock()

            response = await set_entity_preference(
                request=request, db=mock_db, current_user_id=user_id
            )

        assert response.entity_canonical == "Elon Musk"
        assert response.preference == "mute"

    @pytest.mark.asyncio
    async def test_remove_entity_preference_not_found(self):
        try:
            from app.routers.personalization import remove_entity_preference
        except BaseException:
            pytest.skip("Router import requires full deps (cryptography)")

        from fastapi import HTTPException

        mock_db = AsyncMock()
        user_id = str(uuid4())

        with patch(
            "app.routers.personalization.LearningService"
        ) as mock_cls:
            mock_service = mock_cls.return_value
            mock_service.remove_entity_preference = AsyncMock(return_value=False)

            with pytest.raises(HTTPException) as excinfo:
                await remove_entity_preference(
                    entity_canonical="Nobody",
                    db=mock_db,
                    current_user_id=user_id,
                )
            assert excinfo.value.status_code == 404

    @pytest.mark.asyncio
    async def test_remove_entity_preference_success(self):
        try:
            from app.routers.personalization import remove_entity_preference
        except BaseException:
            pytest.skip("Router import requires full deps (cryptography)")

        mock_db = AsyncMock()
        user_id = str(uuid4())

        with patch(
            "app.routers.personalization.LearningService"
        ) as mock_cls:
            mock_service = mock_cls.return_value
            mock_service.remove_entity_preference = AsyncMock(return_value=True)

            response = await remove_entity_preference(
                entity_canonical="Elon Musk",
                db=mock_db,
                current_user_id=user_id,
            )

        assert response["message"] == "Preference pour 'Elon Musk' supprimee"


# ------------------------------------------------------------------
# Schema Tests
# ------------------------------------------------------------------


class TestSchemas:
    def test_proposal_response(self):
        resp = ProposalResponse(
            id=uuid4(),
            proposal_type="source_priority",
            entity_type="source",
            entity_id=str(uuid4()),
            entity_label="Le Figaro",
            current_value="1.0",
            proposed_value="0.5",
            signal_strength=0.85,
            signal_context=SignalContext(
                articles_shown=14, articles_clicked=0, period_days=7
            ),
            shown_count=0,
            status="pending",
        )
        assert resp.proposal_type == "source_priority"
        assert resp.signal_context.articles_shown == 14

    def test_learning_checkpoint_response(self):
        resp = LearningCheckpointResponse(proposals=[], total_pending=0)
        assert resp.proposals == []

    def test_apply_proposals_request(self):
        req = ApplyProposalsRequest(
            actions=[
                ApplyProposalAction(
                    proposal_id=uuid4(), action="accept"
                ),
                ApplyProposalAction(
                    proposal_id=uuid4(), action="dismiss"
                ),
                ApplyProposalAction(
                    proposal_id=uuid4(), action="modify", value="1.5"
                ),
            ]
        )
        assert len(req.actions) == 3
        assert req.actions[2].value == "1.5"

    def test_entity_preference_request(self):
        req = EntityPreferenceRequest(
            entity_canonical="Elon Musk", preference="follow"
        )
        assert req.entity_canonical == "Elon Musk"
        assert req.preference == "follow"
