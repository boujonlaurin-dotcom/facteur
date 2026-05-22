"""Suggestion d'angles + mots-clés explicites pour une veille (Story 23.3).

Évolution du `topic_suggester` legacy (Story 23.1, supprimé) : chaque angle
embarque maintenant 3-5 keywords qui pilotent le filtre temps-réel
(`fetch_veille_feed`). L'angle = titre éditorial, les keywords = match concret
sur title/description des articles.

Appel synchrone à l'instant du flow (mobile attend ~10-15s avec HaloLoader).
Cache in-process TTL 24h pour éviter le re-coût sur édition.
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
class AngleSuggestion:
    title: str
    keywords: list[str]
    reason: str | None


class _LLMAngle(BaseModel):
    """Schéma strict du JSON renvoyé par le LLM."""

    title: str = Field(min_length=1, max_length=120)
    keywords: list[str] = Field(default_factory=list, min_length=1, max_length=10)
    reason: str | None = Field(default=None, max_length=300)


_SYSTEM_PROMPT = """Tu es un expert en curation éditoriale francophone, spécialisé en veille thématique.

Tâche : pour un thème et un brief éditorial donnés, propose 5 à 8 ANGLES de veille pertinents. Chaque angle vient avec 3 à 5 mots-clés explicites qui serviront ensuite à filtrer des articles d'actualité.

Format JSON strict :
{
  "angles": [
    {
      "title": "<titre court fr, 4-8 mots>",
      "keywords": ["<mot-cle-1>", "<mot-cle-2>", "..."],
      "reason": "<1 phrase max sur le pourquoi de cet angle>"
    },
    ...
  ]
}

Contraintes :
- 5 à 8 angles distincts (pas de redondance).
- title : titre court (max 80 chars), explicite, complémentaire aux autres angles.
- keywords : 3 à 5 mots ou expressions courtes (1-3 mots chacun), en français, en minuscules. Ce sont les mots qui doivent matcher dans les titres / descriptions des articles. Pense large (synonymes, variantes, noms propres pertinents) mais reste précis pour le sujet.
- reason : 1 phrase max 200 chars qui explique l'intérêt de cet angle pour le thème + brief.
- Couvre plusieurs angles complémentaires (différents axes du sujet).
- Réponds UNIQUEMENT avec le JSON, rien d'autre."""


def _fallback_angles(theme_label: str) -> list[AngleSuggestion]:
    """Angles génériques si LLM KO — couverture minimale pour ne pas bloquer le flow."""
    return [
        AngleSuggestion(
            title=f"Actualité {theme_label}",
            keywords=[theme_label.lower(), "actualité", "nouveau"],
            reason=f"Suit l'actualité courante de {theme_label}",
        ),
        AngleSuggestion(
            title="Analyses de fond",
            keywords=["analyse", "enquête", "décryptage"],
            reason="Articles long format et tribunes d'experts",
        ),
        AngleSuggestion(
            title="Innovations et nouveautés",
            keywords=["innovation", "nouveauté", "lancement"],
            reason="Suit les évolutions récentes du domaine",
        ),
        AngleSuggestion(
            title="Débats et controverses",
            keywords=["débat", "controverse", "polémique"],
            reason="Sujets clivants et arguments contradictoires",
        ),
        AngleSuggestion(
            title="Initiatives et bonnes pratiques",
            keywords=["initiative", "bonne pratique", "retour d'expérience"],
            reason="Cas concrets et solutions testées",
        ),
    ]


class AngleSuggester:
    """Suggère 5-8 angles + mots-clés via LLM, cache 24h, fallback déterministe."""

    def __init__(
        self,
        llm: EditorialLLMClient | None = None,
        model: str | None = None,
        cache_size: int = _CACHE_SIZE,
        cache_ttl: int = _CACHE_TTL_SECONDS,
    ) -> None:
        self._llm = llm or EditorialLLMClient()
        self._model = model or get_settings().veille_llm_model
        self._cache: TTLCache[str, list[AngleSuggestion]] = TTLCache(
            maxsize=cache_size, ttl=cache_ttl
        )

    @staticmethod
    def _cache_key(theme_id: str, theme_label: str, brief: str) -> str:
        payload = f"{theme_id}|{theme_label}|{brief.strip().lower()}"
        return hashlib.sha256(payload.encode()).hexdigest()

    async def suggest_angles(
        self,
        theme_id: str,
        theme_label: str,
        brief: str = "",
    ) -> list[AngleSuggestion]:
        """Renvoie 5-8 angles pour `theme_id` + `brief`. Fallback si LLM KO."""
        cache_key = self._cache_key(theme_id, theme_label, brief)
        if cached := self._cache.get(cache_key):
            return cached

        if not self._llm.is_ready:
            logger.warning("angle_suggester.llm_unavailable", theme_id=theme_id)
            result = _fallback_angles(theme_label)
            self._cache[cache_key] = result
            return result

        user_message = (
            f"Thème : {theme_label} (slug: {theme_id})\n"
            f"Brief éditorial : {brief or '(aucun)'}\n\n"
            f"Propose 5 à 8 angles avec leurs mots-clés explicites."
        )

        raw = await self._llm.chat_json(
            system=_SYSTEM_PROMPT,
            user_message=user_message,
            model=self._model,
            temperature=0.3,
            max_tokens=1200,
        )

        angles = self._parse(raw)
        if not angles:
            logger.warning(
                "angle_suggester.parse_failed",
                theme_id=theme_id,
                model=self._model,
            )
            angles = _fallback_angles(theme_label)

        self._cache[cache_key] = angles
        return angles

    @staticmethod
    def _parse(raw: dict | list | None) -> list[AngleSuggestion]:
        if not isinstance(raw, dict):
            return []
        items = raw.get("angles")
        if not isinstance(items, list):
            return []
        try:
            parsed = [_LLMAngle.model_validate(it) for it in items]
        except ValidationError as exc:
            logger.warning("angle_suggester.validation_error", error=str(exc))
            return []
        return [
            AngleSuggestion(
                title=a.title.strip(),
                keywords=[k.strip().lower() for k in a.keywords if k.strip()],
                reason=a.reason,
            )
            for a in parsed
        ]


_angle_suggester: AngleSuggester | None = None


def get_angle_suggester() -> AngleSuggester:
    global _angle_suggester
    if _angle_suggester is None:
        _angle_suggester = AngleSuggester()
    return _angle_suggester
