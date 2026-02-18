"""Schemas utilisateur."""

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


class UserProfileCreate(BaseModel):
    """Création d'un profil utilisateur."""

    display_name: Optional[str] = None


class UserProfileUpdate(BaseModel):
    """Mise à jour du profil utilisateur."""

    display_name: Optional[str] = None
    gamification_enabled: Optional[bool] = None
    weekly_goal: Optional[int] = Field(None, ge=3, le=7)


class UserProfileResponse(BaseModel):
    """Réponse profil utilisateur."""

    id: UUID
    user_id: UUID
    display_name: Optional[str]
    age_range: Optional[str]
    gender: Optional[str]
    onboarding_completed: bool
    gamification_enabled: bool
    weekly_goal: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class UserPreferenceResponse(BaseModel):
    """Réponse préférence utilisateur."""

    preference_key: str
    preference_value: str

    class Config:
        from_attributes = True


class UserInterestResponse(BaseModel):
    """Réponse intérêt utilisateur."""

    interest_slug: str
    weight: float

    class Config:
        from_attributes = True


class OnboardingAnswers(BaseModel):
    """Réponses du questionnaire d'onboarding."""

    # Section 1 - Overview
    objective: str = Field(..., description="Objectif : learn, culture, professional")
    age_range: str = Field(..., description="Tranche d'âge")
    gender: Optional[str] = None
    approach: str = Field(..., description="direct ou detailed")

    # Section 2 - App Preferences
    perspective: str = Field(..., description="big_picture ou detail_oriented")
    response_style: str = Field(..., description="decisive ou nuanced")
    content_recency: Optional[str] = Field(None, description="recent ou evergreen (deprecated)")
    gamification_enabled: bool = True
    weekly_goal: Optional[int] = Field(5, ge=3, le=7, description="Daily article count (3/5/7)")
    digest_mode: Optional[str] = Field("pour_vous", description="pour_vous, serein, perspective")

    # Section 3 - Source Preferences
    preferred_sources: Optional[list[str]] = Field(default_factory=list, description="Liste des sources sélectionnées")
    themes: Optional[list[str]] = Field(default_factory=list, description="Liste des thèmes sélectionnés")
    subtopics: Optional[list[str]] = Field(default_factory=list, description="Topics granulaires sélectionnés")
    format_preference: Optional[str] = Field("mixed", description="short, long, mixed")
    personal_goal: Optional[str] = Field(None, description="Objectif personnel")

    class Config:
        populate_by_name = True
        alias_generator = lambda s: "".join(
            word.capitalize() if i > 0 else word for i, word in enumerate(s.split("_"))
        )


class OnboardingRequest(BaseModel):
    """Requête de sauvegarde de l'onboarding."""

    answers: OnboardingAnswers


class OnboardingResponse(BaseModel):
    """Réponse détaillée de l'onboarding."""

    profile: UserProfileResponse
    interests_created: int
    subtopics_created: int
    preferences_created: int


class UserStatsResponse(BaseModel):
    """Statistiques utilisateur."""

    this_week: int
    this_month: int
    total: int
    by_type: dict[str, int]
    by_theme: dict[str, int]

