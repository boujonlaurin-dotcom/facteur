"""Suggestion de sources pour une veille — liste unique rankée par pertinence.

Le LLM produit une seule liste de sources francophones (médias établis pertinents
au topic + niches indé), notées par `relevance_score`. Post-traitement :
- hydrate / ingère via `SourceService.detect_source` ;
- dédoublonne par domaine racine (keep highest score) ;
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

from app.models.enums import SourceType
from app.models.source import Source, UserSource
from app.schemas.veille import VeilleThemeSlug
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.source_service import SourceService
from app.services.veille.topic_suggester import purpose_line

logger = structlog.get_logger()

# Doit rester aligné avec `VeilleThemeSlug` et la contrainte SQL
# `ck_source_theme_valid` : un INSERT avec un theme hors liste empoisonne
# la session (PendingRollbackError sur tout commit ultérieur).
_ALLOWED_SOURCE_THEMES = frozenset(VeilleThemeSlug.__args__)

# Cap par candidat (HTTP detect + flush DB). Au-delà, on skip pour ne pas
# bloquer le pipeline sur un domaine qui hang (cf. bug-veille-suggestions
# -sources-pending-rollback : binge.audio/feed/ retry 22× = 3min wall).
_HYDRATE_TIMEOUT_S = 8.0

# Cap global sur l'appel LLM (Mistral). Sur timeout → fallback curé.
_LLM_TIMEOUT_S = 20.0


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

    def __init__(self, llm: EditorialLLMClient | None = None) -> None:
        self._llm = llm or EditorialLLMClient()

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
        followed_ids = await self._followed_source_ids(session, user_id)

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

        if not candidates:
            sources = await self._fallback(session, theme_id, excluded, followed_ids)
            return SourceSuggestions(sources=sources)

        # Hydrate / ingère + dédup par domaine (keep highest score).
        # Chaque candidat est isolé dans un SAVEPOINT + cappé à 8 s :
        # - savepoint évite qu'une `IntegrityError` (feed_url unique, name >
        #   200 chars) empoisonne la session pour les candidats suivants ;
        # - timeout évite qu'un mauvais URL fasse hang RSSParser (cf. bug
        #   binge.audio/feed/ retry 22× = 3 min wall).
        by_domain: dict[str, tuple[Source, _LLMSourceCandidate]] = {}
        source_service = SourceService(session)
        for cand in candidates:
            try:
                async with session.begin_nested():
                    hydrated = await asyncio.wait_for(
                        self._hydrate_or_ingest(
                            session, source_service, cand, theme_id
                        ),
                        timeout=_HYDRATE_TIMEOUT_S,
                    )
            except TimeoutError:
                logger.warning(
                    "source_suggester.candidate_timeout",
                    name=cand.name,
                    url=cand.url,
                    timeout_s=_HYDRATE_TIMEOUT_S,
                )
                continue
            except Exception as exc:
                # Sentry capture obligatoire : sans ça on perd la cause
                # racine des `flush()` qui foirent (ck_source_theme_valid,
                # feed_url unique, name overflow…) et on ne peut pas
                # itérer sur les vraies failures.
                sentry_sdk.capture_exception(exc)
                logger.warning(
                    "source_suggester.hydrate_failed",
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

    async def _hydrate_or_ingest(
        self,
        session: AsyncSession,
        source_service: SourceService,
        cand: _LLMSourceCandidate,
        theme_id: str,
    ) -> Source:
        """Ingest la source à la volée si absente du catalogue."""
        detected = await source_service.detect_source(cand.url)

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

        try:
            source_type = SourceType(detected.detected_type)
        except ValueError:
            source_type = SourceType.ARTICLE

        new_source = Source(
            id=uuid4(),
            name=cand.name or detected.name,
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
