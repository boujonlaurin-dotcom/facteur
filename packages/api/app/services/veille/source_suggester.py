"""Suggestion de sources pour une veille — liste unique rankée par pertinence.

Le LLM produit une seule liste de sources francophones (médias établis pertinents
au topic + niches indé), notées par `relevance_score`. Post-traitement :
- detect HTTP en parallèle (`RSSParser.detect`, sémaphore polite) ;
- ingest DB séquentiel + dédoublonne par domaine racine (keep highest score) ;
- flag `is_already_followed` calculé contre les `UserSource` du user ;
- trie par `relevance_score` desc.

Sans `MISTRAL_API_KEY`, fallback déterministe sur 5 sources curées du même thème.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from urllib.parse import urlparse
from uuid import UUID, uuid4

import sentry_sdk
import structlog
from pydantic import BaseModel, Field, ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import apply_session_timeouts
from app.models.enums import SourceType
from app.models.source import Source, UserSource
from app.schemas.veille import VeilleThemeSlug
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.rss_parser import DetectedFeed, RSSParser
from app.services.veille.topic_suggester import purpose_line

logger = structlog.get_logger()

# Doit rester aligné avec `VeilleThemeSlug` et la contrainte SQL
# `ck_source_theme_valid` : un INSERT avec un theme hors liste empoisonne
# la session (PendingRollbackError sur tout commit ultérieur).
_ALLOWED_SOURCE_THEMES = frozenset(VeilleThemeSlug.__args__)

# Cap par candidat (HTTP detect via RSSParser teste plusieurs variants
# suffix avec httpx 7s + curl-cffi 10s). Sans cap, un seul URL qui hang
# gèle le pipeline complet pour les 7-11 candidats restants.
_HYDRATE_TIMEOUT_S = 8.0

# Cap global sur l'appel LLM (Mistral). Sur timeout → fallback curé.
_LLM_TIMEOUT_S = 20.0

# Phase 1 (HTTP detect) parallèle, borne polie côté sites cibles. Aligné
# sur le sémaphore interne de RSSParser stage 4 suffix probe (4) pour
# éviter d'amplifier la pression aval.
_DETECT_CONCURRENCY = 4


@dataclass(frozen=True)
class SourceSuggestionItem:
    source_id: UUID
    name: str
    url: str
    feed_url: str
    theme: str
    why: str | None
    is_already_followed: bool
    relevance_score: float | None


@dataclass(frozen=True)
class SourceSuggestions:
    sources: list[SourceSuggestionItem]


class _LLMSourceCandidate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    url: str = Field(min_length=4, max_length=2048)
    why: str | None = Field(default=None, max_length=300)
    relevance_score: float = Field(ge=0.0, le=1.0)


_SOURCES_SYSTEM_PROMPT = """Tu es un expert en curation média francophone.

Tâche : pour un thème + des topics + un usage + un brief éditorial donnés, propose 8 à 12 sources francophones (médias établis, médias indé, newsletters, blogs spécialisés, podcasts) classées par pertinence pour CES topics et CE brief — pas seulement pour le thème générique.

Format JSON strict :
{"sources": [
  {"name": "<nom>", "url": "<url racine>", "why": "<1 phrase max>", "relevance_score": 0.0-1.0},
  ...
]}

