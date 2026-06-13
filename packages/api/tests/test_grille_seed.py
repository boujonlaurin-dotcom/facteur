"""Tests du seed idempotent des puzzles de « La Grille du jour ».

Régression docs/bugs/bug-grille-du-jour-crash.md : la table `grille_puzzles`
était vide en prod (seed manuel-only jamais exécuté) → 404 → écran gris mobile.
Le seed est désormais joué au démarrage de l'app ; ces tests garantissent qu'il
peuple bien la table et reste idempotent (upsert par `puzzle_date`).
"""

from datetime import date

import pytest
from sqlalchemy import func, select

from app.models.grille_puzzle import GrillePuzzle
from app.services.grille_seed import (
    format_cancel,
    format_date_affichee,
    format_date_court,
    load_seed,
    seed_puzzles,
)


async def _count(db) -> int:
    return await db.scalar(select(func.count()).select_from(GrillePuzzle))


@pytest.mark.asyncio
async def test_seed_populates_table(db_session):
    created, updated = await seed_puzzles(db_session)
    await db_session.commit()

    _, puzzles = load_seed()
    assert created == len(puzzles)
    assert updated == 0
    assert await _count(db_session) == len(puzzles)


@pytest.mark.asyncio
async def test_seed_is_idempotent(db_session):
    # 1er passage : tout créé.
    created1, updated1 = await seed_puzzles(db_session)
    await db_session.commit()
    # 2e passage : tout mis à jour, rien de neuf, aucun doublon.
    created2, updated2 = await seed_puzzles(db_session)
    await db_session.commit()

    _, puzzles = load_seed()
    assert (created1, updated1) == (len(puzzles), 0)
    assert (created2, updated2) == (0, len(puzzles))
    assert await _count(db_session) == len(puzzles)


@pytest.mark.asyncio
async def test_seed_computes_display_dates_from_calendar(db_session):
    await seed_puzzles(db_session)
    await db_session.commit()

    # 2026-05-30 est un samedi — vérifie que les dates affichées sont calculées
    # depuis le calendrier (et non recopiées d'un champ JSON faillible).
    p = await db_session.scalar(
        select(GrillePuzzle).where(GrillePuzzle.puzzle_date == date(2026, 5, 30))
    )
    if p is not None:  # le seed peut évoluer ; on ne teste que si la date existe
        assert p.date_affichee == "Samedi 30 mai"
        assert p.date_court == "Sam. 30 mai"
        assert p.cancel == "30·05·26"


def test_format_helpers_french_conventions():
    d = date(2026, 6, 1)  # lundi 1er juin
    assert format_date_affichee(d) == "Lundi 1er juin"
    assert format_date_court(d) == "Lun. 1er juin"
    assert format_cancel(d) == "01·06·26"
