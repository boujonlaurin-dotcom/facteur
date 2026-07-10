"""Seed et création de secours des puzzles de « La Grille du jour ».

Le calendrier historique vient de `app/data/grille_puzzles_seed.json`. Les
jours absents sont créés à la volée depuis le pool éditorial embarqué. Toutes
les insertions sont idempotentes par `puzzle_date` et une ligne existante n'est
jamais réécrite : un puzzle publié, hybridé ou déjà joué reste immuable.

Appelé à deux endroits :
- au démarrage de l'app (`main.lifespan`) → garantit qu'une table vide ne
  peut plus passer en prod silencieusement (cf. docs/bugs/bug-grille-du-jour-crash.md) ;
- par `scripts/seed_grille_puzzles.py` (exécution manuelle / one-off).

Invariant vérifié au seed : chaque `word` ∈ dictionnaire (grille_words_fr.txt).
"""

import json
from datetime import date
from hashlib import sha256
from pathlib import Path

import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.grille_puzzle import GrillePuzzle
from app.services.grille_dictionary import is_valid_word
from app.services.grille_quality_pool import get_quality_pool
from app.services.grille_selector import recent_words
from app.services.grille_text import normalize_word

logger = structlog.get_logger()

_SEED_PATH = (
    Path(__file__).resolve().parent.parent / "data" / "grille_puzzles_seed.json"
)

_WEEKDAYS_LONG = [
    "lundi",
    "mardi",
    "mercredi",
    "jeudi",
    "vendredi",
    "samedi",
    "dimanche",
]
_WEEKDAYS_SHORT = ["Lun.", "Mar.", "Mer.", "Jeu.", "Ven.", "Sam.", "Dim."]
_MONTHS = [
    "janvier",
    "février",
    "mars",
    "avril",
    "mai",
    "juin",
    "juillet",
    "août",
    "septembre",
    "octobre",
    "novembre",
    "décembre",
]

_FIRST_EDITION_DATE = date(2026, 5, 30)
_FIRST_EDITION_NUMBER = 143
_FALLBACK_INDICE = "Un mot de six lettres choisi dans les repères de Facteur"
_FALLBACK_THEME = "Repères · Culture générale"
_FALLBACK_POURQUOI = (
    "Ce mot fait partie des repères éditoriaux de Facteur. "
    "Une pause quotidienne pour jouer avec les mots et garder l'esprit ouvert."
)


class SeedInvalidWord(Exception):
    """Un `word` du seed est absent du dictionnaire (grille_words_fr.txt)."""


def _day_fr(d: date) -> str:
    """« 30 » ou « 1er » (convention française pour le 1er du mois)."""
    return "1er" if d.day == 1 else str(d.day)


def format_date_affichee(d: date) -> str:
    """« Samedi 30 mai » (masthead)."""
    weekday = _WEEKDAYS_LONG[d.weekday()].capitalize()
    return f"{weekday} {_day_fr(d)} {_MONTHS[d.month - 1]}"


def format_date_court(d: date) -> str:
    """« Sam. 30 mai » (pied de partage)."""
    return f"{_WEEKDAYS_SHORT[d.weekday()]} {_day_fr(d)} {_MONTHS[d.month - 1]}"


def format_cancel(d: date) -> str:
    """« 30·05·26 » (cachet d'oblitération)."""
    return f"{d.day:02d}·{d.month:02d}·{d.year % 100:02d}"


def load_seed() -> tuple[str, list[dict]]:
    """Charge l'indice par défaut + la liste des puzzles depuis le JSON seedé."""
    data = json.loads(_SEED_PATH.read_text(encoding="utf-8"))
    return data["indice_default"], data["puzzles"]


def _edition_number(target_date: date) -> str:
    number = _FIRST_EDITION_NUMBER + (target_date - _FIRST_EDITION_DATE).days
    return f"N°{number}"


