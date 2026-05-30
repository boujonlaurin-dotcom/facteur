"""Seed des puzzles de « La Grille du jour » (Story 24.1).

Upsert idempotent par `puzzle_date` depuis `app/data/grille_puzzles_seed.json`.
Les dates affichées (`date_affichee`, `date_court`, `cancel`) sont calculées
depuis `date` pour éviter toute erreur de jour de semaine.

Invariant vérifié au seed : chaque `word` ∈ dictionnaire (grille_words_fr.txt).

Usage :
  cd packages/api && source venv/bin/activate
  python -m scripts.seed_grille_puzzles
"""

import asyncio
import json
from datetime import date
from pathlib import Path

from sqlalchemy import select

from app.database import async_session_maker
from app.models.grille_puzzle import GrillePuzzle
from app.services.grille_dictionary import is_valid_word

_SEED_PATH = (
    Path(__file__).resolve().parent.parent / "app" / "data" / "grille_puzzles_seed.json"
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
    data = json.loads(_SEED_PATH.read_text(encoding="utf-8"))
    return data["indice_default"], data["puzzles"]


async def main() -> None:
    indice_default, puzzles = load_seed()

    # Garde-fou : tous les mots du jour doivent être dans le dictionnaire.
    invalid = [p["word"] for p in puzzles if not is_valid_word(p["word"])]
    if invalid:
        raise SystemExit(
            f"Mots du jour absents du dictionnaire (grille_words_fr.txt) : {invalid}"
        )

    created = 0
    updated = 0
    async with async_session_maker() as db:
        for p in puzzles:
            puzzle_date = date.fromisoformat(p["date"])
            existing = await db.scalar(
                select(GrillePuzzle).where(
                    GrillePuzzle.puzzle_date == puzzle_date
                )
            )
            fields = dict(
                word=p["word"],
                length=p.get("longueur", 6),
                max_attempts=p.get("essaisMax", 6),
                indice=p.get("indice", indice_default),
                theme=p["theme"],
                pourquoi=p["pourquoi"],
                numero=p["numero"],
                date_affichee=format_date_affichee(puzzle_date),
                date_court=format_date_court(puzzle_date),
                cancel=format_cancel(puzzle_date),
            )
            if existing is None:
                db.add(GrillePuzzle(puzzle_date=puzzle_date, **fields))
                created += 1
                print(f"  + {p['date']} {p['numero']} {p['word']}")
            else:
                for key, value in fields.items():
                    setattr(existing, key, value)
                updated += 1
                print(f"  ~ {p['date']} {p['numero']} {p['word']} (maj)")
        await db.commit()

    print(f"\nDone. {created} créés, {updated} mis à jour.")


if __name__ == "__main__":
    asyncio.run(main())
