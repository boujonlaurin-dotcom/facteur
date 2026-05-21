"""Suggestion de sources pour une veille (Story 23.3).

Évolution du `source_suggester` legacy (Story 23.1, supprimé) : version
simplifiée qui ne fait QUE l'appel LLM — pas de HTTP detect, pas de DB ingest.
L'ingestion se fait au POST /api/veille/config via le flow `niche_candidate`
existant. Cela rend l'endpoint rapide (~10s) et garde la complexité d'ingestion
là où elle existe déjà.

Renforce les anciens prompts pour les cas niches : oblige le LLM à proposer
sources institutionnelles + médias locaux/internationaux quand le thème est
spécialisé (ex : "Musées contemporains Barcelone").
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass

import structlog
from cachetools import TTLCache
from pydantic import BaseModel, Field, ValidationError

from app.config import get_settings
from app.services.editorial.llm_client import EditorialLLMClient

logger = structlog.get_logger()

_CACHE_SIZE = 256
_CACHE_TTL_SECONDS = 86400  # 24h


@dataclass(frozen=True)
class SourceSuggestion:
    name: str
    url: str
    why: str | None
    relevance_score: float


class _LLMSource(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    url: str = Field(min_length=4, max_length=2048)
    why: str | None = Field(default=None, max_length=300)
    relevance_score: float = Field(ge=0.0, le=1.0)


_SYSTEM_PROMPT = """Tu es un expert en curation média francophone et internationale.

Tâche : pour un thème + des angles + des mots-clés + un brief, propose 5 à 10 sources (médias établis, médias indé, newsletters, blogs spécialisés, podcasts, sites institutionnels) classées par pertinence.

IMPORTANT : pour les cas NICHE (sujets très spécialisés ou géographiquement précis), ne te limite PAS aux grands médias francophones. Inclus :
- sites institutionnels (musées, universités, organismes officiels)
- médias locaux / régionaux / internationaux pertinents
- blogs d'experts, newsletters thématiques, podcasts spécialisés
- sites en anglais ou langue locale SI ils sont la meilleure source disponible

Tu DOIS proposer au moins 3 sources même sur les cas les plus niches.

Format JSON strict :
{
  "sources": [
    {
      "name": "<nom>",
      "url": "<url racine, https://...>",
      "why": "<1 phrase max>",
      "relevance_score": 0.0-1.0
    },
    ...
  ]
}

Contraintes :
- 5 à 10 sources (minimum 3 absolu, même cas niche).
- relevance_score (0.0–1.0) : pondéré par adéquation aux angles+mots-clés ET au brief.
- url : page d'accueil ou URL racine (pas d'article spécifique).
- why : 1 phrase max qui explique pourquoi cette source matche les angles.
- Pas de doublon de domaine.
- Réponds UNIQUEMENT avec le JSON."""


def _fallback_sources() -> list[SourceSuggestion]:
    """Si LLM KO : liste vide (mobile bascule sur le mode advanced URL).

    On retourne intentionnellement vide plutôt que des sources génériques :
    pousser "Le Monde" à un user qui cherche "musées Barcelone" est pire que
    montrer un état vide avec le mode advanced URL.
    """
    return []


class SourceSuggester:
    """Suggère 5-10 sources via LLM. Pas d'ingestion DB ici (faite à l'upsert)."""

    def __init__(
        self,
        llm: EditorialLLMClient | None = None,
        model: str | None = None,
        cache_size: int = _CACHE_SIZE,
        cache_ttl: int = _CACHE_TTL_SECONDS,
    ) -> None:
        self._llm = llm or EditorialLLMClient()
        self._model = model or get_settings().veille_llm_model
        self._cache: TTLCache[str, list[SourceSuggestion]] = TTLCache(
            maxsize=cache_size, ttl=cache_ttl
        )

    @staticmethod
    def _cache_key(
        theme_id: str,
        theme_label: str,
        brief: str,
        angles: list[str],
        keywords: list[str],
    ) -> str:
        payload = "|".join(
            [
                theme_id,
                theme_label,
                brief.strip().lower(),
                ",".join(sorted(a.strip().lower() for a in angles)),
                ",".join(sorted(k.strip().lower() for k in keywords)),
            ]
        )
        return hashlib.sha256(payload.encode()).hexdigest()

    async def suggest_sources(
        self,
        theme_id: str,
        theme_label: str,
        brief: str = "",
        angles: list[str] | None = None,
        keywords: list[str] | None = None,
    ) -> list[SourceSuggestion]:
        """Renvoie 5-10 sources rankées. Vide si LLM KO."""
        angles = angles or []
        keywords = keywords or []
        cache_key = self._cache_key(theme_id, theme_label, brief, angles, keywords)
        if cached := self._cache.get(cache_key):
            return cached

        if not self._llm.is_ready:
            logger.warning("source_suggester.llm_unavailable", theme_id=theme_id)
            result = _fallback_sources()
            self._cache[cache_key] = result
            return result

        angles_block = "\n".join(f"  - {a}" for a in angles) if angles else "  (aucun)"
        keywords_str = ", ".join(keywords) if keywords else "(aucun)"
        user_message = (
            f"Thème : {theme_label} (slug: {theme_id})\n"
            f"Angles retenus :\n{angles_block}\n"
            f"Mots-clés : {keywords_str}\n"
            f"Brief éditorial : {brief or '(aucun)'}\n\n"
            f"Propose 5 à 10 sources rankées (minimum 3 même cas niche)."
        )

        raw = await self._llm.chat_json(
            system=_SYSTEM_PROMPT,
            user_message=user_message,
            model=self._model,
            temperature=0.4,
            max_tokens=1500,
        )

        sources = self._parse(raw)
        if not sources:
            logger.warning(
                "source_suggester.parse_failed",
                theme_id=theme_id,
                model=self._model,
            )
            sources = _fallback_sources()

        # Dédoublonne par domaine racine (keep highest score)
        sources = self._dedupe_by_domain(sources)
        # Trie desc par relevance_score
        sources.sort(key=lambda s: s.relevance_score, reverse=True)

        self._cache[cache_key] = sources
        return sources

    @staticmethod
    def _parse(raw: dict | list | None) -> list[SourceSuggestion]:
        if not isinstance(raw, dict):
            return []
        items = raw.get("sources")
        if not isinstance(items, list):
            return []
        out: list[SourceSuggestion] = []
        for it in items:
            try:
                parsed = _LLMSource.model_validate(it)
            except ValidationError as exc:
                logger.debug("source_suggester.skip_invalid", error=str(exc))
                continue
            out.append(
                SourceSuggestion(
                    name=parsed.name.strip(),
                    url=parsed.url.strip(),
                    why=parsed.why,
                    relevance_score=parsed.relevance_score,
                )
            )
        return out

    @staticmethod
    def _dedupe_by_domain(sources: list[SourceSuggestion]) -> list[SourceSuggestion]:
        from urllib.parse import urlparse

        seen: dict[str, SourceSuggestion] = {}
        for s in sources:
            host = (urlparse(s.url).hostname or s.url).lower()
            host = host[4:] if host.startswith("www.") else host
            existing = seen.get(host)
            if existing is None or s.relevance_score > existing.relevance_score:
                seen[host] = s
        return list(seen.values())


_source_suggester: SourceSuggester | None = None


def get_source_suggester() -> SourceSuggester:
    global _source_suggester
    if _source_suggester is None:
        _source_suggester = SourceSuggester()
    return _source_suggester
