"""Modèle GrillePuzzle — le mot du jour de « La Grille du jour » (Story 24.1).

Un puzzle global daté : une ligne par jour, identique pour tous les joueurs.
Le `word` est le secret serveur — il n'est jamais exposé au client tant que la
partie n'est pas terminée (validation 100 % serveur).
"""

import uuid
from datetime import date, datetime
from uuid import UUID

from sqlalchemy import Date, DateTime, SmallInteger, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class GrillePuzzle(Base):
    """Puzzle quotidien de La Grille du jour.

    Attributes:
        puzzle_date: Date du puzzle (clé du jour, = target_date du digest).
        word: Mot du jour, MAJUSCULES sans accent — secret serveur.
        length: Longueur du mot (6 par défaut).
        max_attempts: Nombre d'essais maximum (6 par défaut).
        indice: Indice affiché au joueur (« Le mot qui a traversé ta tournée… »).
        theme: Thème éditorial (« Environnement · Société »).
        pourquoi: Reveal pédago (voix du Facteur), révélé en fin de partie.
        numero: Numéro d'édition (« N°143 »).
        date_affichee: Date longue pour le masthead (« Vendredi 30 mai »).
        date_court: Date courte pour le pied de partage (« Ven. 30 mai »).
        cancel: Date d'oblitération du cachet (« 30·05·26 »).
    """

    __tablename__ = "grille_puzzles"
    __table_args__ = (UniqueConstraint("puzzle_date", name="uq_grille_puzzles_date"),)

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    puzzle_date: Mapped[date] = mapped_column(Date, nullable=False)
    word: Mapped[str] = mapped_column(String(8), nullable=False)
    length: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, default=6, server_default="6"
    )
    max_attempts: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, default=6, server_default="6"
    )
    indice: Mapped[str] = mapped_column(Text, nullable=False)
    theme: Mapped[str] = mapped_column(String, nullable=False)
    pourquoi: Mapped[str] = mapped_column(Text, nullable=False)
    numero: Mapped[str] = mapped_column(String, nullable=False)
    date_affichee: Mapped[str] = mapped_column(String, nullable=False)
    date_court: Mapped[str] = mapped_column(String, nullable=False)
    cancel: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )
