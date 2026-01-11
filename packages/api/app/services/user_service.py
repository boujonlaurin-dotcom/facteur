"""Service utilisateur."""

from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import UserProfile, UserPreference, UserInterest, UserStreak
from app.schemas.user import OnboardingAnswers, UserProfileUpdate, UserStatsResponse


class UserService:
    """Service pour la gestion des utilisateurs."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_profile(self, user_id: str) -> Optional[UserProfile]:
        """Récupère le profil utilisateur."""
        result = await self.db.execute(
            select(UserProfile).where(UserProfile.user_id == UUID(user_id))
        )
        return result.scalar_one_or_none()

    async def create_profile(self, user_id: str) -> UserProfile:
        """Crée un nouveau profil utilisateur."""
        profile = UserProfile(
            id=uuid4(),
            user_id=UUID(user_id),
            onboarding_completed=False,
        )
        self.db.add(profile)
        await self.db.flush()

        # Créer le streak associé
        streak = UserStreak(
            id=uuid4(),
            user_id=UUID(user_id),
        )
        self.db.add(streak)

        return profile

    async def get_or_create_profile(self, user_id: str) -> UserProfile:
        """Récupère ou crée le profil utilisateur."""
        profile = await self.get_profile(user_id)
        if not profile:
            profile = await self.create_profile(user_id)
        return profile

    async def update_profile(
        self, user_id: str, data: UserProfileUpdate
    ) -> Optional[UserProfile]:
        """Met à jour le profil utilisateur."""
        profile = await self.get_profile(user_id)
        if not profile:
            return None

        update_data = data.model_dump(exclude_unset=True)
        for key, value in update_data.items():
            setattr(profile, key, value)

        await self.db.flush()
        return profile

    async def save_onboarding(
        self, user_id: str, answers: OnboardingAnswers
    ) -> dict:
        """Sauvegarde les réponses de l'onboarding."""
        profile = await self.get_or_create_profile(user_id)

        # Mettre à jour le profil (Idempotent)
        profile.age_range = answers.age_range
        profile.gender = answers.gender
        profile.gamification_enabled = answers.gamification_enabled
        profile.weekly_goal = answers.weekly_goal or 10
        profile.onboarding_completed = True

        # Nettoyer les anciennes préférences et intérêts pour garantir l'idempotence
        # Cela permet de gérer les retries ou les erreurs partielles sans dupliquer les données
        # ou causer des erreurs d'intégrité si des contraintes d'unicité existent.
        await self.db.execute(
            delete(UserPreference).where(UserPreference.user_id == UUID(user_id))
        )
        await self.db.execute(
            delete(UserInterest).where(UserInterest.user_id == UUID(user_id))
        )

        # Sauvegarder les préférences
        preferences = {
            "objective": answers.objective,
            "approach": answers.approach,
            "perspective": answers.perspective,
            "response_style": answers.response_style,
            "content_recency": answers.content_recency,
            "format_preference": answers.format_preference,
            "personal_goal": answers.personal_goal,
        }

        pref_count = 0
        for key, value in preferences.items():
            if value is None:
                continue
            pref = UserPreference(
                id=uuid4(),
                user_id=UUID(user_id),
                preference_key=key,
                preference_value=str(value),
            )
            self.db.add(pref)
            pref_count += 1

        # Sauvegarder les intérêts
        interest_count = 0
        for interest_slug in answers.themes:
            interest = UserInterest(
                id=uuid4(),
                user_id=UUID(user_id),
                interest_slug=interest_slug,
                weight=1.0,
            )
            self.db.add(interest)
            interest_count += 1

        await self.db.flush()
        return {
            "profile": profile,
            "interests_created": interest_count,
            "preferences_created": pref_count,
        }

    async def get_preferences(self, user_id: str) -> list[UserPreference]:
        """Récupère les préférences utilisateur."""
        result = await self.db.execute(
            select(UserPreference).where(UserPreference.user_id == UUID(user_id))
        )
        return list(result.scalars().all())

    async def get_interests(self, user_id: str) -> list[UserInterest]:
        """Récupère les intérêts utilisateur."""
        result = await self.db.execute(
            select(UserInterest).where(UserInterest.user_id == UUID(user_id))
        )
        return list(result.scalars().all())

    async def get_stats(self, user_id: str) -> UserStatsResponse:
        """Récupère les statistiques utilisateur."""
        # TODO: Implémenter les vraies stats avec des requêtes SQL
        return UserStatsResponse(
            this_week=0,
            this_month=0,
            total=0,
            by_type={},
            by_theme={},
        )

