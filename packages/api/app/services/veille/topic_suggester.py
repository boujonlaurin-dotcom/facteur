"""Suggestion de topics liés à un thème via LLM Mistral, avec cache TTL + fallback.

Pool DB : ce service n'ouvre AUCUNE session — le caller fournit ce qu'il faut.
Cache in-process (`cachetools.TTLCache`) — à migrer Redis si scale horizontal.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass

import structlog
from cachetools import TTLCache
from pydantic import BaseModel, Field, ValidationError

from app.services.editorial.llm_client import EditorialLLMClient

logger = structlog.get_logger()

_DEFAULT_CACHE_SIZE = 256
_DEFAULT_CACHE_TTL_SECONDS = 600  # 10 min
_SUGGESTIONS_PER_CALL = 5

# Slugs partagés avec le mobile (Step 1 « Pour quoi faire ? »). Doit rester
# aligné avec `apps/mobile/lib/features/veille/widgets/veille_widgets.dart`.
PURPOSE_LABELS: dict[str, str] = {
    "me_tenir_au_courant": "Me tenir à jour de l'actu",
    "progresser_au_travail": "M'améliorer dans mon travail",
    "culture_generale": "Développer ma culture générale",
    "preparer_projet": "Préparer un projet / une décision",
    "approfondir_passion": "Approfondir un sujet de passion",
    "autre": "Autre",
}


def purpose_label(slug: str | None) -> str:
    """Retourne le label fr d'un slug purpose, ou '(non précisé)' si inconnu."""
    if not slug:
        return "(non précisé)"
    return PURPOSE_LABELS.get(slug, slug)


def purpose_line(slug: str | None, other: str | None) -> str:
    """Format `<label> (<other>)` pour le user_message LLM."""
    base = purpose_label(slug)
    return f"{base} ({other})" if other else base


@dataclass(frozen=True)
class TopicSuggestion:
    topic_id: str
    label: str
    reason: str | None


class _LLMSuggestedTopic(BaseModel):
    """Schéma strict du JSON retourné par le LLM."""

    topic_id: str = Field(min_length=1, max_length=80)
    label: str = Field(min_length=1, max_length=200)
    reason: str | None = Field(default=None, max_length=300)


_SYSTEM_PROMPT = """Tu es un expert en curation éditoriale francophone, spécialisé en veille thématique.

Tâche : pour un thème donné et une liste de topics déjà sélectionnés par l'utilisateur, propose 5 topics SUPPLÉMENTAIRES pertinents, NON redondants avec ceux déjà choisis ni avec ceux à exclure.

Format JSON strict :
{"topics": [{"topic_id": "<slug-kebab-case>", "label": "<nom court fr>", "reason": "<1 phrase max sur le pourquoi>"}, ...]}

Contraintes :
- Exactement 5 topics.
- topic_id : slug en kebab-case, max 80 caractères, stable (ex: "evaluations-scolaires").
- label : nom court français max 60 caractères (ex: "Évaluations scolaires").
- reason : 1 phrase max 200 caractères qui explique l'intérêt pour le thème — peut être null.
- Topics ciblés, ni trop génériques ni trop pointus.
- Respecte la diversité : couvre plusieurs angles du thème.
- Réponds UNIQUEMENT avec le JSON, rien d'autre."""


def _fallback_topics(theme_label: str) -> list[TopicSuggestion]:
    """5 topics génériques de secours quand le LLM est indisponible."""
    return [
        TopicSuggestion(
            topic_id="actualite-generale",
            label=f"Actualité {theme_label}",
            reason=f"Suit l'actualité courante autour de {theme_label}",
        ),
        TopicSuggestion(
            topic_id="analyses-de-fond",
            label="Analyses de fond",
            reason="Articles long format et tribunes d'experts",
        ),
        TopicSuggestion(
            topic_id="recherche-etudes",
            label="Recherche et études",
            reason="Études récentes et travaux de recherche",
        ),
        TopicSuggestion(
            topic_id="debats-controverses",
            label="Débats et controverses",
            reason="Sujets clivants et arguments contradictoires",
        ),
        TopicSuggestion(
            topic_id="initiatives-pratiques",
            label="Initiatives et bonnes pratiques",
            reason="Retours d'expérience concrets et solutions testées",
        ),
    ]


