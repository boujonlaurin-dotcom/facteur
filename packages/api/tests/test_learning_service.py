"""Tests for the entity-preference subset of LearningService.

Historique : ce fichier testait aussi le Learning Checkpoint (Epic 13),
supprime en Sprint 2 PR1 (feature morte). Cf. migration `lp02`.
"""

import sys
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

# Mock feedparser and its deep deps (sgmllib removed in Python 3.x)
# to allow tests to run without full production dependencies
if "feedparser" not in sys.modules:
    sys.modules["feedparser"] = MagicMock()
if "sgmllib" not in sys.modules:
    sys.modules["sgmllib"] = MagicMock()

from app.services.learning_service import LearningService
from app.schemas.learning import EntityPreferenceRequest


# ------------------------------------------------------------------
# LearningService (entity preferences only)
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


# ------------------------------------------------------------------
# Defensive muted entities loader (chantier A — backend resilience)
# ------------------------------------------------------------------


class TestLoadMutedEntitiesSafe:
    """Guard-rail contre la régression qui a causé l'outage post-merge #395 :
    si `user_entity_preferences` est absente (schema drift), `/api/feed/`
    doit continuer à servir — pas crasher.
    """

    @pytest.mark.asyncio
    async def test_returns_set_when_query_succeeds(self):
        try:
            from app.services.recommendation_service import (
                _load_muted_entities_safe,
            )
        except BaseException:
            pytest.skip("recommendation_service import requires full deps")

        mock_session = AsyncMock()
        mock_result = MagicMock()
        mock_result.all.return_value = [("Elon Musk",), ("Donald Trump",)]
        mock_session.execute = AsyncMock(return_value=mock_result)

        muted = await _load_muted_entities_safe(mock_session, uuid4())

        assert muted == {"Elon Musk", "Donald Trump"}

    @pytest.mark.asyncio
    async def test_returns_empty_set_on_missing_table(self):
        """Régression outage PR #395 : si la migration Epic 13 n'a pas encore
        été appliquée, la requête lève `UndefinedTable`. Le feed doit
        dégrader (set vide) plutôt que propager et faire tomber `/api/feed/`.
        """
        try:
            from app.services.recommendation_service import (
                _load_muted_entities_safe,
            )
        except BaseException:
            pytest.skip("recommendation_service import requires full deps")

        mock_session = AsyncMock()
        # Simule une Postgres UndefinedTable error propagée par SQLAlchemy.
        mock_session.execute = AsyncMock(
            side_effect=Exception(
                'relation "user_entity_preferences" does not exist'
            )
        )

        muted = await _load_muted_entities_safe(mock_session, uuid4())

        assert muted == set()

    @pytest.mark.asyncio
    async def test_returns_empty_set_on_any_exception(self):
        """Couvre aussi les erreurs transitoires (connection lost, timeout,
        RLS denied) — aucune ne doit faire tomber le feed.
        """
        try:
            from app.services.recommendation_service import (
                _load_muted_entities_safe,
            )
        except BaseException:
            pytest.skip("recommendation_service import requires full deps")

        mock_session = AsyncMock()
        mock_session.execute = AsyncMock(
            side_effect=RuntimeError("connection closed")
        )

        muted = await _load_muted_entities_safe(mock_session, uuid4())

        assert muted == set()


# ------------------------------------------------------------------
# Entity-preference endpoints (under app.routers.personalization)
# ------------------------------------------------------------------


class TestEntityPreferenceEndpoints:
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
    def test_entity_preference_request(self):
        req = EntityPreferenceRequest(
            entity_canonical="Elon Musk", preference="follow"
        )
        assert req.entity_canonical == "Elon Musk"
        assert req.preference == "follow"
