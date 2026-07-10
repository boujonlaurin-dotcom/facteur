"""Sélecteur hybride du « mot du jour » — extrait de l'actu réelle du jour.

Inverse la logique de l'ancien `grille_matcher` : au lieu de partir d'un mot
seedé et de *chercher* un article qui colle, on **extrait** le mot du jour du
corpus d'actu du jour (titres + descriptions des ~300 articles de la tournée),
filtré par le pool de qualité éditoriale (`grille_quality_pool`) et le
dictionnaire de validité (`grille_dictionary`). On fige l'occurrence exacte
(quel article, titre ou description, surface à surligner) pour le reveal.

Pur scoring + une requête corpus en miroir de
`DigestGenerationJob._get_global_candidates`. Aucun join runtime côté Grille :
le résultat est figé en colonnes sur `GrillePuzzle`.
"""

import asyncio
import re
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from functools import lru_cache
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content
from app.models.grille_puzzle import GrillePuzzle
from app.services.editorial.schemas import EditorialGlobalContext
from app.services.grille_dictionary import WORD_LENGTH, is_valid_word
from app.services.grille_matcher import _excerpt, _norm
from app.services.grille_quality_pool import get_quality_pool
from app.services.grille_text import normalize_word
from app.services.recommendation.filter_presets import apply_ad_filter

logger = structlog.get_logger()

# Fenêtre de récence du corpus (miroir de `hours_lookback` du digest).
_CORPUS_HOURS = 48
# Borne du corpus (top-N par récence) — assez large pour trouver un mot la
# plupart des jours sans scanner toute la base.
_CORPUS_LIMIT = 300
# Score minimal pour retenir un mot (au moins un match sous-chaîne).
_MIN_SCORE = 1
# Demi-largeur d'une fenêtre de description centrée sur la surface matchée.
_WINDOW_HALF = 110

FIELD_TITLE = "title"
FIELD_DESCRIPTION = "description"
WORD_SOURCE_HYBRID = "hybrid"

# Runs de lettres (unicode, accents inclus ; chiffres / ponctuation exclus).
_TOKEN_RE = re.compile(r"[^\W\d_]+", re.UNICODE)


@dataclass(frozen=True)
class GrilleSelection:
    """Mot du jour extrait de l'actu + son occurrence exacte (à figer)."""

    word: str
    content_id: UUID
    title: str
    source_name: str | None
    url: str | None
    excerpt: str | None
    field: str  # FIELD_TITLE | FIELD_DESCRIPTION
    snippet: str  # texte exact à afficher (titre complet ou fenêtre de desc)
    match_surface: str  # surface exacte à surligner dans le snippet


def _scan_field(
    text: str | None, pool_index: dict[str, str]
) -> dict[str, tuple[str, bool]]:
    """Mots du pool présents dans `text` (1 seule passe de tokenisation).

    Renvoie `word_MAJ -> (surface_originale, mot_entier)`. Un token strictement
    égal à un mot du pool est un **mot-entier** (« climat ») ; un token qui
    *contient* un mot est une **flexion** (« climatique »). Un mot-entier
    l'emporte toujours sur une flexion, et la première occurrence gagne sinon.
    La surface est le token original (accents/casse d'origine) → le mobile la
    re-localise dans le snippet.
    """
    hits: dict[str, tuple[str, bool]] = {}
    if not text:
        return hits
    for tok in _TOKEN_RE.findall(text):
        tok_norm = _norm(tok)
        word = pool_index.get(tok_norm)
        if word is not None:  # mot-entier (lookup O(1))
            prev = hits.get(word)
            if prev is None or not prev[1]:
                hits[word] = (tok, True)
            continue
        # Flexion : un mot du pool est strictement inclus dans le token.
        # Les mots du pool font tous WORD_LENGTH lettres → un token plus court
        # ne peut pas les contenir.
        if len(tok_norm) <= WORD_LENGTH:
            continue
        for word_l, word in pool_index.items():
            if word_l in tok_norm:
                hits.setdefault(word, (tok, False))
    return hits


def _window(text: str, surface: str) -> str:
    """Fenêtre ~220 car de `text` centrée sur `surface` (sinon extrait simple)."""
    idx = text.find(surface)
    if idx < 0:
        return _excerpt(text) or text
    start = max(0, idx - _WINDOW_HALF)
    end = min(len(text), idx + len(surface) + _WINDOW_HALF)
    fragment = text[start:end].strip()
    prefix = "…" if start > 0 else ""
    suffix = "…" if end < len(text) else ""
    return f"{prefix}{fragment}{suffix}"


def _build_cluster_index(
    editorial_ctx: EditorialGlobalContext | None,
) -> dict[str, int]:
    """content_id (str) → rang du cluster qui le contient (plus petit = mieux)."""
    index: dict[str, int] = {}
    if editorial_ctx is None:
        return index
    for rank, cluster in enumerate(editorial_ctx.cluster_data):
        for cid in cluster.get("content_ids", []):
            index.setdefault(str(cid), rank)
    return index


def _subject_label_words(
    editorial_ctx: EditorialGlobalContext | None,
) -> set[str]:
    """Mots (MAJUSCULES sans accent) présents dans les labels des sujets.

    Même forme canonique que le pool / `GrilleSelection.word` → comparaison
    directe `word in label_words`.
    """
    words: set[str] = set()
    if editorial_ctx is None:
        return words
    for subject in editorial_ctx.subjects:
        for tok in _TOKEN_RE.findall(subject.label):
            words.add(normalize_word(tok))
    return words


