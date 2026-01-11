"""Schemas streak et progression."""

from datetime import date
from typing import Optional

from pydantic import BaseModel


class StreakResponse(BaseModel):
    """Réponse streak et progression."""

    current_streak: int
    longest_streak: int
    last_activity_date: Optional[date]
    weekly_count: int
    weekly_goal: int
    weekly_progress: float  # 0.0 à 1.0

    class Config:
        from_attributes = True

