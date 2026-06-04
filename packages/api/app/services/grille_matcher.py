"""Auto-matching « mot du jour » → article réel de la tournée.

À la génération du digest, on cherche dans le contexte éditorial global le sujet
dont l'actu colle le mieux au mot du jour (et son thème), puis on **fige** un
snapshot (titre + extrait + url + source) sur le `GrillePuzzle` du jour. Le
reveal affiche alors un vrai article ; sans match, il retombe sur `pourquoi`.

Best-effort et idempotent : appelé depuis le job digest dans un try/except qui
n'altère jamais le digest. Le runtime de la Grille ne fait aucun join — il lit
uniquement les colonnes figées.
"""

import unicodedata
from datetime import date, datetime

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.grille_puzzle import GrillePuzzle
from app.services.editorial.schemas import EditorialGlobalContext, EditorialSubject
from app.services.recommendation.helpers.keyword_match import matches_word_boundary

logger = structlog.get_logger()

# Longueur max de l'extrait figé (description tronquée proprement).
_EXCERPT_MAX = 240

# Score minimal pour accrocher un article (au moins un match flexion/sous-chaîne).
_MIN_SCORE = 1


def _norm(text: str) -> str:
    """Minuscules sans accent (miroir Python de la normalisation de matching)."""
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).lower()


def subject_match_score(word: str, theme: str, subject: EditorialSubject) -> int:
    """Force du match d'un sujet éditorial au mot du jour (0 = pas de match).

    On compare le mot (et, en bonus, le thème) au label du sujet, à son thème et
    au titre de son actu. Un match **mot-entier** (`\\b…\\b`) vaut plus qu'une
    sous-chaîne — cette dernière tolère les flexions (CLIMAT ⊂ « climatique »).
    """
    word_l = _norm(word)
    if not word_l:
        return 0

    haystacks: list[str] = [_norm(subject.label)]
    if subject.theme:
        haystacks.append(_norm(subject.theme))
    if subject.actu_article is not None:
        haystacks.append(_norm(subject.actu_article.title))

    score = 0
    for hay in haystacks:
        if matches_word_boundary(word_l, hay):
            score += 3
        elif word_l in hay:
            # Flexion / dérivé (climat → climatique) : match plus faible.
            score += 2

    # Bonus léger si le thème du sujet recoupe le thème éditorial du puzzle
    # (« Environnement · Société » → tokens partagés).
    theme_tokens = {t for t in _norm(theme).replace("·", " ").split() if len(t) > 3}
    subj_theme = _norm(subject.theme or "")
    if theme_tokens and any(t in subj_theme for t in theme_tokens):
        score += 1

    return score


def _best_subject(
    word: str, theme: str, subjects: list[EditorialSubject]
) -> EditorialSubject | None:
    """Sujet au meilleur score (>= seuil) portant une actu ; tie-break par rang."""
    best: EditorialSubject | None = None
    best_score = 0
    for subject in sorted(subjects, key=lambda s: s.rank):
        if subject.actu_article is None:
            continue
        score = subject_match_score(word, theme, subject)
        if score > best_score:
            best_score = score
            best = subject
    return best if best_score >= _MIN_SCORE else None


def _excerpt(description: str | None) -> str | None:
    """Tronque la description en un extrait propre (sans couper un mot)."""
    if not description:
        return None
    text = description.strip()
    if len(text) <= _EXCERPT_MAX:
        return text
    cut = text[:_EXCERPT_MAX].rsplit(" ", 1)[0].rstrip(",;:.")
    return f"{cut}…"


async def match_grille_featured_article(
    session: AsyncSession,
    target_date: date,
    editorial_ctx: EditorialGlobalContext | None,
) -> bool:
    """Fige l'article matché sur le puzzle du jour. Retourne True si un match.

    Idempotent : ne fait rien si le puzzle a déjà un `featured_content_id`. Ne
    commit pas (le caller gère la transaction) — fait juste un flush.
    """
    if editorial_ctx is None or not editorial_ctx.subjects:
        return False

    puzzle = await session.scalar(
        select(GrillePuzzle).where(GrillePuzzle.puzzle_date == target_date)
    )
    if puzzle is None:
        return False
    if puzzle.featured_content_id is not None:
        logger.info("grille_featured_already_set", target_date=str(target_date))
        return False

    subject = _best_subject(puzzle.word, puzzle.theme, editorial_ctx.subjects)
    if subject is None or subject.actu_article is None:
        logger.info(
            "grille_featured_no_match",
            target_date=str(target_date),
            word=puzzle.word,
        )
        return False

    actu = subject.actu_article
    content = await session.get(Content, actu.content_id)

    puzzle.featured_content_id = actu.content_id
    puzzle.featured_title = actu.title
    puzzle.featured_excerpt = _excerpt(content.description if content else None)
    puzzle.featured_url = content.url if content else None
    puzzle.featured_source = actu.source_name
    puzzle.featured_matched_at = datetime.utcnow()
    await session.flush()

    logger.info(
        "grille_featured_matched",
        target_date=str(target_date),
        word=puzzle.word,
        content_id=str(actu.content_id),
        source=actu.source_name,
    )
    return True