async def _corpus(session: AsyncSession) -> list[Content]:
    """Articles récents (≤48h, hors pubs), top-N par récence — miroir digest."""
    cutoff = datetime.now(UTC) - timedelta(hours=_CORPUS_HOURS)
    stmt = (
        apply_ad_filter(select(Content).options(selectinload(Content.source)))
        .where(Content.published_at >= cutoff)
        .order_by(Content.published_at.desc())
        .limit(_CORPUS_LIMIT)
    )
    result = await session.execute(stmt)
    return list(result.scalars().all())


# Fenêtre d'anti-répétition : un mot du jour ne doit pas réapparaître avant
# ~2 mois (la table `grille_puzzles` est l'historique, pas de table dédiée).
RECENT_WINDOW_DAYS = 60


async def recent_words(
    session: AsyncSession, target_date: date, days: int = RECENT_WINDOW_DAYS
) -> set[str]:
    """Mots des puzzles des `days` derniers jours (normalisés) — anti-répétition.

    Couvre `[target_date - days, target_date - 1]` : on n'inclut pas le jour
    courant (le puzzle du jour est en cours de sélection).
    """
    rows = await session.scalars(
        select(GrillePuzzle.word).where(
            GrillePuzzle.puzzle_date >= target_date - timedelta(days=days),
            GrillePuzzle.puzzle_date < target_date,
        )
    )
    return {normalize_word(word) for word in rows if word}


@dataclass
class _Candidate:
    """Accumulateur de score d'un mot du pool sur le corpus."""

    word: str
    score: int = 0
    cluster_rank: int = 1_000_000
    # Meilleure occurrence (priorité : titre-entier > titre-flexion > desc).
    occ_priority: int = 99
    content: Content | None = None
    field: str = FIELD_TITLE
    surface: str = ""


@lru_cache(maxsize=1)
def _pool_index() -> dict[str, str]:
    """Index `mot_minuscule → mot_MAJ` du pool (calculé une seule fois)."""
    return {word.lower(): word for word in get_quality_pool()}


def _select_from_corpus(
    corpus: list[Content],
    cluster_index: dict[str, int],
    label_words: set[str],
    exclude: set[str] | str | None,
) -> GrilleSelection | None:
    """Cœur pur : extrait le meilleur mot du pool présent dans le corpus."""
    if exclude is None:
        excluded: set[str] = set()
    elif isinstance(exclude, str):
        excluded = {exclude}
    else:
        excluded = exclude
    pool_index = _pool_index()
    candidates: dict[str, _Candidate] = {}

    for content in corpus:
        crank = cluster_index.get(str(content.id), 1_000_000)
        title_hits = _scan_field(content.title, pool_index)
        desc_hits = _scan_field(content.description, pool_index)

        for word in title_hits.keys() | desc_hits.keys():
            if word in excluded or not is_valid_word(word):
                continue

            title_hit = title_hits.get(word)
            desc_hit = desc_hits.get(word)

            art_score = 0
            if title_hit:
                art_score += 3 if title_hit[1] else 1
            if desc_hit:
                art_score += 2 if desc_hit[1] else 1

            cand = candidates.setdefault(word, _Candidate(word=word))
            cand.score += art_score
            cand.cluster_rank = min(cand.cluster_rank, crank)

            # Occurrence à figer : titre-entier(0) > titre-flexion(1) > desc(2).
            if title_hit:
                priority = 0 if title_hit[1] else 1
                surface, field = title_hit[0], FIELD_TITLE
            else:
                priority = 2
                surface, field = desc_hit[0], FIELD_DESCRIPTION
            if priority < cand.occ_priority:
                cand.occ_priority = priority
                cand.content = content
                cand.field = field
                cand.surface = surface

    if not candidates:
        return None

    # Bonus éditorial +2 (top cluster ou mot dans un label de sujet).
    for cand in candidates.values():
        if cand.cluster_rank < 1_000_000 or cand.word in label_words:
            cand.score += 2

    # Tie-break déterministe : score desc, rang cluster asc, alpha.
    best = min(
        (c for c in candidates.values() if c.score >= _MIN_SCORE and c.content),
        key=lambda c: (-c.score, c.cluster_rank, c.word),
        default=None,
    )
    if best is None or best.content is None:
        return None

    content = best.content
    if best.field == FIELD_TITLE:
        snippet = (content.title or "").strip()
    else:
        snippet = _window(content.description or "", best.surface)

    return GrilleSelection(
        word=best.word,
        content_id=content.id,
        title=content.title or "",
        source_name=content.source.name if content.source else None,
        url=content.url,
        excerpt=_excerpt(content.description),
        field=best.field,
        snippet=snippet,
        match_surface=best.surface,
    )


async def select_daily_word(
    session: AsyncSession,
    target_date: date,
    editorial_ctx: EditorialGlobalContext | None,
) -> GrilleSelection | None:
    """Choisit le mot du jour dans l'actu du jour, ou None (→ fallback seed).

    Lecture seule : ne touche pas le puzzle (c'est `apply_hybrid_word` qui fige).
    """
    corpus, recent = await asyncio.gather(
        _corpus(session),
        recent_words(session, target_date),
    )
    if not corpus:
        logger.info("grille_selector_empty_corpus", target_date=str(target_date))
        return None

    selection = _select_from_corpus(
        corpus,
        _build_cluster_index(editorial_ctx),
        _subject_label_words(editorial_ctx),
        recent,
    )
    if selection is None:
        logger.info("grille_selector_no_candidate", target_date=str(target_date))
    else:
        logger.info(
            "grille_selector_picked",
            target_date=str(target_date),
            word=selection.word,
            field=selection.field,
            content_id=str(selection.content_id),
        )
    return selection