Contraintes :
- 8 à 12 sources max.
- relevance_score (0.0–1.0) : pondéré par adéquation aux topics ET au brief — pas seulement au thème. 1.0 = source la plus pertinente possible, 0.5 = pertinent mais générique, < 0.5 = à éviter.
- Mélange : médias établis (Le Monde, Mediapart, etc.) SI pertinents pour le topic, et niches (médias indé, newsletters, blogs spé, podcasts).
- Diversifie les angles éditoriaux et les formats.
- url : page d'accueil ou URL racine, pas un article spécifique.
- why : 1 phrase max qui explique pourquoi cette source est pertinente pour CE topic / CE brief.
- Pas de doublon de domaine.
- Réponds UNIQUEMENT avec le JSON."""


def _root_domain(url: str) -> str:
    """Domaine racine normalisé (lowercase, sans `www.`) pour dédup."""
    host = (urlparse(url).hostname or url).lower()
    return host[4:] if host.startswith("www.") else host


class SourceSuggester:
    """Suggère une liste unique de sources rankées pour une veille."""

    def __init__(
        self,
        llm: EditorialLLMClient | None = None,
        rss_parser: RSSParser | None = None,
    ) -> None:
        self._llm = llm or EditorialLLMClient()
        self._rss_parser = rss_parser or RSSParser()

    async def suggest_sources(
        self,
        session: AsyncSession,
        user_id: UUID,
        theme_id: str,
        topic_labels: list[str],
        excluded_source_ids: list[UUID] | None = None,
        purpose: str | None = None,
        purpose_other: str | None = None,
        editorial_brief: str | None = None,
    ) -> SourceSuggestions:
        """Renvoie une liste unique de sources triée par `relevance_score` desc.

        Args:
            session: AsyncSession ouverte (caller-managed).
            user_id: UUID du user (pour calculer `is_already_followed`).
            theme_id: slug du thème.
            topic_labels: labels des topics retenus (pondère le LLM).
            excluded_source_ids: sources à exclure (déjà rattachées, refusées).
            purpose: slug de l'usage souhaité (V1, optionnel).
            purpose_other: free-text quand `purpose='autre'`.
            editorial_brief: brief libre décrivant la veille idéale.

        Returns:
            `SourceSuggestions(sources=...)` triée par pertinence.
        """
        excluded = set(excluded_source_ids or [])

        # `safe_async_session` émet `SET LOCAL` au démarrage, ce qui ouvre
        # une tx implicite. Sans rollback, l'await LLM dépasse
        # `idle_in_transaction_session_timeout` (10 s) et Postgres tue la
        # connexion. Les SET LOCAL sont ré-appliqués via
        # `apply_session_timeouts` après le LLM.
        await session.rollback()

        candidates: list[_LLMSourceCandidate] = []
        if self._llm.is_ready:
            user_message = (
                f"Thème : {theme_id}\n"
                f"Topics retenus : {', '.join(topic_labels) if topic_labels else '(aucun)'}\n"
                f"Usage souhaité : {purpose_line(purpose, purpose_other)}\n"
                f"Brief éditorial : {editorial_brief or '(aucun)'}\n\n"
                f"Propose 8 à 12 sources rankées par pertinence pour ces topics et ce brief."
            )
            try:
                raw = await asyncio.wait_for(
                    self._llm.chat_json(
                        system=_SOURCES_SYSTEM_PROMPT,
                        user_message=user_message,
                        model="mistral-large-latest",
                        temperature=0.4,
                        max_tokens=1500,
                    ),
                    timeout=_LLM_TIMEOUT_S,
                )
                candidates = self._parse_candidates(raw)
            except TimeoutError:
                logger.warning(
                    "source_suggester.llm_timeout",
                    timeout_s=_LLM_TIMEOUT_S,
                    theme_id=theme_id,
                )
                # Fallback curé — pas de sentry capture (timeout LLM = condition
                # business connue, pas un bug applicatif).

        # Re-pousse SET LOCAL sur la nouvelle tx que la prochaine query
        # va ouvrir : sans ça, le filet anti-zombie côté Postgres est
        # perdu pour la suite (boucle d'ingestion + commit final).
        await apply_session_timeouts(session)

        followed_ids = await self._followed_source_ids(session, user_id)

        if not candidates:
            sources = await self._fallback(session, theme_id, excluded, followed_ids)
            return SourceSuggestions(sources=sources)

        # Phase 1 — detect HTTP en parallèle (cap `_DETECT_CONCURRENCY` pour
        # rester poli vers les sites cibles). RSSParser fait les requêtes
        # via un `httpx.AsyncClient` partagé qui supporte la concurrence ;
        # les sémaphores internes (stage 4 suffix probe) bornent la fan-out
        # par hostname. La session DB n'est PAS touchée ici : SQLAlchemy
        # AsyncSession n'est pas safe pour des opérations concurrentes,
        # donc le SELECT existing + INSERT restent en Phase 2 séquentielle.
        detect_sem = asyncio.Semaphore(_DETECT_CONCURRENCY)
        detect_results = await asyncio.gather(
            *(self._detect_candidate(detect_sem, cand) for cand in candidates),
        )

        # Phase 2 — ingest DB séquentiel + dédup par domaine (keep highest
        # score). Chaque candidat reste isolé dans un SAVEPOINT : sans ça,
        # une `IntegrityError` au flush() (feed_url unique, name overflow…)
        # empoisonne la session pour tous les candidats suivants
        # (PendingRollbackError au commit final).
        by_domain: dict[str, tuple[Source, _LLMSourceCandidate]] = {}
        for result in detect_results:
            if result is None:
                continue
            cand, detected = result
            try:
                async with session.begin_nested():
                    hydrated = await self._persist_detected(
                        session, cand, detected, theme_id
                    )
            except Exception as exc:
                # Sentry capture obligatoire : le `logger.warning` seul ne
                # remonte pas la stack ; sans ça on perd la cause racine
                # des flush() qui foirent et on ne peut pas itérer dessus.
                sentry_sdk.capture_exception(exc)
                logger.warning(
                    "source_suggester.persist_failed",
                    name=cand.name,
                    url=cand.url,
                    error_class=type(exc).__name__,
                    error=str(exc),
                )
                continue
            if hydrated.id in excluded:
                continue
            domain = _root_domain(hydrated.url)
            existing = by_domain.get(domain)
            if existing is None or cand.relevance_score > existing[1].relevance_score:
                by_domain[domain] = (hydrated, cand)

        items = [
            SourceSuggestionItem(
                source_id=src.id,
                name=src.name,
                url=src.url,
                feed_url=src.feed_url,
                theme=src.theme,
                why=cand.why,
                is_already_followed=src.id in followed_ids,
                relevance_score=cand.relevance_score,
            )
            for src, cand in by_domain.values()
        ]
        items.sort(key=lambda i: i.relevance_score or 0.0, reverse=True)
        return SourceSuggestions(sources=items)

    async def _followed_source_ids(
        self,
        session: AsyncSession,
        user_id: UUID,
    ) -> set[UUID]:
        stmt = select(UserSource.source_id).where(UserSource.user_id == user_id)
        result = await session.execute(stmt)
        return set(result.scalars().all())

    async def _detect_candidate(
        self,
        sem: asyncio.Semaphore,
        cand: _LLMSourceCandidate,
    ) -> tuple[_LLMSourceCandidate, DetectedFeed] | None:
        """Phase 1 — detect HTTP par candidat, sans toucher la session DB.

        Wrap `_HYDRATE_TIMEOUT_S` pour cap par candidat ; les exceptions
        sont avalées (logguées + capture Sentry pour les non-Value/Timeout)
        de sorte que `asyncio.gather` ne propage pas une seule défaillance
        et tue les autres candidats en cours.
        """
        async with sem:
            try:
                detected = await asyncio.wait_for(
                    self._rss_parser.detect(cand.url),
                    timeout=_HYDRATE_TIMEOUT_S,
                )
            except TimeoutError:
                logger.warning(
                    "source_suggester.candidate_timeout",
                    name=cand.name,
                    url=cand.url,
                    timeout_s=_HYDRATE_TIMEOUT_S,
                )
                return None
            except ValueError as exc:
                # ValueError = échec de détection RSS (404, 403, no feed,
                # DNS fail). Cas business attendu, pas une stack à
                # remonter à Sentry — un warning structuré suffit.
                logger.warning(
                    "source_suggester.detect_failed",
                    name=cand.name,
                    url=cand.url,
                    error=str(exc),
                )
                return None
            except Exception as exc:
                # Inattendu — capture obligatoire pour pouvoir itérer.
                sentry_sdk.capture_exception(exc)
                logger.warning(
                    "source_suggester.detect_unexpected",
                    name=cand.name,
                    url=cand.url,
                    error_class=type(exc).__name__,
                    error=str(exc),
                )
                return None
        return cand, detected

    async def _persist_detected(
        self,
        session: AsyncSession,
        cand: _LLMSourceCandidate,
        detected: DetectedFeed,
        theme_id: str,
    ) -> Source:
        """Phase 2 — persiste une source détectée en DB (idempotent par feed_url)."""
        existing_stmt = select(Source).where(Source.feed_url == detected.feed_url)
        existing = (await session.execute(existing_stmt)).scalars().first()
        if existing:
            return existing

        if theme_id not in _ALLOWED_SOURCE_THEMES:
            # Sans ce garde-fou, l'INSERT viole `ck_source_theme_valid`
            # et le rollback empoisonne toute la requête HTTP en cours.
            raise ValueError(
                f"Invalid theme_id '{theme_id}' — must be one of "
                f"{sorted(_ALLOWED_SOURCE_THEMES)}"
            )

        # `RSSParser.detect()` retourne un feed_type dans
        # {"rss","atom","youtube","podcast","reddit"}. SourceType n'a pas
        # de valeur "rss"/"atom" → mapper vers ARTICLE comme dans
        # `SourceService.detect_source`.
        feed_type = detected.feed_type
        source_type_str = "article" if feed_type in ("rss", "atom") else feed_type
        try:
            source_type = SourceType(source_type_str)
        except ValueError:
            source_type = SourceType.ARTICLE

        new_source = Source(
            id=uuid4(),
            name=cand.name or detected.title,
            url=cand.url,
            feed_url=detected.feed_url,
            type=source_type,
            theme=theme_id,
            description=detected.description,
            logo_url=detected.logo_url,
            is_curated=False,
            is_active=True,
        )
        session.add(new_source)
        await session.flush()
        logger.info(
            "source_suggester.source_ingested",
            source_id=str(new_source.id),
            name=new_source.name,
            theme=theme_id,
        )
        return new_source

    async def _fallback(
        self,
        session: AsyncSession,
        theme_id: str,
        excluded: set[UUID],
        followed_ids: set[UUID],
    ) -> list[SourceSuggestionItem]:
        """Sans LLM : sources curées du thème, plus celles déjà suivies."""
        stmt = select(Source).where(
            Source.is_active.is_(True),
            Source.theme == theme_id,
            Source.is_curated.is_(True),
        )
        if excluded:
            stmt = stmt.where(Source.id.notin_(excluded))
        result = await session.execute(stmt)
        rows = list(result.scalars().all())
        return [
            SourceSuggestionItem(
                source_id=s.id,
                name=s.name,
                url=s.url,
                feed_url=s.feed_url,
                theme=s.theme,
                why=None,
                is_already_followed=s.id in followed_ids,
                relevance_score=None,
            )
            for s in rows[:8]
        ]

    @staticmethod
    def _parse_candidates(raw: dict | list | None) -> list[_LLMSourceCandidate]:
        if not isinstance(raw, dict):
            return []
        items = raw.get("sources")
        if not isinstance(items, list):
            return []
        out: list[_LLMSourceCandidate] = []
        for it in items:
            try:
                out.append(_LLMSourceCandidate.model_validate(it))
            except ValidationError as exc:
                logger.debug("source_suggester.skip_invalid", error=str(exc))
        return out


_source_suggester: SourceSuggester | None = None


def get_source_suggester() -> SourceSuggester:
    global _source_suggester
    if _source_suggester is None:
        _source_suggester = SourceSuggester()
    return _source_suggester
