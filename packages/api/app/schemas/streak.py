"""Schemas streak et progression."""

from datetime import date

from pydantic import BaseModel

# Objectif journalier de lectures abouties. Constante serveur volontairement :
# il n'existe aucune UI d'édition, et la garder ici permet de recalibrer sans
# release client. Valeur provisoire — à arrêter sur la distribution réelle une
# fois l'instrumentation réparée (aujourd'hui ≈ 1,2 lecture aboutie/jour actif).
# Elle vit dans `schemas` et non dans `streak_service` : `schemas` n'importe
# rien d'applicatif, donc le sens de dépendance reste `services → schemas` et
# le défaut du champ ne peut plus diverger de la valeur servie.
DAILY_COMPLETION_GOAL = 2


class StreakResponse(BaseModel):
    """Réponse streak et progression."""

    current_streak: int
    longest_streak: int
    last_activity_date: date | None
    weekly_count: int
    weekly_goal: int
    weekly_progress: float  # 0.0 à 1.0
    # Lectures abouties de la journée éditoriale (frontière 07h30 Paris).
    # Dérivé de `completed_at`, jamais stocké.
    daily_completed: int = 0
    daily_goal: int = DAILY_COMPLETION_GOAL

    class Config:
        from_attributes = True


class StreakActivityDayResponse(BaseModel):
    """État d'ouverture d'app pour un jour donné."""

    date: date
    opened: bool
    articles_read: int | None = None


class StreakActivityResponse(BaseModel):
    """Réponse d'activité streak pour le calendrier d'ouverture."""

    current_streak: int
    longest_streak: int
    last_activity_date: date | None
    days: list[StreakActivityDayResponse]
