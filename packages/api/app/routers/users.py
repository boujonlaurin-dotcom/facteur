"""Routes utilisateur."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.user import (
    OnboardingRequest,
    OnboardingResponse,
    UserProfileResponse,
    UserProfileUpdate,
    UserPreferenceResponse,
    UserInterestResponse,
    UserStatsResponse,
)
from app.schemas.streak import StreakResponse
from app.services.streak_service import StreakService
from app.services.user_service import UserService

router = APIRouter()


@router.get("/profile", response_model=UserProfileResponse)
async def get_profile(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserProfileResponse:
    """Récupérer le profil utilisateur."""
    service = UserService(db)
    profile = await service.get_profile(user_id)

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found",
        )

    return UserProfileResponse.model_validate(profile)


@router.put("/profile", response_model=UserProfileResponse)
async def update_profile(
    data: UserProfileUpdate,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserProfileResponse:
    """Mettre à jour le profil utilisateur."""
    service = UserService(db)
    profile = await service.update_profile(user_id, data)

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found",
        )

    return UserProfileResponse.model_validate(profile)


@router.post("/onboarding", response_model=OnboardingResponse)
async def save_onboarding(
    data: OnboardingRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> OnboardingResponse:
    """Sauvegarder les réponses de l'onboarding."""
    service = UserService(db)
    result = await service.save_onboarding(user_id, data.answers)
    return OnboardingResponse.model_validate(result)


@router.get("/preferences", response_model=list[UserPreferenceResponse])
async def get_preferences(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[UserPreferenceResponse]:
    """Récupérer les préférences utilisateur."""
    service = UserService(db)
    preferences = await service.get_preferences(user_id)

    return [UserPreferenceResponse.model_validate(p) for p in preferences]


@router.get("/interests", response_model=list[UserInterestResponse])
async def get_interests(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[UserInterestResponse]:
    """Récupérer les intérêts utilisateur."""
    service = UserService(db)
    interests = await service.get_interests(user_id)

    return [UserInterestResponse.model_validate(i) for i in interests]


@router.get("/stats", response_model=UserStatsResponse)
async def get_stats(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserStatsResponse:
    """Récupérer les statistiques utilisateur."""
    service = UserService(db)
    stats = await service.get_stats(user_id)

    return stats

    return stats


@router.get("/streak", response_model=StreakResponse)
async def get_streak(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> StreakResponse:
    """Récupérer le streak actuel."""
    service = StreakService(db)
    return await service.get_streak(user_id)
