"""Modèle GrilleGameState — partie d'un utilisateur pour « La Grille du jour ».

Une partie par (user_id, puzzle_date). Les propositions sont stockées dans
l'ordre (MAJUSCULES) ; les états par case sont recalculés côté serveur à la
volée pour ne jamais persister le mot dérivé côté client.
"""

import uuid
from datetime import date, datetime
from uuid import UUID

from sqlalchemy import (
    Date,
    DateTime,
    Index,
    SmallInteger,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Statuts possibles d'une partie.
STATUS_IN_PROGRESS = "in_progress"
STATUS_SOLVED = "solved"
STATUS_FAILED = "failed"


class GrilleGameState(Base):
    """État de partie par utilisateur et par jour.

    Attributes:
        user_id: UUID de l'utilisateur.
        puzzle_date: Date du puzzle joué.
        guesses: Propositions MAJUSCULES dans l'ordre (liste JSONB).
        status: in_progress | solved | failed.
        attempts: Nombre d'essais consommés.
        finished_at: Date/heure de fin de partie (null tant qu'en cours).
    """

    __tablename__ = "grille_game_states"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "puzzle_date", name="uq_grille_game_states_user_date"
        ),
        Index("ix_grille_game_states_puzzle_date", "puzzle_date"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    puzzle_date: Mapped[date] = mapped_column(Date, nullable=False)
    guesses: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )
    status: Mapped[str] = mapped_column(
        String,
        nullable=False,
        default=STATUS_IN_PROGRESS,
        server_default=STATUS_IN_PROGRESS,
    )
    attempts: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, default=0, server_default="0"
    )
    finished_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )
