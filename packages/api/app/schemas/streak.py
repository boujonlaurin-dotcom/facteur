"""Schemas streak et progression."""

from datetime import date

from pydantic import BaseModel


class StreakResponse(BaseModel):
    """Réponse streak et progression."""

    current_streak: int
    longest_streak: int
    last_activity_date: date | None
    weekly_count: int
    weekly_goal: int
    weekly_progress: float  # 0.0 à 1.0

    class Config:
        from_attributes = True
