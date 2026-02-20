"""Service utilisateur."""

import logging
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import select, delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import UserProfile, UserPreference, UserInterest, UserStreak, UserSubtopic
from app.models.source import Source, UserSource
from app.schemas.user import OnboardingAnswers, UserProfileUpdate, UserStatsResponse

logger = logging.getLogger(__name__)


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

        await self._ensure_streak_exists(user_id)

        return profile

    async def get_or_create_profile(self, user_id: str) -> UserProfile:
        """Récupère ou crée le profil utilisateur."""
        profile = await self.get_profile(user_id)
        if not profile:
            profile = await self.create_profile(user_id)

        await self._ensure_streak_exists(user_id)

        return profile

    async def _ensure_streak_exists(self, user_id: str) -> None:
        """Crée le streak s'il n'existe pas, en gérant les race conditions."""
        result = await self.db.execute(
            select(UserStreak).where(UserStreak.user_id == UUID(user_id))
        )
        if not result.scalar_one_or_none():
            try:
                streak = UserStreak(
                    id=uuid4(),
                    user_id=UUID(user_id),
                )
                self.db.add(streak)
                await self.db.flush()
            except IntegrityError:
                # Race condition: streak was created by another request
                await self.db.rollback()
                logger.info(f"Streak already exists for user {user_id} (race condition handled)")

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
        profile.weekly_goal = answers.weekly_goal or 5
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
        await self.db.execute(
            delete(UserSubtopic).where(UserSubtopic.user_id == UUID(user_id))
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
            "digest_mode": answers.digest_mode,
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
        if answers.themes:
            for interest_slug in answers.themes:
                interest = UserInterest(
                    id=uuid4(),
                    user_id=UUID(user_id),
                    interest_slug=interest_slug,
                    weight=1.0,
                )
                self.db.add(interest)
                interest_count += 1

        # Sauvegarder les sous-thèmes
        subtopic_count = 0
        if answers.subtopics:
            for topic_slug in answers.subtopics:
                subtopic = UserSubtopic(
                    id=uuid4(),
                    user_id=UUID(user_id),
                    topic_slug=topic_slug,
                    weight=1.0,
                )
                self.db.add(subtopic)
                subtopic_count += 1

        # Sauvegarder les sources sélectionnées (UserSource)
        # Atomique avec le reste de l'onboarding — pas de race condition
        sources_created = 0
        if answers.preferred_sources:
            # Vérifier quelles sources existent et sont actives
            valid_source_ids = set()
            for sid in answers.preferred_sources:
                try:
                    valid_source_ids.add(UUID(sid))
                except ValueError:
                    continue

            if valid_source_ids:
                existing_result = await self.db.execute(
                    select(UserSource.source_id).where(
                        UserSource.user_id == UUID(user_id),
                        UserSource.source_id.in_(list(valid_source_ids)),
                    )
                )
                already_trusted = set(existing_result.scalars().all())

                for source_id in valid_source_ids - already_trusted:
                    user_source = UserSource(
                        id=uuid4(),
                        user_id=UUID(user_id),
                        source_id=source_id,
                        is_custom=False,
                    )
                    self.db.add(user_source)
                    sources_created += 1

        await self.db.flush()
        return {
            "profile": profile,
            "interests_created": interest_count,
            "subtopics_created": subtopic_count,
            "preferences_created": pref_count,
            "sources_created": sources_created,
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

    async def upsert_preference(self, user_id: str, key: str, value: str) -> None:
        """Upsert une préférence clé-valeur pour l'utilisateur."""
        uid = UUID(user_id)
        result = await self.db.execute(
            select(UserPreference).where(
                UserPreference.user_id == uid,
                UserPreference.preference_key == key,
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            existing.preference_value = value
        else:
            pref = UserPreference(
                id=uuid4(),
                user_id=uid,
                preference_key=key,
                preference_value=value,
            )
            self.db.add(pref)
        await self.db.flush()

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

