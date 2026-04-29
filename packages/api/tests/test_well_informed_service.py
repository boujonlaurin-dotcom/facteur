"""Tests pour la note self-reported "bien informé" (Story 14.3)."""

import sys
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

# Mock feedparser et dépendances (supprimées de Python 3.x) — cohérent avec
# test_learning_service.py pour éviter d'importer toute la stack prod.
if "feedparser" not in sys.modules:
    sys.modules["feedparser"] = MagicMock()
if "sgmllib" not in sys.modules:
    sys.modules["sgmllib"] = MagicMock()

from app.schemas.well_informed import WellInformedRatingCreate
from app.services.well_informed_service import submit_rating


class TestWellInformedService:
    @pytest.mark.asyncio
    async def test_submit_rating_persists_row(self):
        """submit_rating ajoute une ligne, commit, puis refresh."""
        mock_db = AsyncMock()
        user_id = uuid4()
        payload = WellInformedRatingCreate(score=7, context="digest_inline")

        rating = await submit_rating(
            mock_db, user_id, payload, device_id="device-xyz"
        )

        assert rating.user_id == user_id
        assert rating.score == 7
        assert rating.context == "digest_inline"
        assert rating.device_id == "device-xyz"
        mock_db.add.assert_called_once()
        mock_db.commit.assert_awaited_once()
        mock_db.refresh.assert_awaited_once_with(rating)

    @pytest.mark.asyncio
    async def test_submit_rating_default_context(self):
        mock_db = AsyncMock()
        payload = WellInformedRatingCreate(score=10)

        rating = await submit_rating(mock_db, uuid4(), payload)

        assert rating.context == "digest_inline"
        assert rating.device_id is None

    @pytest.mark.asyncio
    async def test_submit_rating_score_boundaries(self):
        """Les bornes 1 et 10 sont valides."""
        mock_db = AsyncMock()

        r_low = await submit_rating(
            mock_db, uuid4(), WellInformedRatingCreate(score=1)
        )
        r_high = await submit_rating(
            mock_db, uuid4(), WellInformedRatingCreate(score=10)
        )

        assert r_low.score == 1
        assert r_high.score == 10


class TestWellInformedSchema:
    def test_score_lower_bound_rejected(self):
        from pydantic import ValidationError

        with pytest.raises(ValidationError):
            WellInformedRatingCreate(score=0)

    def test_score_upper_bound_rejected(self):
        from pydantic import ValidationError

        with pytest.raises(ValidationError):
            WellInformedRatingCreate(score=11)

    def test_score_negative_rejected(self):
        from pydantic import ValidationError

        with pytest.raises(ValidationError):
            WellInformedRatingCreate(score=-3)

    def test_default_context(self):
        payload = WellInformedRatingCreate(score=5)
        assert payload.context == "digest_inline"

    def test_custom_context(self):
        payload = WellInformedRatingCreate(score=5, context="settings_prompt")
        assert payload.context == "settings_prompt"


class TestWellInformedRouter:
    @pytest.mark.asyncio
    async def test_create_rating_returns_read_schema(self):
        """Le handler instancie un WellInformedRatingRead depuis le modèle."""
        try:
            from app.routers.well_informed import create_rating
        except BaseException:
            pytest.skip("Router import requires full deps (cryptography)")

        from unittest.mock import patch

        mock_db = AsyncMock()
        user_id = uuid4()
        payload = WellInformedRatingCreate(score=8)

        from app.models.well_informed_rating import UserWellInformedRating

        fake = UserWellInformedRating(
            user_id=user_id,
            score=8,
            context="digest_inline",
        )
        # Assigner un id manuellement (model_validate le réclame).
        fake.id = uuid4()
        from datetime import datetime, timezone

        fake.submitted_at = datetime.now(tz=timezone.utc)

        with patch(
            "app.routers.well_informed.submit_rating",
            AsyncMock(return_value=fake),
        ):
            response = await create_rating(
                payload=payload,
                device_id=None,
                user_id=user_id,
                db=mock_db,
            )

        assert response.score == 8
        assert response.context == "digest_inline"