def _fallback_word(target_date: date, recent: set[str] | None = None) -> str:
    """Choisit un mot stable pour une date donnée dans le pool éditorial.

    Déterministe par date (hash SHA256), mais saute les mots déjà sortis
    récemment (`recent`, mots normalisés des ~2 derniers mois) pour éviter les
    répétitions. On itère une séquence salée `sha256("<date>:<i>")` et on retient
    le premier mot hors historique ; si tout le pool est récent (improbable), on
    retombe sur le 1er tirage (comportement historique).
    """
    words = sorted(get_quality_pool())
    if not words:
        raise SeedInvalidWord("Le pool éditorial de la Grille est vide")
    recent = recent or set()
    first: str | None = None
    for i in range(len(words)):
        seed = f"{target_date.isoformat()}:{i}".encode("ascii")
        digest = sha256(seed).digest()
        word = words[int.from_bytes(digest[:8], "big") % len(words)]
        if first is None:
            first = word
        if normalize_word(word) not in recent:
            return word
    return first  # tout le pool est récent → repli déterministe


def _fallback_fields(
    target_date: date, recent: set[str] | None = None
) -> dict[str, object]:
    word = _fallback_word(target_date, recent)
    if not is_valid_word(word):
        raise SeedInvalidWord(
            f"Mot fallback absent du dictionnaire (grille_words_fr.txt) : {word}"
        )
    return {
        "word": word,
        "length": len(word),
        "max_attempts": 6,
        "indice": _FALLBACK_INDICE,
        "theme": _FALLBACK_THEME,
        "pourquoi": _FALLBACK_POURQUOI,
        "numero": _edition_number(target_date),
        "date_affichee": format_date_affichee(target_date),
        "date_court": format_date_court(target_date),
        "cancel": format_cancel(target_date),
    }


async def ensure_daily_puzzle(session: AsyncSession, target_date: date) -> GrillePuzzle:
    """Garantit atomiquement l'existence du puzzle de `target_date`."""
    recent = await recent_words(session, target_date)
    stmt = (
        insert(GrillePuzzle)
        .values(puzzle_date=target_date, **_fallback_fields(target_date, recent))
        .on_conflict_do_nothing(index_elements=["puzzle_date"])
        .returning(GrillePuzzle.id)
    )
    created_id = await session.scalar(stmt)
    puzzle = await session.scalar(
        select(GrillePuzzle).where(GrillePuzzle.puzzle_date == target_date)
    )
    if puzzle is None:
        raise RuntimeError(f"Puzzle introuvable après insertion : {target_date}")
    if created_id is not None:
        logger.info(
            "grille_fallback_created",
            target_date=str(target_date),
            word=puzzle.word,
            numero=puzzle.numero,
        )
    return puzzle


async def seed_puzzles(db: AsyncSession) -> tuple[int, int]:
    """Crée les puzzles historiques absents. Retourne `(créés, mis_à_jour)`.

    Ne commit pas : laisse la transaction au caller (parité avec `GrilleService`,
    où `get_db` assure le commit). Lève [SeedInvalidWord] si un mot du jour est
    hors dictionnaire. Une ligne existante n'est jamais modifiée.
    """
    indice_default, puzzles = load_seed()

    invalid = [p["word"] for p in puzzles if not is_valid_word(p["word"])]
    if invalid:
        raise SeedInvalidWord(
            f"Mots du jour absents du dictionnaire (grille_words_fr.txt) : {invalid}"
        )

    created = 0
    updated = 0
    for p in puzzles:
        puzzle_date = date.fromisoformat(p["date"])
        fields = {
            "word": p["word"],
            "length": p.get("longueur", 6),
            "max_attempts": p.get("essaisMax", 6),
            "indice": p.get("indice", indice_default),
            "theme": p["theme"],
            "pourquoi": p["pourquoi"],
            "numero": p["numero"],
            "date_affichee": format_date_affichee(puzzle_date),
            "date_court": format_date_court(puzzle_date),
            "cancel": format_cancel(puzzle_date),
        }
        stmt = (
            insert(GrillePuzzle)
            .values(puzzle_date=puzzle_date, **fields)
            .on_conflict_do_nothing(index_elements=["puzzle_date"])
            .returning(GrillePuzzle.id)
        )
        if await db.scalar(stmt) is not None:
            created += 1

    await db.flush()
    return created, updated
