"""Routes utilisateur."""

import logging
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy import select as sa_select
from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.streak import StreakResponse
from app.schemas.user import (
    AlgorithmProfileResponse,
    OnboardingRequest,
    OnboardingResponse,
    UserInterestResponse,
    UserPreferenceResponse,
    UserProfileResponse,
    UserProfileUpdate,
    UserStatsResponse,
)
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
    try:
        result = await service.save_onboarding(user_id, data.answers)
        return OnboardingResponse.model_validate(result)
    except Exception as e:
        logger.error(f"Onboarding save failed for user {user_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save onboarding data. Please retry.",
        )


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


@router.get("/algorithm-profile", response_model=AlgorithmProfileResponse)
async def get_algorithm_profile(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> AlgorithmProfileResponse:
    """Profil algorithmique : poids appris par thème/subtopic + affinités sources."""
    from app.models.user import UserInterest, UserSubtopic
    from app.services.recommendation_service import RecommendationService

    # Interest weights
    interest_rows = (
        await db.execute(
            sa_select(UserInterest.interest_slug, UserInterest.weight).where(
                UserInterest.user_id == user_id
            )
        )
    ).all()
    interest_weights = {row.interest_slug: row.weight for row in interest_rows}

    # Subtopic weights
    subtopic_rows = (
        await db.execute(
            sa_select(UserSubtopic.topic_slug, UserSubtopic.weight).where(
                UserSubtopic.user_id == user_id
            )
        )
    ).all()
    subtopic_weights = {row.topic_slug: row.weight for row in subtopic_rows}

    # Source affinities (reuse recommendation service logic)
    reco_service = RecommendationService(db)
    affinity_map = await reco_service._compute_source_affinity(user_id)
    source_affinities = {str(sid): score for sid, score in affinity_map.items()}

    return AlgorithmProfileResponse(
        interest_weights=interest_weights,
        subtopic_weights=subtopic_weights,
        source_affinities=source_affinities,
    )


@router.post("/interests/{slug}/reset")
async def reset_interest_weight(
    slug: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, bool]:
    """Remet le poids appris d'un thème à 1.0 (neutre)."""
    from sqlalchemy import update

    from app.models.user import UserInterest

    result = await db.execute(
        update(UserInterest)
        .where(UserInterest.user_id == user_id, UserInterest.interest_slug == slug)
        .values(weight=1.0)
    )
    await db.commit()
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Interest not found")
    return {"success": True}


@router.post("/subtopics/{slug}/reset")
async def reset_subtopic_weight(
    slug: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, bool]:
    """Remet le poids appris d'un subtopic à 1.0 (neutre)."""
    from sqlalchemy import update

    from app.models.user import UserSubtopic

    result = await db.execute(
        update(UserSubtopic)
        .where(UserSubtopic.user_id == user_id, UserSubtopic.topic_slug == slug)
        .values(weight=1.0)
    )
    await db.commit()
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Subtopic not found")
    return {"success": True}


@router.get("/stats", response_model=UserStatsResponse)
async def get_stats(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserStatsResponse:
    """Récupérer les statistiques utilisateur."""
    service = UserService(db)
    stats = await service.get_stats(user_id)

    return stats


@router.get("/streak", response_model=StreakResponse)
async def get_streak(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> StreakResponse:
    """Récupérer le streak actuel."""
    service = StreakService(db)
    return await service.get_streak(user_id)


class PreferenceUpdateRequest(BaseModel):
    """Requête de mise à jour de préférence clé-valeur."""

    key: str
    value: str


class PreferenceUpdateResponse(BaseModel):
    """Réponse de mise à jour de préférence."""

    success: bool
    key: str
    value: str


@router.put("/preferences", response_model=PreferenceUpdateResponse)
async def update_preference(
    data: PreferenceUpdateRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> PreferenceUpdateResponse:
    """Mettre à jour une préférence utilisateur (upsert clé-valeur)."""
    service = UserService(db)
    await service.upsert_preference(user_id, data.key, data.value)
    return PreferenceUpdateResponse(success=True, key=data.key, value=data.value)


class TopThemeResponse(BaseModel):
    """Un thème utilisateur avec son poids."""

    interest_slug: str
    weight: float
    article_count: int = 0


@router.get("/top-themes", response_model=list[TopThemeResponse])
async def get_top_themes(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[TopThemeResponse]:
    """Retourne les thèmes de l'utilisateur triés par poids décroissant.

    Themes with no recent articles (last 14 days) are excluded.
    """
    from app.models.content import Content

    service = UserService(db)
    interests = await service.get_interests(user_id)

    if not interests:
        return []

    # Count recent articles per theme (last 14 days) in a single query
    cutoff = datetime.now(UTC) - timedelta(days=14)
    slugs = [i.interest_slug for i in interests]
    count_rows = (
        await db.execute(
            sa_select(Content.theme, func.count(Content.id))
            .where(Content.theme.in_(slugs), Content.published_at >= cutoff)
            .group_by(Content.theme)
        )
    ).all()
    theme_counts = {row[0]: row[1] for row in count_rows}

    themes = sorted(interests, key=lambda i: i.weight, reverse=True)
    return [
        TopThemeResponse(
            interest_slug=i.interest_slug,
            weight=i.weight,
            article_count=theme_counts.get(i.interest_slug, 0),
        )
        for i in themes
        if theme_counts.get(i.interest_slug, 0) > 0
    ]
