"""TopicEnrichmentService: LLM one-shot enrichment for custom topics (Epic 11).

Takes a free-text topic name from the user and maps it to:
- slug_parent: one of VALID_TOPIC_SLUGS
- keywords: 5-10 relevant search keywords
- intent_description: one-sentence description of the topic intent
- entity_type: if the input is a named entity (PERSON, ORG, EVENT, LOCATION, PRODUCT)
- canonical_name: normalized full name of the entity
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

import httpx
import structlog

from app.config import get_settings
from app.services.ml.classification_service import (
    MISTRAL_API_URL,
    SLUG_TO_LABEL,
    VALID_ENTITY_TYPES,
    VALID_TOPIC_SLUGS,
)

log = structlog.get_logger()

# Build the topic list for the enrichment prompt
_TOPIC_LIST = "\n".join(
    f"- {slug}: {label}" for slug, label in sorted(SLUG_TO_LABEL.items())
)

ENRICHMENT_SYSTEM_PROMPT = f"""Tu es un assistant qui catégorise les sujets d'intérêt des utilisateurs.

L'utilisateur te donne un sujet libre (ex: "Voiture électrique", "GPT-5", "Affaire Epstein").
Tu dois le mapper sur UN SEUL slug parmi cette liste prédéfinie :

{_TOPIC_LIST}

Tu dois retourner un JSON valide avec exactement ces champs :
1. "slug_parent": le slug le plus pertinent (OBLIGATOIREMENT un slug de la liste ci-dessus)
2. "keywords": un array de 5 à 10 mots-clés de recherche associés (en français)
3. "intent_description": une phrase décrivant l'intention de suivi

Si le sujet est une entité nommée (personne, organisation, événement, lieu, produit), ajoute aussi :
4. "entity_type": "PERSON" | "ORG" | "EVENT" | "LOCATION" | "PRODUCT"
5. "canonical_name": le nom complet normalisé (ex: "E. Macron" → "Emmanuel Macron")
Si ce n'est PAS une entité nommée, ne PAS inclure entity_type ni canonical_name.

Exemple pour "Voiture électrique" (pas une entité) :
{{"slug_parent": "climate", "keywords": ["véhicule électrique", "Tesla", "batterie", "recharge", "mobilité durable", "ZFE", "autonomie"], "intent_description": "Suivi des actualités sur les voitures et véhicules électriques"}}

Exemple pour "Elon Musk" (entité PERSON) :
{{"slug_parent": "startups", "keywords": ["Tesla", "SpaceX", "X", "Neuralink", "milliardaire"], "intent_description": "Suivi des actualités sur Elon Musk", "entity_type": "PERSON", "canonical_name": "Elon Musk"}}

Réponds UNIQUEMENT avec le JSON, rien d'autre."""


DISAMBIGUATION_SYSTEM_PROMPT = f"""Tu es un assistant qui aide à désambiguïser les sujets d'intérêt.

L'utilisateur te donne un nom ou sujet libre. Tu dois proposer les 1 à 5 interprétations les plus probables.

Pour chaque interprétation, tu dois fournir :
1. "canonical_name": le nom complet normalisé
2. "entity_type": "PERSON" | "ORG" | "EVENT" | "LOCATION" | "PRODUCT" | null (si c'est un concept/thème)
3. "description": une phrase courte décrivant cette interprétation (max 80 caractères)
4. "slug_parent": le slug le plus pertinent parmi cette liste :

{_TOPIC_LIST}

Si le sujet est clairement non-ambigu (ex: "Emmanuel Macron"), retourne un seul résultat.
Si le sujet est ambigu (ex: "Dakar", "Mercury", "Apple"), retourne 2 à 5 interprétations.

Retourne un JSON valide : {{"suggestions": [...]}}
Réponds UNIQUEMENT avec le JSON, rien d'autre."""


@dataclass
class TopicEnrichmentResult:
    """Result of LLM topic enrichment."""

    slug_parent: str
    keywords: list[str]
    intent_description: str
    entity_type: str | None = field(default=None)
    canonical_name: str | None = field(default=None)


@dataclass
class DisambiguationOption:
    """A single disambiguation suggestion from the LLM."""

    canonical_name: str
    entity_type: str | None
    description: str
    slug_parent: str


