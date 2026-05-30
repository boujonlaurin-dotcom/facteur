"""Tests endpoint + service de La Grille du jour (Story 24.1)."""

from datetime import date, timedelta
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.grille_game_state import (
    STATUS_FAILED,
    STATUS_IN_PROGRESS,
    STATUS_SOLVED,
    GrilleGameState,
)
from app.models.grille_puzzle import GrillePuzzle
from app.services.grille_service import (
    GameAlreadyFinished,
    GameNotFinished,
    GrilleService,
    PuzzleNotFound,
)
from app.utils.time import today_paris


def _override_db(session):
    async def _fake_db():
        yield session

    return _fake_db


def _override_user(user_id: str):
    async def _fake_user():
        return user_id

    return _fake_user


async def _make_puzzle(db, *, word="CLIMAT", max_attempts=6, on_date=None):
    puzzle = GrillePuzzle(
        puzzle_date=on_date or today_paris(),
        word=word,
        length=len(word),
        max_attempts=max_attempts,
        indice="Le mot qui a traversé ta tournée d'aujourd'hui",
        theme="Environnement · Société",
        pourquoi="Un mot, trois angles : prendre du recul.",
        numero="N°143",
        date_affichee="Test 30 mai",
        date_court="Test 30 mai",
        cancel="30·05·26",
    )
    db.add(puzzle)
    await db.commit()
    return puzzle


async def _add_game(db, user_id, *, status, attempts, on_date=None, guesses=None):
    game = GrilleGameState(
        user_id=user_id,
        puzzle_date=on_date or today_paris(),
        guesses=guesses or [],
        status=status,
        attempts=attempts,
    )
    db.add(game)
    await db.commit()
    return game


# ----- GET /today (HTTP) ----------------------------------------------------


