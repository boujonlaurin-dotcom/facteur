"""Orchestration « mot du jour » → sélection hybride depuis l'actu réelle.

À la génération du digest, `apply_hybrid_word` extrait le mot du jour du corpus
d'actu (cf. `grille_selector`) et **fige** sur le `GrillePuzzle` du jour le mot,
l'article source (titre/extrait/url/source) et l'occurrence exacte (où le mot se
cachait). Sans candidat, le puzzle garde son mot seedé + `pourquoi`.

Best-effort et idempotent : appelé depuis le job digest dans un try/except qui
n'altère jamais le digest. Le runtime de la Grille ne fait aucun join — il lit
uniquement les colonnes figées.
"""

import unicodedata
from datetime import date, datetime

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.grille_game_state import GrilleGameState
from app.models.grille_puzzle import GrillePuzzle
from app.services.editorial.schemas import EditorialGlobalContext

logger = structlog.get_logger()

# Longueur max de l'extrait figé (description tronquée proprement).
_EXCERPT_MAX = 240


def _norm(text: str) -> str:
    """Minuscules sans accent (miroir Python de la normalisation de matching)."""
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).lower()


def _excerpt(description: str | None) -> str | None:
    """Tronque la description en un extrait propre (sans couper un mot)."""
    if not description:
        return None
    text = description.strip()
    if len(text) <= _EXCERPT_MAX:
        return text
    cut = text[:_EXCERPT_MAX].rsplit(" ", 1)[0].rstrip(",;:.")
    return f"{cut}…"


async def apply_hybrid_word(
    session: AsyncSession,
    target_date: date,
    editorial_ctx: EditorialGlobalContext | None,
) -> bool:
    """Sélection hybride : remplace le mot seedé par un mot extrait de l'actu.

    Retourne True si un mot a été posé depuis l'actu (sinon le puzzle garde son
    mot seedé + `pourquoi`). Ne commit pas (le caller gère la transaction).

    Gardes :
      - **Idempotence** : no-op si `hybrid_word_source == "hybrid"` déjà posé.
      - **Anti-overwrite mid-day** (edge case critique) : si ≥1 partie existe
        déjà pour `target_date`, on ne touche à **rien** — changer `word`
        re-colorierait les tuiles d'un joueur en cours (`compute_tiles` lit
        `puzzle.word` live), et l'occurrence hybride serait incohérente avec le
        mot seedé conservé. En pratique le digest tourne au rollover (07:30) →
        aucune partie n'existe encore, donc l'overwrite gagne la course.
    """
    from app.services.grille_selector import (
        WORD_SOURCE_HYBRID,
        select_daily_word,
    )

    puzzle = await session.scalar(
        select(GrillePuzzle).where(GrillePuzzle.puzzle_date == target_date)
    )
    if puzzle is None:
        return False
    if puzzle.hybrid_word_source == WORD_SOURCE_HYBRID:
        logger.info("grille_hybrid_already_set", target_date=str(target_date))
        return False

    game_exists = await session.scalar(
        select(GrilleGameState.id)
        .where(GrilleGameState.puzzle_date == target_date)
        .limit(1)
    )
    if game_exists is not None:
        logger.warning(
            "grille_hybrid_skipped_game_started",
            target_date=str(target_date),
        )
        return False

    selection = await select_daily_word(session, target_date, editorial_ctx)
    if selection is None:
        logger.info("grille_hybrid_no_candidate", target_date=str(target_date))
        return False

    puzzle.word = selection.word
    puzzle.featured_content_id = selection.content_id
    puzzle.featured_title = selection.title
    puzzle.featured_excerpt = selection.excerpt
    puzzle.featured_url = selection.url
    puzzle.featured_source = selection.source_name
    puzzle.featured_matched_at = datetime.utcnow()
    puzzle.hybrid_field = selection.field
    puzzle.hybrid_snippet = selection.snippet
    puzzle.hybrid_match = selection.match_surface
    puzzle.hybrid_word_source = WORD_SOURCE_HYBRID
    await session.flush()

    logger.info(
        "grille_hybrid_applied",
        target_date=str(target_date),
        word=selection.word,
        field=selection.field,
        content_id=str(selection.content_id),
    )
    return True
