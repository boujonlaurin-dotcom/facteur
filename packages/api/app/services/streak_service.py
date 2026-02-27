"""Service streak et gamification."""

from datetime import date, timedelta
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import UserProfile, UserStreak
from app.schemas.streak import StreakResponse


class StreakService:
    """Service pour la gestion des streaks."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_streak(self, user_id: str) -> StreakResponse:
        """Récupère le streak et la progression."""
        streak = await self._get_or_create_streak(user_id)
        profile = await self._get_profile(user_id)

        weekly_goal = profile.weekly_goal if profile else 10

        return StreakResponse(
            current_streak=streak.current_streak,
            longest_streak=streak.longest_streak,
            last_activity_date=streak.last_activity_date,
            weekly_count=streak.weekly_count,
            weekly_goal=weekly_goal,
            weekly_progress=min(1.0, streak.weekly_count / weekly_goal),
        )

    async def increment_consumption(self, user_id: str) -> UserStreak:
        """
        Incrémente le compteur de consommation.

        Met à jour le streak quotidien et le compteur hebdomadaire.
        """
        streak = await self._get_or_create_streak(user_id)
        today = date.today()

        # Vérifier si on doit reset la semaine
        week_start = today - timedelta(days=today.weekday())
        if streak.week_start != week_start:
            streak.weekly_count = 0
            streak.week_start = week_start

        # Incrémenter le compteur hebdo
        streak.weekly_count += 1

        # Gérer le streak quotidien
        if streak.last_activity_date:
            days_since = (today - streak.last_activity_date).days

            if days_since == 0:
                # Déjà actif aujourd'hui, ne pas incrémenter le streak
                pass
            elif days_since == 1:
                # Jour consécutif, incrémenter le streak
                streak.current_streak += 1
            else:
                # Streak cassé, reset à 1
                streak.current_streak = 1
        else:
            # Premier jour d'activité
            streak.current_streak = 1

        streak.last_activity_date = today

        # Mettre à jour le record
        if streak.current_streak > streak.longest_streak:
            streak.longest_streak = streak.current_streak

        await self.db.flush()
        return streak

    async def _get_or_create_streak(self, user_id: str) -> UserStreak:
        """Récupère ou crée le streak d'un utilisateur."""
        query = select(UserStreak).where(UserStreak.user_id == UUID(user_id))
        result = await self.db.execute(query)
        streak = result.scalar_one_or_none()

        if not streak:
            streak = UserStreak(
                id=uuid4(),
                user_id=UUID(user_id),
                week_start=date.today() - timedelta(days=date.today().weekday()),
            )
            self.db.add(streak)
            await self.db.flush()

        return streak

    async def _get_profile(self, user_id: str) -> UserProfile | None:
        """Récupère le profil utilisateur."""
        query = select(UserProfile).where(UserProfile.user_id == UUID(user_id))
        result = await self.db.execute(query)
        return result.scalar_one_or_none()
