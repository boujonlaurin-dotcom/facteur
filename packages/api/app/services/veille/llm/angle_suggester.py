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
from app.services.recommendation.french_stopwords import FRENCH_STOP_WORDS

logger = structlog.get_logger()

_CACHE_SIZE = 256
# TTL 24h : après un déploiement durcissant le prompt, d'anciennes suggestions
# génériques peuvent coexister au plus 24h avant expiration du cache in-process.
_CACHE_TTL_SECONDS = 86400  # 24h

# Denylist de mots-clés **unigrammes** de discours / d'analyse : ils matchent
# tout et n'importe quoi (« budget », « europe »…), gonflent le corpus hors-sujet
# et, avec le floor durci de la curation, ne qualifient de toute façon plus seuls.
# Filtrés en post-parse (jamais les expressions multi-mots — elles discriminent).
_GENERIC_KEYWORDS: frozenset[str] = frozenset(
    {
        "actualité",
        "actualités",
        "analyse",
        "analyses",
        "décryptage",
        "enquête",
        "enquêtes",
        "dossier",
        "dossiers",
        "reportage",
        "enjeu",
        "enjeux",
        "stratégie",
        "stratégies",
        "budget",
        "débat",
        "débats",
        "controverse",
        "polémique",
        "tribune",
        "initiative",
        "initiatives",
        "réforme",
        "réformes",
        "mesure",
        "mesures",
        "projet",
        "projets",
        "politique",
        "politiques",
        "réglementation",
        "loi",
        "lois",
        "crise",
        "crises",
        "croissance",
        "développement",
        "impact",
        "impacts",
        "bilan",
        "perspective",
        "perspectives",
        "tendance",
        "tendances",
        "prospective",
        "avenir",
        "futur",
        "innovation",
        "innovations",
        "nouveau",
        "nouveauté",
        "nouveautés",
        "lancement",
        "question",
        "questions",
        "monde",
        "société",
        "économie",
        "europe",
        "france",
        "international",
        "national",
        "secteur",
        "secteurs",
        "marché",
        "marchés",
        "acteur",
        "acteurs",
        "expert",
        "experts",
        "interview",
        "portrait",
        "chiffres",
        "rapport",
        "étude",
        "études",
    }
)


@dataclass(frozen=True)
class AngleSuggestion:
    title: str
    keywords: list[str]
    reason: str | None = None


class _LLMAngle(BaseModel):
    """Schéma strict du JSON renvoyé par le LLM."""

    title: str = Field(min_length=1, max_length=120)
    keywords: list[str] = Field(default_factory=list, min_length=1, max_length=10)


_SYSTEM_PROMPT = """Tu es un expert en curation éditoriale francophone, spécialisé en veille thématique.

Tâche : pour un thème et un brief éditorial donnés, propose 8 à 12 ANGLES de veille pertinents. Chaque angle vient avec 3 à 5 mots-clés explicites qui serviront ensuite à FILTRER des articles d'actualité (match sur le titre / la description).

Format JSON strict :
{
  "angles": [
    {
      "title": "<titre court fr, 4-8 mots>",
      "keywords": ["<mot-cle-1>", "<mot-cle-2>", "..."]
    },
    ...
  ]
}

RÈGLE D'OR des mots-clés — applique ce test à CHAQUE mot-clé :
« Un article dont le titre contient ce mot-clé parle presque certainement de ce sujet précis. »
Si ce n'est pas vrai, le mot-clé est trop générique : jette-le.

Contraintes mots-clés :
- Privilégie les NOMS PROPRES, entités datées et termes techniques : personnes, organisations, lois, produits, événements, lieux précis (ex. « conseil constitutionnel », « jeux olympiques 2024 », « intelligence artificielle générative »).
- AU MOINS 2 expressions multi-mots (2 à 4 mots) par angle : elles discriminent bien mieux qu'un mot isolé.
- INTERDIT : le vocabulaire de discours / d'analyse qui matche tout et n'importe quoi — par exemple « stratégie », « budget », « analyse », « enjeux », « débat », « europe », « société », « avenir », « tendance », « réforme », « crise », « impact ». Ces mots ne disent RIEN du sujet précis.
- 3 à 5 mots-clés par angle, en français, en minuscules.

Contraintes angles :
- 8 à 12 angles distincts (pas de redondance), complémentaires (différents axes du sujet).
- title : titre court (max 80 chars), explicite.
- Réponds UNIQUEMENT avec le JSON, rien d'autre."""


def _filter_generic_keywords(keywords: list[str]) -> list[str]:
    """Écarte les **unigrammes** de discours (denylist + stopwords FR).

    Les expressions **multi-mots** sont toujours conservées : même bâties sur des
    mots vagues, la combinaison discrimine (« coupe du monde », « conseil
    constitutionnel »). Ordre d'origine préservé.
    """
    # Multi-mots (`" " in kw`) : jamais filtré — la combinaison discrimine même
    # bâtie sur des mots vagues. Unigramme : écarté s'il est dans la denylist ou
    # les stopwords FR. Ordre d'origine préservé.
    return [
        kw
        for kw in keywords
        if " " in kw or (kw not in _GENERIC_KEYWORDS and kw not in FRENCH_STOP_WORDS)
    ]


def _fallback_angles(theme_label: str) -> list[AngleSuggestion]:
    """Angles de repli si le LLM est KO — peu nombreux, ancrés sur le thème.

    Volontairement minimalistes et bâtis sur des **expressions multi-mots**
    ancrées au thème (elles qualifient le floor durci comme « hit fort » et
    survivent au filtre denylist). Ces grappes restent génériques : elles
    produiront un feed court, voire vide — comportement dégradé **assumé** quand
    le LLM est indisponible, préférable au bruit des anciennes grappes 100 %
    discours (« analyse », « débat »…) qui inondaient la veille de hors-sujet.
    """
    label = theme_label.lower().strip()
    return [
        AngleSuggestion(
            title=f"Actualité {theme_label}",
            keywords=[f"actualité {label}", f"nouveauté {label}"],
        ),
        AngleSuggestion(
            title=f"Analyses {theme_label}",
            keywords=[f"analyse {label}", f"enquête {label}"],
        ),
        AngleSuggestion(
            title=f"Débats {theme_label}",
            keywords=[f"débat {label}", f"tribune {label}"],
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
            f"Propose 8 à 12 angles avec leurs mots-clés explicites."
        )

        raw = await self._llm.chat_json(
            system=_SYSTEM_PROMPT,
            user_message=user_message,
            model=self._model,
            temperature=0.3,
            max_tokens=2000,
            call_site="veille_suggester",
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

        result: list[AngleSuggestion] = []
        dropped = 0
        for a in parsed:
            raw_kws = [k.strip().lower() for k in a.keywords if k.strip()]
            kept = _filter_generic_keywords(raw_kws)
            dropped += len(raw_kws) - len(kept)
            if not kept:
                # Angle intégralement vidé par le filtre → écarté (une grappe
                # 100 % générique ne curerait rien d'utile).
                continue
            result.append(
                AngleSuggestion(title=a.title.strip(), keywords=kept, reason=None)
            )
        if dropped:
            logger.info("angle_suggester.keywords_filtered", dropped=dropped)
        return result


_angle_suggester: AngleSuggester | None = None


def get_angle_suggester() -> AngleSuggester:
    global _angle_suggester
    if _angle_suggester is None:
        _angle_suggester = AngleSuggester()
    return _angle_suggester
