"""Tests de l'auto-matching « mot du jour » → article réel (Part D)."""

from datetime import datetime
from uuid import uuid4

import pytest

from app.models.content import Content
from app.models.enums import ContentType
from app.models.grille_puzzle import GrillePuzzle
from app.services.editorial.schemas import (
    EditorialGlobalContext,
    EditorialSubject,
    MatchedActuArticle,
)
from app.services.grille_matcher import (
    _best_subject,
    match_grille_featured_article,
    subject_match_score,
)
from app.utils.time import today_paris


def _actu(title, *, content_id=None, source_name="Le Monde"):
    return MatchedActuArticle(
        content_id=content_id or uuid4(),
        title=title,
        source_name=source_name,
        source_id=uuid4(),
        is_user_source=True,
        published_at=datetime.utcnow(),
    )


def _subject(rank, label, *, theme=None, actu=None):
    return EditorialSubject(
        rank=rank,
        topic_id=f"t{rank}",
        label=label,
        selection_reason="parce que",
        theme=theme,
        actu_article=actu,
    )


def _ctx(subjects):
    return EditorialGlobalContext(
        subjects=subjects, cluster_data=[], generated_at=datetime.utcnow()
    )


# ----- scoring pur ----------------------------------------------------------


def test_score_word_boundary_beats_flexion():
    boundary = _subject(1, "Climat", actu=_actu("Accord mondial sur le climat"))
    flexion = _subject(2, "Énergie", actu=_actu("La transition climatique s'accélère"))
    s_boundary = subject_match_score("CLIMAT", "Environnement", boundary)
    s_flexion = subject_match_score("CLIMAT", "Environnement", flexion)
    assert s_boundary > s_flexion > 0


def test_score_zero_when_unrelated():
    subj = _subject(1, "Football", actu=_actu("La finale de la coupe approche"))
    assert subject_match_score("CLIMAT", "Diplomatie", subj) == 0


def test_best_subject_picks_matching_lowest_rank():
    subjects = [
        _subject(1, "Sport", actu=_actu("Match de gala")),
        _subject(2, "Climat", actu=_actu("Le climat au cœur du sommet")),
    ]
    best = _best_subject("CLIMAT", "Environnement", subjects)
    assert best is not None
    assert best.rank == 2


def test_best_subject_none_when_no_match():
    subjects = [_subject(1, "Sport", actu=_actu("Match de gala"))]
    assert _best_subject("CLIMAT", "Diplomatie", subjects) is None


def test_best_subject_skips_subjects_without_actu():
    subjects = [_subject(1, "Climat", actu=None)]
    assert _best_subject("CLIMAT", "Environnement", subjects) is None


# ----- match_grille_featured_article (DB) -----------------------------------


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
async def test_match_sets_snapshot(db_session, test_source):
    puzzle = await _make_puzzle(db_session)
    content = await _make_content(
        db_session,
        test_source.id,
        title="Accord mondial sur le climat",
        description="Les délégations ont trouvé un terrain d'entente historique.",
        url="https://exemple.fr/climat",
    )
    ctx = _ctx(
        [
            _subject(1, "Sport", actu=_actu("Match de gala")),
            _subject(
                2,
                "Climat",
                theme="Environnement",
                actu=_actu(
                    "Accord mondial sur le climat",
                    content_id=content.id,
                    source_name="Le Monde",
                ),
            ),
        ]
    )

    matched = await match_grille_featured_article(db_session, today_paris(), ctx)
    assert matched is True

    await db_session.refresh(puzzle)
    assert puzzle.featured_content_id == content.id
    assert puzzle.featured_title == "Accord mondial sur le climat"
    assert puzzle.featured_excerpt is not None
    assert puzzle.featured_url == "https://exemple.fr/climat"
    assert puzzle.featured_source == "Le Monde"
    assert puzzle.featured_matched_at is not None


@pytest.mark.asyncio
async def test_match_no_result_leaves_null(db_session):
    puzzle = await _make_puzzle(db_session)
    ctx = _ctx([_subject(1, "Sport", actu=_actu("Match de gala"))])

    matched = await match_grille_featured_article(db_session, today_paris(), ctx)
    assert matched is False

    await db_session.refresh(puzzle)
    assert puzzle.featured_content_id is None
    assert puzzle.featured_title is None


@pytest.mark.asyncio
async def test_match_is_idempotent(db_session, test_source):
    content = await _make_content(
        db_session,
        test_source.id,
        title="Climat",
        description="desc",
        url="https://exemple.fr/c",
    )
    puzzle = await _make_puzzle(db_session)
    puzzle.featured_content_id = content.id
    puzzle.featured_title = "Déjà figé"
    await db_session.commit()

    ctx = _ctx(
        [_subject(1, "Climat", actu=_actu("Le climat", content_id=content.id))]
    )
    matched = await match_grille_featured_article(db_session, today_paris(), ctx)
    assert matched is False  # déjà set → skip

    await db_session.refresh(puzzle)
    assert puzzle.featured_title == "Déjà figé"  # inchangé


@pytest.mark.asyncio
async def test_match_none_ctx_is_noop(db_session):
    puzzle = await _make_puzzle(db_session)
    matched = await match_grille_featured_article(db_session, today_paris(), None)
    assert matched is False
    await db_session.refresh(puzzle)
    assert puzzle.featured_content_id is None
