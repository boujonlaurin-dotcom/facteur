"""Service utilisateur."""

from uuid import UUID, uuid4

import structlog
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.source import Source, UserSource
from app.models.user import (
    UserInterest,
    UserPreference,
    UserProfile,
    UserStreak,
    UserSubtopic,
)
from app.models.user_topic_profile import UserTopicProfile
from app.schemas.user import OnboardingAnswers, UserProfileUpdate, UserStatsResponse
from app.services.ml.classification_service import SLUG_TO_LABEL

logger = structlog.get_logger(__name__)


class UserService:
    """Service pour la gestion des utilisateurs."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_profile(self, user_id: str) -> UserProfile | None:
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
        """Crée le streak s'il n'existe pas, en gérant les race conditions.

        Uses a savepoint (nested transaction) so that an IntegrityError only
        rolls back the streak INSERT, not the entire transaction — preventing
        silent data loss of previously flushed objects like UserProfile.
        """
        result = await self.db.execute(
            select(UserStreak).where(UserStreak.user_id == UUID(user_id))
        )
        if not result.scalar_one_or_none():
            try:
                async with self.db.begin_nested():
                    streak = UserStreak(
                        id=uuid4(),
                        user_id=UUID(user_id),
                    )
                    self.db.add(streak)
                    await self.db.flush()
            except IntegrityError:
                # Race condition: streak was created by another request.
                # The savepoint is rolled back automatically, outer transaction intact.
                logger.info(
                    f"Streak already exists for user {user_id} (race condition handled)"
                )

    async def update_profile(
        self, user_id: str, data: UserProfileUpdate
    ) -> UserProfile | None:
        """Met à jour le profil utilisateur."""
        profile = await self.get_profile(user_id)
        if not profile:
            return None

        update_data = data.model_dump(exclude_unset=True)
        for key, value in update_data.items():
            setattr(profile, key, value)

        await self.db.flush()
        return profile

    async def save_onboarding(self, user_id: str, answers: OnboardingAnswers) -> dict:
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
        # Note: onboarding topic profiles are now upserted (skip-if-exists)
        # to preserve manual priority changes made post-onboarding.

        # Sauvegarder les préférences
        preferences = {
            "objective": answers.objective,
            "approach": answers.approach,
            "perspective": answers.perspective,
            "response_style": answers.response_style,
            "content_recency": answers.content_recency,
            "format_preference": answers.format_preference,
            "personal_goal": answers.personal_goal,
            "serein_enabled": getattr(answers, "serein_enabled", None),
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

        # Muter les thèmes non-sélectionnés (pour affichage "Mes Intérêts")
        all_themes = {
            "tech", "international", "science", "culture",
            "politics", "society", "environment", "economy", "sport",
        }
        selected_themes = set(answers.themes) if answers.themes else set()
        unselected_themes = sorted(all_themes - selected_themes)

        from sqlalchemy.dialects.postgresql import insert as pg_insert
        from app.models.user_personalization import UserPersonalization

        stmt = (
            pg_insert(UserPersonalization)
            .values(
                user_id=UUID(user_id),
                muted_themes=unselected_themes,
            )
            .on_conflict_do_update(
                index_elements=["user_id"],
                set_={"muted_themes": unselected_themes},
            )
        )
        await self.db.execute(stmt)

        # Sauvegarder les sous-thèmes + créer les topic profiles correspondants
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

                # Create UserTopicProfile only if not already followed
                # (preserves manual priority changes from post-onboarding edits)
                existing_profile = await self.db.scalar(
                    select(UserTopicProfile).where(
                        UserTopicProfile.user_id == UUID(user_id),
                        UserTopicProfile.slug_parent == topic_slug,
                    )
                )
                if not existing_profile:
                    topic_profile = UserTopicProfile(
                        user_id=UUID(user_id),
                        topic_name=SLUG_TO_LABEL.get(
                            topic_slug, topic_slug.capitalize()
                        ),
                        slug_parent=topic_slug,
                        keywords=[topic_slug],
                        source_type="onboarding",
                        priority_multiplier=1.0,
                        composite_score=0.0,
                    )
                    self.db.add(topic_profile)

        # Sauvegarder les sources sélectionnées (UserSource)
        # Atomique avec le reste de l'onboarding — pas de race condition
        sources_created = 0
        sources_removed = 0
        if answers.preferred_sources:
            # Valider les UUIDs
            valid_source_ids: set[UUID] = set()
            invalid_sids: list[str] = []
            for sid in answers.preferred_sources:
                try:
                    valid_source_ids.add(UUID(sid))
                except ValueError:
                    invalid_sids.append(sid)

            if invalid_sids:
                logger.warning(
                    "onboarding_invalid_source_ids",
                    user_id=user_id,
                    invalid_ids=invalid_sids,
                )

            if valid_source_ids:
                # Vérifier que les sources existent réellement en DB (évite FK violation)
                existing_sources_result = await self.db.execute(
                    select(Source.id).where(
                        Source.id.in_(list(valid_source_ids)),
                        Source.is_active,
                    )
                )
                existing_source_ids = set(existing_sources_result.scalars().all())

                # Log les sources qui n'existent pas/plus
                missing = valid_source_ids - existing_source_ids
                if missing:
                    logger.warning(
                        "onboarding_sources_not_found",
                        user_id=user_id,
                        missing_source_ids=[str(s) for s in missing],
                    )
                # Ne garder que les sources valides
                valid_source_ids = existing_source_ids

            if valid_source_ids:
                # Vérifier lesquelles l'utilisateur a déjà
                already_result = await self.db.execute(
                    select(UserSource.source_id).where(
                        UserSource.user_id == UUID(user_id),
                        UserSource.source_id.in_(list(valid_source_ids)),
                    )
                )
                already_trusted = set(already_result.scalars().all())

                for source_id in valid_source_ids - already_trusted:
                    user_source = UserSource(
                        id=uuid4(),
                        user_id=UUID(user_id),
                        source_id=source_id,
                        is_custom=False,
                    )
                    self.db.add(user_source)
                    sources_created += 1

            # Supprimer les sources désélectionnées (sync re-onboarding)
            # Ne supprime que les sources non-custom ajoutées via onboarding
            all_user_sources_result = await self.db.execute(
                select(UserSource).where(
                    UserSource.user_id == UUID(user_id),
                    UserSource.is_custom.is_(False),
                )
            )
            all_user_sources = all_user_sources_result.scalars().all()
            for us in all_user_sources:
                if us.source_id not in valid_source_ids:
                    await self.db.delete(us)
                    sources_removed += 1
        else:
            logger.warning(
                "onboarding_no_preferred_sources",
                user_id=user_id,
                preferred_sources_raw=answers.preferred_sources,
            )

        await self.db.flush()

        logger.info(
            "onboarding_saved",
            user_id=user_id,
            interests_created=interest_count,
            subtopics_created=subtopic_count,
            preferences_created=pref_count,
            sources_created=sources_created,
            sources_removed=sources_removed,
            preferred_sources_count=len(answers.preferred_sources)
            if answers.preferred_sources
            else 0,
        )

        return {
            "profile": profile,
            "interests_created": interest_count,
            "subtopics_created": subtopic_count,
            "preferences_created": pref_count,
            "sources_created": sources_created,
            "sources_removed": sources_removed,
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