class TopicEnrichmentService:
    """Service d'enrichissement de topics via Mistral API (one-shot)."""

    def __init__(self) -> None:
        settings = get_settings()
        self._api_key = settings.mistral_api_key
        self._ready = bool(self._api_key)
        self._client: httpx.AsyncClient | None = None

        if not self._ready:
            log.warning(
                "topic_enrichment.no_api_key",
                message="MISTRAL_API_KEY not set. Topic enrichment unavailable.",
            )

    def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=15.0,
                headers={
                    "Authorization": f"Bearer {self._api_key}",
                    "Content-Type": "application/json",
                },
            )
        return self._client

    async def enrich(self, topic_name: str) -> TopicEnrichmentResult:
        """Enrich a free-text topic name via LLM one-shot call.

        Args:
            topic_name: User-provided topic name (e.g. "Voiture électrique")

        Returns:
            TopicEnrichmentResult with slug_parent, keywords, intent_description,
            and optionally entity_type + canonical_name

        Raises:
            ValueError: If LLM returns an invalid slug_parent
        """
        if not topic_name or not topic_name.strip():
            raise ValueError("topic_name cannot be empty")

        # Try LLM enrichment first
        if self._ready:
            try:
                return await self._enrich_via_llm(topic_name.strip())
            except Exception as e:
                log.warning(
                    "topic_enrichment.llm_failed",
                    topic=topic_name,
                    error=str(e),
                )

        # Fallback: fuzzy matching on SLUG_TO_LABEL
        return self._fallback_enrich(topic_name.strip())

    async def _enrich_via_llm(self, topic_name: str) -> TopicEnrichmentResult:
        """Call Mistral API for topic enrichment."""
        client = self._get_client()
        response = await client.post(
            MISTRAL_API_URL,
            json={
                "model": "mistral-small-latest",
                "messages": [
                    {"role": "system", "content": ENRICHMENT_SYSTEM_PROMPT},
                    {"role": "user", "content": topic_name},
                ],
                "temperature": 0.0,
                "max_tokens": 300,
            },
        )
        response.raise_for_status()
        data = response.json()

        choices = data.get("choices") or []
        if not choices:
            raise ValueError("Empty LLM response")

        raw_answer = (choices[0].get("message") or {}).get("content") or ""
        raw_answer = raw_answer.strip()

        if not raw_answer:
            raise ValueError("Empty LLM content")

        # Parse JSON response
        # Strip markdown code blocks if present
        if raw_answer.startswith("```"):
            lines = raw_answer.split("\n")
            raw_answer = "\n".join(
                line for line in lines if not line.strip().startswith("```")
            )

        parsed = json.loads(raw_answer)

        slug = parsed.get("slug_parent", "").strip().lower()
        if slug not in VALID_TOPIC_SLUGS:
            raise ValueError(f"Invalid slug_parent from LLM: '{slug}'")

        keywords = parsed.get("keywords", [])
        if not isinstance(keywords, list):
            keywords = []
        keywords = [str(k).strip() for k in keywords if k][:10]

        intent = parsed.get("intent_description", "")
        if not isinstance(intent, str):
            intent = ""

        # Extract entity fields if present
        entity_type = None
        canonical_name = None
        raw_entity_type = parsed.get("entity_type")
        if (
            isinstance(raw_entity_type, str)
            and raw_entity_type.upper() in VALID_ENTITY_TYPES
        ):
            entity_type = raw_entity_type.upper()
            raw_canonical = parsed.get("canonical_name")
            canonical_name = (
                raw_canonical.strip()
                if isinstance(raw_canonical, str) and raw_canonical.strip()
                else topic_name
            )

        log.info(
            "topic_enrichment.success",
            topic=topic_name,
            slug=slug,
            keyword_count=len(keywords),
            entity_type=entity_type,
        )

        return TopicEnrichmentResult(
            slug_parent=slug,
            keywords=keywords,
            intent_description=intent.strip(),
            entity_type=entity_type,
            canonical_name=canonical_name,
        )

    def _fallback_enrich(self, topic_name: str) -> TopicEnrichmentResult:
        """Fallback enrichment without LLM: fuzzy match on SLUG_TO_LABEL."""
        topic_lower = topic_name.lower()

        # Try exact slug match first
        if topic_lower in VALID_TOPIC_SLUGS:
            label = SLUG_TO_LABEL.get(topic_lower, topic_name)
            return TopicEnrichmentResult(
                slug_parent=topic_lower,
                keywords=[topic_lower, topic_name.lower()],
                intent_description=f"Suivi de {label}",
            )

        # Try matching in labels
        best_slug = None
        for slug, label in SLUG_TO_LABEL.items():
            if topic_lower in label.lower() or label.lower() in topic_lower:
                best_slug = slug
                break

        if not best_slug:
            # Default to most generic match based on common words
            best_slug = "tech"  # Safe default

        log.warning(
            "topic_enrichment.fallback_used",
            topic=topic_name,
            slug=best_slug,
        )

        return TopicEnrichmentResult(
            slug_parent=best_slug,
            keywords=[topic_name.lower()],
            intent_description=f"Suivi de {topic_name}",
        )

    async def disambiguate(
        self,
        name: str,
        *,
        theme_hint: str | None = None,
    ) -> list[DisambiguationOption]:
        """Return 1-5 disambiguation suggestions for an ambiguous topic name."""
        if not name or not name.strip():
            raise ValueError("name cannot be empty")

        if self._ready:
            try:
                return await self._disambiguate_via_llm(name.strip(), theme_hint)
            except Exception as e:
                log.warning(
                    "topic_disambiguation.llm_failed",
                    name=name,
                    error=str(e),
                )

        # Fallback: single result using existing enrich
        result = self._fallback_enrich(name.strip())
        return [
            DisambiguationOption(
                canonical_name=name.strip(),
                entity_type=result.entity_type,
                description=result.intent_description,
                slug_parent=result.slug_parent,
            )
        ]

    async def _disambiguate_via_llm(
        self,
        name: str,
        theme_hint: str | None,
    ) -> list[DisambiguationOption]:
        """Call Mistral API for topic disambiguation."""
        client = self._get_client()

        user_message = name
        if theme_hint:
            user_message += f" (contexte: {theme_hint})"

        response = await client.post(
            MISTRAL_API_URL,
            json={
                "model": "mistral-small-latest",
                "messages": [
                    {"role": "system", "content": DISAMBIGUATION_SYSTEM_PROMPT},
                    {"role": "user", "content": user_message},
                ],
                "temperature": 0.1,
                "max_tokens": 600,
            },
        )
        response.raise_for_status()
        data = response.json()

        choices = data.get("choices") or []
        if not choices:
            raise ValueError("Empty LLM response")

        raw_answer = (choices[0].get("message") or {}).get("content") or ""
        raw_answer = raw_answer.strip()

        if not raw_answer:
            raise ValueError("Empty LLM content")

        # Strip markdown code blocks if present
        if raw_answer.startswith("```"):
            lines = raw_answer.split("\n")
            raw_answer = "\n".join(
                line for line in lines if not line.strip().startswith("```")
            )

        parsed = json.loads(raw_answer)
        raw_suggestions = parsed.get("suggestions", [])
        if not isinstance(raw_suggestions, list):
            raise ValueError("LLM response 'suggestions' is not a list")

        options: list[DisambiguationOption] = []
        for item in raw_suggestions:
            if not isinstance(item, dict):
                continue

            slug = (item.get("slug_parent") or "").strip().lower()
            if slug not in VALID_TOPIC_SLUGS:
                continue

            canonical = (item.get("canonical_name") or "").strip()
            if not canonical:
                continue

            description = (item.get("description") or "").strip()

            entity_type = None
            raw_et = item.get("entity_type")
            if isinstance(raw_et, str) and raw_et.upper() in VALID_ENTITY_TYPES:
                entity_type = raw_et.upper()

            options.append(
                DisambiguationOption(
                    canonical_name=canonical,
                    entity_type=entity_type,
                    description=description,
                    slug_parent=slug,
                )
            )

        if not options:
            raise ValueError("No valid suggestions from LLM")

        log.info(
            "topic_disambiguation.success",
            name=name,
            suggestion_count=len(options),
        )

        return options[:5]

    def is_ready(self) -> bool:
        return self._ready

    async def close(self) -> None:
        if self._client:
            await self._client.aclose()
            self._client = None


# Singleton
_topic_enrichment_service: TopicEnrichmentService | None = None


def get_topic_enrichment_service() -> TopicEnrichmentService:
    global _topic_enrichment_service
    if _topic_enrichment_service is None:
        _topic_enrichment_service = TopicEnrichmentService()
    return _topic_enrichment_service
