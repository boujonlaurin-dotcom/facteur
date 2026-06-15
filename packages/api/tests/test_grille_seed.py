"""Tests du seed idempotent des puzzles de « La Grille du jour ».

Régression docs/bugs/bug-grille-du-jour-crash.md : la table `grille_puzzles`
était vide en prod (seed manuel-only jamais exécuté) → 404 → écran gris mobile.
Ces tests garantissent aussi qu'un jour absent du calendrier embarqué est créé
de façon déterministe sans réécrire les puzzles déjà publiés.
"""

from datetime import date

import pytest
from sqlalchemy import func, select

from app.models.grille_puzzle import GrillePuzzle
from app.services.grille_seed import (
    ensure_daily_puzzle,
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
    # 2e passage : rien n'est modifié et aucun doublon n'est créé.
    created2, updated2 = await seed_puzzles(db_session)
    await db_session.commit()

    _, puzzles = load_seed()
    assert (created1, updated1) == (len(puzzles), 0)
    assert (created2, updated2) == (0, 0)
    assert await _count(db_session) == len(puzzles)


@pytest.mark.asyncio
async def test_ensure_daily_puzzle_creates_stable_post_seed_fallback(db_session):
    target_date = date(2026, 6, 15)

    first = await ensure_daily_puzzle(db_session, target_date)
    await db_session.flush()
    second = await ensure_daily_puzzle(db_session, target_date)

    assert first.id == second.id
    assert first.word == second.word
    assert first.numero == "N°159"
    assert first.date_affichee == "Lundi 15 juin"
    assert first.date_court == "Lun. 15 juin"
    assert first.cancel == "15·06·26"
    assert first.indice == "Un mot de six lettres choisi dans les repères de Facteur"
    assert "actualité" not in first.pourquoi.lower()
    assert (
        await db_session.scalar(
            select(func.count())
            .select_from(GrillePuzzle)
            .where(GrillePuzzle.puzzle_date == target_date)
        )
        == 1
    )


@pytest.mark.asyncio
async def test_seed_does_not_overwrite_published_hybrid_puzzle(db_session):
    await seed_puzzles(db_session)
    await db_session.commit()
    target_date = date(2026, 6, 13)
    puzzle = await db_session.scalar(
        select(GrillePuzzle).where(GrillePuzzle.puzzle_date == target_date)
    )
    assert puzzle is not None
    puzzle.word = "CLIMAT"
    puzzle.hybrid_word_source = "hybrid"
    puzzle.hybrid_match = "climat"
    await db_session.commit()

    created, updated = await seed_puzzles(db_session)
    await db_session.commit()

    await db_session.refresh(puzzle)
    assert (created, updated) == (0, 0)
    assert puzzle.word == "CLIMAT"
    assert puzzle.hybrid_word_source == "hybrid"
    assert puzzle.hybrid_match == "climat"


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
