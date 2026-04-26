"""Service pour la note self-reported "bien informé" (Story 14.3)."""

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.well_informed_rating import UserWellInformedRating
from app.schemas.well_informed import WellInformedRatingCreate


async def submit_rating(
    db: AsyncSession,
    user_id: UUID,
    payload: WellInformedRatingCreate,
    device_id: str | None = None,
) -> UserWellInformedRating:
    """Persiste une nouvelle note 1-10 pour l'utilisateur.

    Pas de dédup ici : le cooldown (14j sur submit, 5j sur skip) est enforcé
    côté client via `NudgeService`. Si plusieurs soumissions arrivent — bug
    client, retry, multi-device — on garde toutes les lignes pour analyse.
    """
    rating = UserWellInformedRating(
        user_id=user_id,
        score=payload.score,
        context=payload.context,
        device_id=device_id,
    )
    db.add(rating)
    await db.commit()
    await db.refresh(rating)
    return rating