@pytest.mark.asyncio
async def test_today_creates_game_and_hides_word(db_session):
    await _make_puzzle(db_session)
    user_id = uuid4()
    app.dependency_overrides[get_current_user_id] = _override_user(str(user_id))
    app.dependency_overrides[get_db] = _override_db(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get("/api/grille/today")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    body = resp.json()
    assert body["statut"] == "in_progress"
    assert body["premiereLettre"] == "C"
    assert body["nbEssais"] == 0
    assert body["essais"] == []
    # Secret : le mot et le pourquoi ne fuitent pas en cours de partie.
    assert body["mot"] is None
    assert body["pourquoi"] is None
    assert "prochainMotDansSec" in body


@pytest.mark.asyncio
async def test_today_404_when_no_puzzle(db_session):
    user_id = uuid4()
    app.dependency_overrides[get_current_user_id] = _override_user(str(user_id))
    app.dependency_overrides[get_db] = _override_db(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get("/api/grille/today")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 404


# ----- validation (service) -------------------------------------------------


@pytest.mark.asyncio
async def test_guess_wrong_length_not_consumed(db_session):
    await _make_puzzle(db_session)
    service = GrilleService(db_session)
    user_id = str(uuid4())

    result = await service.submit_guess(user_id, "ABC")
    assert result.valide is False
    assert result.raison == "longueur"

    today = await service.get_today(user_id)
    assert today.nbEssais == 0  # essai non consommé


@pytest.mark.asyncio
async def test_guess_out_of_dictionary_not_consumed(db_session):
    await _make_puzzle(db_session)
    service = GrilleService(db_session)
    user_id = str(uuid4())

    result = await service.submit_guess(user_id, "ZZZZZZ")
    assert result.valide is False
    assert result.raison == "hors_dictionnaire"

    today = await service.get_today(user_id)
    assert today.nbEssais == 0


@pytest.mark.asyncio
async def test_guess_valid_progresses(db_session):
    await _make_puzzle(db_session)
    service = GrilleService(db_session)
    user_id = str(uuid4())

    result = await service.submit_guess(user_id, "placer")  # casse/normalisation
    assert result.valide is True
    assert result.statut == "in_progress"
    assert result.nbEssais == 1
    assert result.etats[1] == "place"  # L bien placé
    assert result.mot is None  # toujours secret


@pytest.mark.asyncio
async def test_solve_reveals_word(db_session):
    await _make_puzzle(db_session)
    service = GrilleService(db_session)
    user_id = str(uuid4())

    result = await service.submit_guess(user_id, "CLIMAT")
    assert result.valide is True
    assert result.statut == STATUS_SOLVED
    assert result.etats == ["place"] * 6
    assert result.mot == "CLIMAT"  # révélé en fin de partie
    assert result.pourquoi is not None


@pytest.mark.asyncio
async def test_today_restores_guesses(db_session):
    await _make_puzzle(db_session)
    service = GrilleService(db_session)
    user_id = str(uuid4())

    await service.submit_guess(user_id, "PLACER")
    await service.submit_guess(user_id, "CALMER")

    today = await service.get_today(user_id)
    assert today.nbEssais == 2
    assert [e.mot for e in today.essais] == ["PLACER", "CALMER"]
    assert len(today.essais[0].etats) == 6


@pytest.mark.asyncio
async def test_replay_forbidden_after_solved(db_session):
    await _make_puzzle(db_session)
    service = GrilleService(db_session)
    user_id = str(uuid4())

    await service.submit_guess(user_id, "CLIMAT")  # solved
    with pytest.raises(GameAlreadyFinished):
        await service.submit_guess(user_id, "PLACER")


@pytest.mark.asyncio
async def test_exhaust_attempts_marks_failed(db_session):
    await _make_puzzle(db_session, max_attempts=2)
    service = GrilleService(db_session)
    user_id = str(uuid4())

    await service.submit_guess(user_id, "PLACER")
    last = await service.submit_guess(user_id, "CALMER")
    assert last.statut == STATUS_FAILED
    assert last.mot == "CLIMAT"  # révélé sur échec

    today = await service.get_today(user_id)
    assert today.statut == STATUS_FAILED
    assert today.nbEssais == 2


# ----- leaderboard ----------------------------------------------------------


@pytest.mark.asyncio
async def test_leaderboard_requires_finished_game(db_session):
    await _make_puzzle(db_session)
    service = GrilleService(db_session)
    user_id = str(uuid4())

    # Aucune partie -> 409 métier
    with pytest.raises(GameNotFinished):
        await service.get_leaderboard(user_id)

    # Partie en cours -> 409 métier
    await service.submit_guess(user_id, "PLACER")
    with pytest.raises(GameNotFinished):
        await service.get_leaderboard(user_id)


@pytest.mark.asyncio
async def test_leaderboard_distribution_percentile_and_podium(db_session):
    await _make_puzzle(db_session)

    # Champ de jeu : 4 solveurs (2,3,3,4 essais) + 1 échec.
    me = uuid4()  # 2 essais → meilleur
    await _add_game(db_session, me, status=STATUS_SOLVED, attempts=2)
    await _add_game(db_session, uuid4(), status=STATUS_SOLVED, attempts=3)
    await _add_game(db_session, uuid4(), status=STATUS_SOLVED, attempts=3)
    slow = uuid4()
    await _add_game(db_session, slow, status=STATUS_SOLVED, attempts=4)
    await _add_game(db_session, uuid4(), status=STATUS_FAILED, attempts=6)

    service = GrilleService(db_session)
    board = await service.get_leaderboard(str(me))

    assert board.joueurs == 5
    assert board.monScore == 2
    # distribution ~ 100 %
    assert abs(sum(d.pct for d in board.distribution) - 100) <= 2
    # "X" présent en dernier
    assert board.distribution[-1].score == "X"
    # podium anonymisé : 3 lignes, le joueur marqué "Toi"/moi, pas de nom
    assert len(board.quartier) == 3
    assert any(q.moi and q.initiales == "Toi" for q in board.quartier)
    assert board.quartier[0].rang == 1

    # percentile monotone : le meilleur (2 essais) <= le plus lent (4 essais)
    board_slow = await service.get_leaderboard(str(slow))
    assert board.percentile <= board_slow.percentile


# ----- streak dérivé --------------------------------------------------------


@pytest.mark.asyncio
async def test_streak_consecutive_days(db_session):
    service = GrilleService(db_session)
    user_id = uuid4()
    today = today_paris()
    for offset in range(3):  # aujourd'hui, hier, avant-hier
        await _add_game(
            db_session,
            user_id,
            status=STATUS_SOLVED,
            attempts=3,
            on_date=today - timedelta(days=offset),
        )
    assert await service._compute_streak(str(user_id)) == 3


@pytest.mark.asyncio
async def test_streak_resets_on_gap(db_session):
    service = GrilleService(db_session)
    user_id = uuid4()
    today = today_paris()
    # aujourd'hui + hier joués, puis un trou (J-3 joué mais pas J-2)
    for offset in (0, 1, 3):
        await _add_game(
            db_session,
            user_id,
            status=STATUS_IN_PROGRESS,
            attempts=1,
            on_date=today - timedelta(days=offset),
        )
    assert await service._compute_streak(str(user_id)) == 2


@pytest.mark.asyncio
async def test_streak_zero_when_never_played(db_session):
    service = GrilleService(db_session)
    assert await service._compute_streak(str(uuid4())) == 0
