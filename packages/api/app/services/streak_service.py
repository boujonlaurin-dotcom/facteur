"""Service streak et gamification."""

from datetime import date, timedelta
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.analytics import AnalyticsEvent
from app.models.user import UserProfile, UserStreak
from app.schemas.streak import (
    StreakActivityDayResponse,
    StreakActivityResponse,
    StreakResponse,
)


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
        Incrémente le compteur hebdomadaire de lecture.

        Le streak quotidien est désormais piloté par `session_start` :
        cette méthode conserve uniquement le suivi de progression hebdo.
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

        await self.db.flush()
        return streak

    async def record_session_start(
        self,
        user_id: str,
        *,
        local_date: date | None = None,
    ) -> UserStreak | None:
        """Met à jour le streak d'ouverture d'app, idempotent par jour."""
        profile = await self._get_profile(user_id)
        if not profile or not profile.gamification_enabled:
            return None

        streak = await self._get_or_create_streak(user_id)
        activity_date = local_date or date.today()

        if streak.last_activity_date:
            if activity_date < streak.last_activity_date:
                return streak

            days_since = (activity_date - streak.last_activity_date).days
            if days_since == 0:
                return streak
            if days_since == 1:
                streak.current_streak = (
                    streak.current_streak + 1 if streak.current_streak > 0 else 1
                )
            else:
                streak.current_streak = 1
        else:
            streak.current_streak = 1

        streak.last_activity_date = activity_date
        if streak.current_streak > streak.longest_streak:
            streak.longest_streak = streak.current_streak

        await self.db.flush()
        return streak

    async def get_activity(self, user_id: str, days: int = 14) -> StreakActivityResponse:
        """Construit l'activité d'ouverture d'app sur les N derniers jours."""
        streak = await self._get_or_create_streak(user_id)
        user_uuid = UUID(user_id)
        today = date.today()
        start_date = today - timedelta(days=days - 1)
        since_date = start_date - timedelta(days=1)

        query = (
            select(AnalyticsEvent)
            .where(
                AnalyticsEvent.user_id == user_uuid,
                AnalyticsEvent.event_type.in_(
                    ["session_start", "content_interaction", "article_read"]
                ),
                func.date(AnalyticsEvent.created_at) >= since_date,
            )
            .order_by(AnalyticsEvent.created_at.asc())
        )
        result = await self.db.execute(query)
        events = result.scalars().all()

        opened_dates: set[date] = set()
        articles_read_by_day: dict[date, int] = {}

        for event in events:
            event_date = self._event_local_date(event)
            if event_date < start_date or event_date > today:
                continue

            if event.event_type == "session_start":
                opened_dates.add(event_date)
                continue

            if event.event_type == "content_interaction":
                if event.event_data.get("action") != "read":
                    continue

            # Reading implies the app was opened, even for historical days
            # recorded before `session_start` became the streak source.
            opened_dates.add(event_date)
            articles_read_by_day[event_date] = articles_read_by_day.get(event_date, 0) + 1

        activity_days = [
            StreakActivityDayResponse(
                date=day,
                opened=day in opened_dates,
                articles_read=(
                    articles_read_by_day[day]
                    if articles_read_by_day.get(day, 0) > 0
                    else None
                ),
            )
            for day in (
                start_date + timedelta(days=offset) for offset in range(days)
            )
        ]

        return StreakActivityResponse(
            current_streak=streak.current_streak,
            longest_streak=streak.longest_streak,
            last_activity_date=streak.last_activity_date,
            days=activity_days,
        )

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

    @staticmethod
    def _event_local_date(event: AnalyticsEvent) -> date:
        """Utilise `event_data.local_date` si disponible, sinon `created_at`."""
        raw_local_date = event.event_data.get("local_date")
        if isinstance(raw_local_date, str):
            try:
                return date.fromisoformat(raw_local_date)
            except ValueError:
                pass
        return event.created_at.date()
