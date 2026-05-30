"""Service de « La Grille du jour » (Story 24.1).

Orchestre puzzle / partie / validation / leaderboard / streak. Validation
100 % serveur : le mot du jour n'est jamais exposé tant que la partie n'est pas
terminée. Le service ne gère pas la transaction (commit assuré par `get_db`).
"""

import hashlib
from collections import Counter
from datetime import date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.grille_game_state import (
    STATUS_FAILED,
    STATUS_IN_PROGRESS,
    STATUS_SOLVED,
    GrilleGameState,
)
from app.models.grille_puzzle import GrillePuzzle
from app.schemas.grille import (
    GrilleDistributionItem,
    GrilleEssai,
    GrilleGuessResponse,
    GrilleLeaderboardResponse,
    GrilleQuartierItem,
    GrilleTodayResponse,
)
from app.services.grille_dictionary import is_valid_word
from app.services.grille_text import compute_tiles, normalize_word
from app.utils.time import now_paris, today_paris
from app.workers.scheduler import DIGEST_CRON_HOUR_PARIS, DIGEST_CRON_MINUTE_PARIS

# Sel statique du hash d'anonymisation du podium (combiné au puzzle_date du
# jour → initiales non nominatives, non corrélables d'un jour à l'autre).
_PODIUM_SALT = "facteur-grille-podium-v1"


def _game_score(game: GrilleGameState) -> int | str:
    """Score d'une partie : nb d'essais si résolue, sinon "X" (échec)."""
    return game.attempts if game.status == STATUS_SOLVED else "X"


class PuzzleNotFound(Exception):
    """Aucun puzzle seedé pour la date demandée."""


class GameAlreadyFinished(Exception):
    """La partie du jour est déjà terminée (pas de rejeu)."""


class GameNotFinished(Exception):
    """Le classement n'est disponible qu'une fois la partie terminée."""


def next_rollover_seconds(now: datetime) -> int:
    """Secondes jusqu'au prochain basculement (07:30 Paris), >= 0.

    Aligné sur le cron du digest (`DIGEST_CRON_HOUR_PARIS:MINUTE`) — le mot du
    jour colle au jour de la Tournée.
    """
    target = now.replace(
        hour=DIGEST_CRON_HOUR_PARIS,
        minute=DIGEST_CRON_MINUTE_PARIS,
        second=0,
        microsecond=0,
    )
    if now >= target:
        target = target + timedelta(days=1)
    return int((target - now).total_seconds())