class TopicSuggester:
    """Suggère des topics liés à un thème via LLM, avec cache + fallback."""

    def __init__(
        self,
        llm: EditorialLLMClient | None = None,
        cache_size: int = _DEFAULT_CACHE_SIZE,
        cache_ttl: int = _DEFAULT_CACHE_TTL_SECONDS,
    ) -> None:
        self._llm = llm or EditorialLLMClient()
        self._cache: TTLCache[str, list[TopicSuggestion]] = TTLCache(
            maxsize=cache_size, ttl=cache_ttl
        )

    @staticmethod
    def _cache_key(
        theme_id: str,
        selected: list[str],
        excluded: list[str],
        purpose: str | None,
        purpose_other: str | None,
        editorial_brief: str | None,
    ) -> str:
        # Inclus purpose + brief : 2 users avec mêmes topics mais purpose
        # différent doivent recevoir des suggestions différentes.
        payload = "|".join(
            [
                theme_id,
                ",".join(sorted(selected)),
                ",".join(sorted(excluded)),
                purpose or "",
                purpose_other or "",
                editorial_brief or "",
            ]
        )
        return hashlib.sha256(payload.encode()).hexdigest()

    async def suggest_topics(
        self,
        theme_id: str,
        theme_label: str,
        selected_topic_ids: list[str],
        excluded_topic_ids: list[str] | None = None,
        purpose: str | None = None,
        purpose_other: str | None = None,
        editorial_brief: str | None = None,
    ) -> list[TopicSuggestion]:
        """Renvoie 5 suggestions de topics pour `theme_id`.

        Args:
            theme_id: slug du thème (ex: 'education').
            theme_label: label affichable (ex: 'Éducation').
            selected_topic_ids: topics déjà choisis (à éviter).
            excluded_topic_ids: topics à exclure (ex: refusés précédemment).
            purpose: slug de l'usage souhaité (V1, optionnel).
            purpose_other: free-text quand `purpose='autre'`.
            editorial_brief: brief libre (≤280 chars) décrivant la veille idéale.

        Returns:
            Exactement 5 `TopicSuggestion`. Fallback déterministe si LLM KO.
        """
        excluded = excluded_topic_ids or []
        cache_key = self._cache_key(
            theme_id,
            selected_topic_ids,
            excluded,
            purpose,
            purpose_other,
            editorial_brief,
        )
        if cached := self._cache.get(cache_key):
            return cached

        if not self._llm.is_ready:
            logger.warning(
                "topic_suggester.llm_unavailable",
                theme_id=theme_id,
                using="fallback",
            )
            result = _fallback_topics(theme_label)
            self._cache[cache_key] = result
            return result

        user_message = (
            f"Thème : {theme_label} (slug: {theme_id})\n"
            f"Topics déjà sélectionnés : "
            f"{', '.join(selected_topic_ids) if selected_topic_ids else '(aucun)'}\n"
            f"Topics à exclure : "
            f"{', '.join(excluded) if excluded else '(aucun)'}\n"
            f"Usage souhaité : {purpose_line(purpose, purpose_other)}\n"
            f"Brief éditorial : {editorial_brief or '(aucun)'}\n\n"
            f"Propose 5 topics supplémentaires."
        )

        raw = await self._llm.chat_json(
            system=_SYSTEM_PROMPT,
            user_message=user_message,
            model="mistral-large-latest",
            temperature=0.3,
            max_tokens=800,
        )

        suggestions = self._parse(raw)
        if suggestions is None or len(suggestions) != _SUGGESTIONS_PER_CALL:
            logger.warning(
                "topic_suggester.parse_failed",
                theme_id=theme_id,
                using="fallback",
            )
            suggestions = _fallback_topics(theme_label)

        self._cache[cache_key] = suggestions
        return suggestions

    @staticmethod
    def _parse(raw: dict | list | None) -> list[TopicSuggestion] | None:
        if not isinstance(raw, dict):
            return None
        items = raw.get("topics")
        if not isinstance(items, list):
            return None
        try:
            parsed = [_LLMSuggestedTopic.model_validate(it) for it in items]
        except ValidationError as exc:
            logger.warning("topic_suggester.validation_error", error=str(exc))
            return None
        return [
            TopicSuggestion(
                topic_id=p.topic_id,
                label=p.label,
                reason=p.reason,
            )
            for p in parsed
        ]


_topic_suggester: TopicSuggester | None = None


def get_topic_suggester() -> TopicSuggester:
    global _topic_suggester
    if _topic_suggester is None:
        _topic_suggester = TopicSuggester()
    return _topic_suggester
