"""Suggestion de sources pour une veille : `followed` + `niche` (avec ingestion).

- `followed` : sources suivies par l'user, filtrées par thème.
- `niche`    : sources proposées par LLM, hydratées via `SourceService.detect_source` ;
  ingérées à la volée si absentes du catalogue (`is_curated=False`, sans `UserSource`).

Pool DB : la session est passée en paramètre — pas de réouverture interne.
Sans `MISTRAL_API_KEY`, fallback déterministe sur sources curées du même thème.
"""

from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID, uuid4

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


@dataclass(frozen=True)
class SourceSuggestionItem:
    source_id: UUID
    name: str
    url: str
    feed_url: str
    theme: str
    why: str | None


@dataclass(frozen=True)
class SourceSuggestions:
    followed: list[SourceSuggestionItem]
    niche: list[SourceSuggestionItem]


class _LLMNicheCandidate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    url: str = Field(min_length=4, max_length=2048)
    why: str | None = Field(default=None, max_length=300)


_NICHE_SYSTEM_PROMPT = """Tu es un expert en curation média francophone. Tu connais les sources de niche, indépendantes, et spécialisées sur des thématiques pointues.

Tâche : pour un thème + des topics donnés, propose 6 à 8 sources de niche pertinentes (médias indé, newsletters, blogs spécialisés, podcasts, magazines).

Format JSON strict :
{"sources": [{"name": "<nom>", "url": "<url racine>", "why": "<1 phrase max>"}, ...]}

Contraintes :
- 6 à 8 sources max.
- url : URL racine ou page d'accueil (pas un article spécifique).
- why : pourquoi cette source est intéressante pour ce thème (1 phrase).
- Diversifie : médias indé, perspectives variées, formats variés.
- Évite les médias mainstream (Le Monde, Le Figaro, etc.).
- Réponds UNIQUEMENT avec le JSON."""


class SourceSuggester:
    """Suggère des sources `followed` + `niche` pour une veille."""

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
        """Renvoie sources `followed` + `niche` pour la veille en cours.

        Args:
            session: AsyncSession ouverte (caller-managed).
            user_id: UUID du user (pour requêter `user_sources`).
            theme_id: slug du thème.
            topic_labels: labels des topics retenus (pour aider le LLM).
            excluded_source_ids: sources à exclure (déjà rattachées, refusées).
            purpose: slug de l'usage souhaité (V1, optionnel).
            purpose_other: free-text quand `purpose='autre'`.
            editorial_brief: brief libre décrivant la veille idéale.

        Returns:
            `SourceSuggestions(followed=..., niche=...)`.
        """
        excluded = set(excluded_source_ids or [])

        followed = await self._followed(session, user_id, theme_id, excluded)
        niche = await self._niche(
            session,
            theme_id,
            topic_labels,
            excluded,
            purpose=purpose,
            purpose_other=purpose_other,
            editorial_brief=editorial_brief,
        )

        return SourceSuggestions(followed=followed, niche=niche)

    async def _followed(
        self,
        session: AsyncSession,
        user_id: UUID,
        theme_id: str,
        excluded: set[UUID],
    ) -> list[SourceSuggestionItem]:
        """Sources déjà trustées par l'user, filtrées par thème + exclusions."""
        stmt = (
            select(Source)
            .join(UserSource, UserSource.source_id == Source.id)
            .where(
                UserSource.user_id == user_id,
                Source.theme == theme_id,
                Source.is_active.is_(True),
            )
        )
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
            )
            for s in rows
            if s.id not in excluded
        ]

    async def _niche(
        self,
        session: AsyncSession,
        theme_id: str,
        topic_labels: list[str],
        excluded: set[UUID],
        purpose: str | None = None,
        purpose_other: str | None = None,
        editorial_brief: str | None = None,
    ) -> list[SourceSuggestionItem]:
        if not self._llm.is_ready:
            return await self._fallback_niche(session, theme_id, excluded)

        user_message = (
            f"Thème : {theme_id}\n"
            f"Topics retenus : {', '.join(topic_labels) if topic_labels else '(aucun)'}\n"
            f"Usage souhaité : {purpose_line(purpose, purpose_other)}\n"
            f"Brief éditorial : {editorial_brief or '(aucun)'}\n\n"
            f"Propose 6 à 8 sources de niche pour ce thème."
        )
        raw = await self._llm.chat_json(
            system=_NICHE_SYSTEM_PROMPT,
            user_message=user_message,
            model="mistral-large-latest",
            temperature=0.4,
            max_tokens=1200,
        )
        candidates = self._parse_niche(raw)
        if not candidates:
            return await self._fallback_niche(session, theme_id, excluded)

        items: list[SourceSuggestionItem] = []
        source_service = SourceService(session)
        for cand in candidates:
            try:
                hydrated = await self._hydrate_or_ingest(
                    session, source_service, cand, theme_id
                )
            except Exception as exc:
                logger.warning(
                    "source_suggester.hydrate_failed",
                    name=cand.name,
                    url=cand.url,
                    error=str(exc),
                )
                continue
            if hydrated.id in excluded:
                continue
            items.append(
                SourceSuggestionItem(
                    source_id=hydrated.id,
                    name=hydrated.name,
                    url=hydrated.url,
                    feed_url=hydrated.feed_url,
                    theme=hydrated.theme,
                    why=cand.why,
                )
            )

        return items

    async def _hydrate_or_ingest(
        self,
        session: AsyncSession,
        source_service: SourceService,
        cand: _LLMNicheCandidate,
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

    async def _fallback_niche(
        self,
        session: AsyncSession,
        theme_id: str,
        excluded: set[UUID],
    ) -> list[SourceSuggestionItem]:
        """Sans LLM : 5 sources curées du même thème non exclues."""
        stmt = (
            select(Source)
            .where(
                Source.is_curated.is_(True),
                Source.is_active.is_(True),
                Source.theme == theme_id,
            )
            .limit(5)
        )
        if excluded:
            stmt = stmt.where(Source.id.notin_(excluded))
        result = await session.execute(stmt)
        return [
            SourceSuggestionItem(
                source_id=s.id,
                name=s.name,
                url=s.url,
                feed_url=s.feed_url,
                theme=s.theme,
                why=None,
            )
            for s in result.scalars().all()
        ]

    @staticmethod
    def _parse_niche(raw: dict | list | None) -> list[_LLMNicheCandidate]:
        if not isinstance(raw, dict):
            return []
        items = raw.get("sources")
        if not isinstance(items, list):
            return []
        out: list[_LLMNicheCandidate] = []
        for it in items:
            try:
                out.append(_LLMNicheCandidate.model_validate(it))
            except ValidationError as exc:
                logger.debug("source_suggester.skip_invalid", error=str(exc))
        return out


_source_suggester: SourceSuggester | None = None


def get_source_suggester() -> SourceSuggester:
    global _source_suggester
    if _source_suggester is None:
        _source_suggester = SourceSuggester()
    return _source_suggester
