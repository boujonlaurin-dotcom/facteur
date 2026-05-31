"""Seed idempotent des puzzles de « La Grille du jour ».

Source de vérité : `app/data/grille_puzzles_seed.json` (committé). Upsert par
`puzzle_date`. Les dates affichées (`date_affichee`, `date_court`, `cancel`)
sont calculées depuis `date` pour éviter toute erreur de jour de semaine.

Appelé à deux endroits :
- au démarrage de l'app (`main.lifespan`) → garantit qu'une table vide ne
  peut plus passer en prod silencieusement (cf. docs/bugs/bug-grille-du-jour-crash.md) ;
- par `scripts/seed_grille_puzzles.py` (exécution manuelle / one-off).

Invariant vérifié au seed : chaque `word` ∈ dictionnaire (grille_words_fr.txt).
"""

import json
from datetime import date
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.grille_puzzle import GrillePuzzle
from app.services.grille_dictionary import is_valid_word

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


async def seed_puzzles(db: AsyncSession) -> tuple[int, int]:
    """Upsert idempotent des puzzles dans `db`. Retourne `(créés, mis_à_jour)`.

    Ne commit pas : laisse la transaction au caller (parité avec `GrilleService`,
    où `get_db` assure le commit). Lève [SeedInvalidWord] si un mot du jour est
    hors dictionnaire — fail-fast plutôt que de servir un puzzle injouable.
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
        existing = await db.scalar(
            select(GrillePuzzle).where(GrillePuzzle.puzzle_date == puzzle_date)
        )
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
        if existing is None:
            db.add(GrillePuzzle(puzzle_date=puzzle_date, **fields))
            created += 1
        else:
            for key, value in fields.items():
                setattr(existing, key, value)
            updated += 1

    await db.flush()
    return created, updated
