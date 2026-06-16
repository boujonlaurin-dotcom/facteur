"""Tests de l'orchestration « mot du jour » → sélection hybride (apply_hybrid_word)."""

from datetime import datetime
from uuid import uuid4

import pytest

from app.models.content import Content
from app.models.enums import ContentType
from app.models.grille_game_state import STATUS_IN_PROGRESS, GrilleGameState
from app.models.grille_puzzle import GrillePuzzle
from app.services.grille_matcher import apply_hybrid_word
from app.utils.time import today_paris


async def _make_puzzle(db, word="CLIMAT"):
    puzzle = GrillePuzzle(
        puzzle_date=today_paris(),
        word=word,
        length=len(word),
        max_attempts=6,
        indice="indice",
        theme="Environnement · Société",
        pourquoi="fallback",
        numero="N°143",
        date_affichee="x",
        date_court="x",
        cancel="x",
    )
    db.add(puzzle)
    await db.commit()
    return puzzle


async def _make_content(db, source_id, *, title, description, url):
    content = Content(
        id=uuid4(),
        source_id=source_id,
        title=title,
        url=url,
        description=description,
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        guid=f"g-{uuid4()}",
    )
    db.add(content)
    await db.commit()
    return content


@pytest.mark.asyncio
async def test_hybrid_overwrites_word_from_actu(db_session, test_source):
    puzzle = await _make_puzzle(db_session, word="MANDAT")
    content = await _make_content(
        db_session,
        test_source.id,
        title="Nouvel espoir pour le climat à Belém",
        description="Les délégations ont trouvé un terrain d'entente.",
        url="https://exemple.fr/climat",
    )

    matched = await apply_hybrid_word(db_session, today_paris(), None)
    assert matched is True

    await db_session.refresh(puzzle)
    assert puzzle.word == "CLIMAT"  # mot extrait de l'actu, pas le seed
    assert puzzle.hybrid_word_source == "hybrid"
    assert puzzle.hybrid_field == "title"
    assert puzzle.hybrid_match == "climat"
    assert puzzle.hybrid_snippet == "Nouvel espoir pour le climat à Belém"
    assert puzzle.featured_content_id == content.id
    assert puzzle.featured_source == test_source.name


@pytest.mark.asyncio
async def test_hybrid_is_idempotent(db_session, test_source):
    puzzle = await _make_puzzle(db_session, word="MANDAT")
    puzzle.hybrid_word_source = "hybrid"
    await db_session.commit()
    await _make_content(
        db_session,
        test_source.id,
        title="Le climat se réchauffe",
        description="x",
        url="https://exemple.fr/c",
    )

    matched = await apply_hybrid_word(db_session, today_paris(), None)
    assert matched is False  # déjà posé → skip

    await db_session.refresh(puzzle)
    assert puzzle.word == "MANDAT"  # inchangé


@pytest.mark.asyncio
async def test_hybrid_skips_when_game_already_started(db_session, test_source):
    puzzle = await _make_puzzle(db_session, word="MANDAT")
    await _make_content(
        db_session,
        test_source.id,
        title="Le climat se réchauffe",
        description="x",
        url="https://exemple.fr/c",
    )
    db_session.add(
        GrilleGameState(
            user_id=uuid4(),
            puzzle_date=today_paris(),
            guesses=[],
            status=STATUS_IN_PROGRESS,
            attempts=0,
        )
    )
    await db_session.commit()

    matched = await apply_hybrid_word(db_session, today_paris(), None)
    assert matched is False  # partie en cours → ne touche pas le mot

    await db_session.refresh(puzzle)
    assert puzzle.word == "MANDAT"
    assert puzzle.hybrid_word_source is None


@pytest.mark.asyncio
async def test_hybrid_no_candidate_leaves_seed(db_session, test_source):
    puzzle = await _make_puzzle(db_session, word="MANDAT")
    await _make_content(
        db_session,
        test_source.id,
        title="Texte sans aucun terme du pool ici",
        description="ni la non plus voila",
        url="https://exemple.fr/none",
    )

    matched = await apply_hybrid_word(db_session, today_paris(), None)
    assert matched is False

    await db_session.refresh(puzzle)
    assert puzzle.word == "MANDAT"  # fallback seed intact
    assert puzzle.hybrid_word_source is None