class GrilleService:
    """Logique métier de La Grille du jour."""

    def __init__(self, db: AsyncSession):
        self.db = db

    # ----- accès puzzle / partie -------------------------------------------

    async def _get_puzzle(self, puzzle_date: date) -> GrillePuzzle | None:
        return await self.db.scalar(
            select(GrillePuzzle).where(GrillePuzzle.puzzle_date == puzzle_date)
        )

    async def _get_game(
        self, user_id: str, puzzle_date: date
    ) -> GrilleGameState | None:
        return await self.db.scalar(
            select(GrilleGameState).where(
                GrilleGameState.user_id == user_id,
                GrilleGameState.puzzle_date == puzzle_date,
            )
        )

    async def _get_or_create_game(
        self, user_id: str, puzzle_date: date
    ) -> GrilleGameState:
        game = await self._get_game(user_id, puzzle_date)
        if game is None:
            game = GrilleGameState(
                user_id=user_id,
                puzzle_date=puzzle_date,
                guesses=[],
                status=STATUS_IN_PROGRESS,
                attempts=0,
            )
            self.db.add(game)
            await self.db.flush()
        return game

    # ----- GET /today -------------------------------------------------------

    async def get_today(self, user_id: str) -> GrilleTodayResponse:
        puzzle_date = today_paris()
        puzzle = await self._get_puzzle(puzzle_date)
        if puzzle is None:
            raise PuzzleNotFound(puzzle_date.isoformat())

        game = await self._get_or_create_game(user_id, puzzle_date)
        finished = game.status != STATUS_IN_PROGRESS

        essais = [
            GrilleEssai(mot=g, etats=compute_tiles(puzzle.word, g))
            for g in game.guesses
        ]

        return GrilleTodayResponse(
            date=puzzle_date.isoformat(),
            dateAffichee=puzzle.date_affichee,
            dateCourt=puzzle.date_court,
            numero=puzzle.numero,
            longueur=puzzle.length,
            essaisMax=puzzle.max_attempts,
            premiereLettre=puzzle.word[0],
            indice=puzzle.indice,
            theme=puzzle.theme,
            statut=game.status,
            essais=essais,
            nbEssais=game.attempts,
            mot=puzzle.word if finished else None,
            pourquoi=puzzle.pourquoi if finished else None,
            streak=await self._compute_streak(user_id),
            prochainMotDansSec=next_rollover_seconds(now_paris()),
        )

    # ----- POST /today/guess -----------------------------------------------

    async def submit_guess(self, user_id: str, raw_mot: str) -> GrilleGuessResponse:
        puzzle_date = today_paris()
        puzzle = await self._get_puzzle(puzzle_date)
        if puzzle is None:
            raise PuzzleNotFound(puzzle_date.isoformat())

        game = await self._get_or_create_game(user_id, puzzle_date)
        if game.status != STATUS_IN_PROGRESS:
            raise GameAlreadyFinished()

        mot = normalize_word(raw_mot)

        # Refus — essai NON consommé.
        if len(mot) != puzzle.length:
            return GrilleGuessResponse(valide=False, raison="longueur")
        if not is_valid_word(mot):
            return GrilleGuessResponse(valide=False, raison="hors_dictionnaire")

        # Essai accepté.
        game.guesses = [*game.guesses, mot]
        game.attempts += 1
        etats = compute_tiles(puzzle.word, mot)

        if mot == puzzle.word:
            game.status = STATUS_SOLVED
        elif game.attempts >= puzzle.max_attempts:
            game.status = STATUS_FAILED

        finished = game.status != STATUS_IN_PROGRESS
        if finished:
            game.finished_at = datetime.utcnow()

        await self.db.flush()

        return GrilleGuessResponse(
            valide=True,
            etats=etats,
            statut=game.status,
            nbEssais=game.attempts,
            mot=puzzle.word if finished else None,
            pourquoi=puzzle.pourquoi if finished else None,
        )

    # ----- GET /today/leaderboard ------------------------------------------

    async def get_leaderboard(self, user_id: str) -> GrilleLeaderboardResponse:
        puzzle_date = today_paris()
        puzzle = await self._get_puzzle(puzzle_date)
        if puzzle is None:
            raise PuzzleNotFound(puzzle_date.isoformat())

        my_game = await self._get_game(user_id, puzzle_date)
        if my_game is None or my_game.status == STATUS_IN_PROGRESS:
            raise GameNotFinished()

        finished = (
            await self.db.scalars(
                select(GrilleGameState).where(
                    GrilleGameState.puzzle_date == puzzle_date,
                    GrilleGameState.status != STATUS_IN_PROGRESS,
                )
            )
        ).all()

        joueurs = len(finished)
        max_attempts = puzzle.max_attempts

        # Classement (clé croissante = meilleur) : solved trié par essais,
        # failed tout au fond.
        def rank_key(g: GrilleGameState) -> tuple[int, int, str]:
            if g.status == STATUS_SOLVED:
                return (0, g.attempts, str(g.user_id))
            return (1, max_attempts + 1, str(g.user_id))

        ordered = sorted(finished, key=rank_key)
        my_index = next(
            i for i, g in enumerate(ordered) if str(g.user_id) == str(user_id)
        )

        # Distribution (% par nb d'essais 1..max + "X") — un seul passage.
        counts = Counter(_game_score(g) for g in finished)
        scores: list[int | str] = [*range(1, max_attempts + 1), "X"]
        distribution = [
            GrilleDistributionItem(score=s, pct=self._pct(counts[s], joueurs))
            for s in scores
        ]

        # Percentile : part des joueurs strictement meilleurs (moins = mieux).
        my_key = rank_key(my_game)
        better = sum(1 for g in finished if rank_key(g) < my_key)
        percentile = max(1, round(100 * better / joueurs)) if joueurs else 1

        my_score = _game_score(my_game)

        return GrilleLeaderboardResponse(
            percentile=percentile,
            joueurs=joueurs,
            monScore=my_score,
            distribution=distribution,
            quartier=self._build_podium(ordered, my_index, user_id, puzzle_date),
            streak=await self._compute_streak(user_id),
        )

    @staticmethod
    def _pct(count: int, total: int) -> int:
        return round(100 * count / total) if total else 0

    def _build_podium(
        self,
        ordered: list[GrilleGameState],
        my_index: int,
        user_id: str,
        puzzle_date: date,
    ) -> list[GrilleQuartierItem]:
        """Podium anonymisé de 3 ; garantit la présence du joueur (« Toi »)."""

        def item(idx: int) -> GrilleQuartierItem:
            g = ordered[idx]
            is_me = str(g.user_id) == str(user_id)
            return GrilleQuartierItem(
                initiales="Toi" if is_me else self._initials(g.user_id, puzzle_date),
                score=_game_score(g),
                rang=idx + 1,
                moi=is_me,
            )

        top_indices = list(range(min(3, len(ordered))))
        # Si le joueur n'est pas dans le top 3, on l'insère à la place du 3e.
        if my_index not in top_indices and top_indices:
            top_indices[-1] = my_index
        return [item(i) for i in top_indices]

    @staticmethod
    def _initials(user_id, puzzle_date: date) -> str:
        """2 initiales non nominatives dérivées d'un hash quotidien salé."""
        digest = hashlib.sha256(
            f"{_PODIUM_SALT}:{puzzle_date.isoformat()}:{user_id}".encode()
        ).digest()
        a = chr(ord("A") + digest[0] % 26)
        b = chr(ord("A") + digest[1] % 26)
        return f"{a}·{b}"

    # ----- streak dérivé ----------------------------------------------------

    async def _compute_streak(self, user_id: str) -> int:
        """Jours consécutifs joués en remontant depuis aujourd'hui (Paris).

        Dérivé des `puzzle_date` distincts du joueur — ne touche jamais
        `UserStreak`/`streak_service` (zone digest). Un « aujourd'hui » non
        encore joué ne casse pas une série acquise la veille.
        """
        rows = (
            await self.db.scalars(
                select(GrilleGameState.puzzle_date)
                .where(GrilleGameState.user_id == user_id)
                .distinct()
            )
        ).all()
        played = set(rows)
        if not played:
            return 0

        today = today_paris()
        cursor = today if today in played else today - timedelta(days=1)
        streak = 0
        while cursor in played:
            streak += 1
            cursor -= timedelta(days=1)
        return streak
