"""LLM bias annotation service (Phase 4 — analyse fine des biais éditoriaux).

Wrappe `EditorialLLMClient.chat_json(model="mistral-medium-latest")` pour
produire des annotations au schéma v2 strict (target_spans pondérés +
exclude_spans binaires + justification par span). Sortie consommée par le
harness de calibration offline (PR 2) puis par le pipeline production (PR 4).

PR 1 : service + validateur tolérant (drop + log), **pas branché au pipeline**.
"""

from __future__ import annotations

import structlog

from app.services.editorial.llm_client import EditorialLLMClient

logger = structlog.get_logger(__name__)

LLM_VERSION = "mistral-medium-latest-v1"
DEFAULT_MODEL = "mistral-medium-latest"

TARGET_CATEGORIES = frozenset(
    {
        "editorial_angle",
        "fact",
        "multi_token_expression",
        "framing_noun",
        "foreign_lang",
    }
)
EXCLUDE_CATEGORIES = frozenset(
    {
        "pivot_entity",
        "neutral_verb",
        "entity_alias",
        "geographic_alias",
        "noise",
    }
)
ALLOWED_WEIGHTS = frozenset({0.25, 0.5, 1.0})


SCHEMA_DESCRIPTION = """\
Tu es un assistant d'annotation éditoriale pour Facteur, une app qui met en
regard plusieurs titres de presse couvrant la même actualité. Ta tâche : pour
chaque titre "alt" (une perspective parmi plusieurs sur le même évènement),
identifier les fragments qui méritent d'être SURLIGNÉS car ils relèvent d'un
choix éditorial du média, par opposition aux faits avérés.

Tu reçois pour chaque appel :
1. Le titre de référence du cluster (point de comparaison neutre, souvent un
   média grand public).
2. Le titre de la perspective à annoter, avec son `bias_stance`.
3. Quelques autres titres du même cluster (contexte — n'annote PAS ces titres).

Tu retournes UN JSON strict avec cette forme :
{
  "target_spans": [
    {"start": int, "end": int, "text": str, "category": str,
     "weight": float, "justification": str}
  ],
  "exclude_spans": [
    {"start": int, "end": int, "text": str, "category": str}
  ],
  "notes": str,
  "confidence": float
}

Où :
- `target_spans` = fragments à SURLIGNER (l'éditorialisation du média).
  - `category` ∈ {"editorial_angle", "fact", "multi_token_expression",
    "framing_noun", "foreign_lang"}
    - editorial_angle : verbe ou adjectif chargé ("crispe", "écrase",
      "insulte").
    - fact : mot factuel utilisé comme cadrage clivant ("gauche", "droite").
    - multi_token_expression : expression de 2+ mots contiguës ("vent debout",
      "mettre les egos de côté", "nie s'être inspiré"). UN SEUL span couvrant
      toute l'expression.
    - framing_noun : nom abstrait choisi pour cadrer ("mainmise",
      "indépendance", "polémique").
    - foreign_lang : à utiliser quand la perspective n'est pas en français
      (anglais, allemand, italien…) — annote les fragments éditorialisants
      dans la langue d'origine.
  - `weight` ∈ {0.25, 0.5, 1.0} :
    - 0.25 : très légère éditorialisation.
    - 0.5  : cadrage modéré (factuel + nuance assumée).
    - 1.0  : éditorialisation forte (verbes chargés, jeux de mots, synthèses
             partisanes, expressions clivantes).
  - `justification` : 1 phrase courte (max 140 caractères) expliquant pourquoi
    ce fragment a été retenu. Affichée à l'utilisateur final dans un tooltip.
- `exclude_spans` = fragments à NE PAS SURLIGNER même si une pipeline
  mécanique les capturerait. Sans `weight` (binaire).
  - `category` ∈ {"pivot_entity", "neutral_verb", "entity_alias",
    "geographic_alias", "noise"}
    - pivot_entity : entité présente dans la majorité des titres du cluster
      (Trump, Macron, "Banque de France"…).
    - neutral_verb : verbe descriptif sans charge ("annonce", "confirme",
      "désigne", "appelle").
    - entity_alias : nom propre alternatif ("Donald Trump" ⊂ "Trump").
    - geographic_alias : variante d'un lieu.
    - noise : faits secondaires (titres de films, dates, noms de poste).

RÈGLES IMPORTANTES :
- Tes `start`/`end` doivent référer EXACTEMENT à des indices dans le titre
  fourni (codepoints Unicode). Le champ `text` doit être ce que donne
  `titre[start:end]`.
- Si un fragment éditorialisant fait 2+ mots contigus, fais UN span
  `multi_token_expression` couvrant toute l'expression — pas plusieurs.
- Pas de chevauchement entre target_spans et exclude_spans.
- L'absence totale d'éditorialisation est légitime : `target_spans: []` est
  valide pour un titre 100 % factuel.
- `confidence` ∈ [0, 1] : auto-évaluation de la difficulté du cas.
- `notes` : 1 phrase justifiant l'analyse globale du titre (utile au debug).
- Réponds UNIQUEMENT par le JSON, sans markdown, sans préambule.
"""


def _norm(s: str) -> str:
    """Normalise apostrophes typographiques + NBSP pour matching tolérant."""
    return s.replace("’", "'").replace("\xa0", " ")


def find_span(title: str, text: str) -> tuple[int, int] | None:
    """Localise un fragment dans un titre, tolérant aux apostrophes
    typographiques et aux NBSP. Retourne None si introuvable."""
    if not text:
        return None
    idx = title.find(text)
    if idx >= 0:
        return (idx, idx + len(text))
    nt = _norm(title)
    ntxt = _norm(text)
    idx = nt.find(ntxt)
    if idx >= 0:
        return (idx, idx + len(ntxt))
    return None


def _validate_target(raw: object, title: str, index: int) -> dict | None:
    if not isinstance(raw, dict):
        logger.warning("llm_bias.target_drop", reason="not_dict", index=index)
        return None
    text = (raw.get("text") or "").strip()
    category = raw.get("category", "")
    if category not in TARGET_CATEGORIES:
        logger.warning(
            "llm_bias.target_drop",
            reason="bad_category",
            index=index,
            category=category,
        )
        return None
    try:
        weight = float(raw.get("weight", 0))
    except (TypeError, ValueError):
        logger.warning("llm_bias.target_drop", reason="bad_weight_type", index=index)
        return None
    if weight not in ALLOWED_WEIGHTS:
        logger.warning(
            "llm_bias.target_drop",
            reason="bad_weight_value",
            index=index,
            weight=weight,
        )
        return None
    span = find_span(title, text)
    if span is None:
        logger.warning(
            "llm_bias.target_drop",
            reason="span_not_found",
            index=index,
            text=text[:60],
        )
        return None
    justification_raw = raw.get("justification")
    justification = (
        str(justification_raw).strip() if justification_raw else None
    ) or None
    return {
        "start": span[0],
        "end": span[1],
        "text": title[span[0] : span[1]],
        "category": category,
        "weight": weight,
        "justification": justification,
    }


def _validate_exclude(raw: object, title: str, index: int) -> dict | None:
    if not isinstance(raw, dict):
        logger.warning("llm_bias.exclude_drop", reason="not_dict", index=index)
        return None
    text = (raw.get("text") or "").strip()
    category = raw.get("category", "")
    if category not in EXCLUDE_CATEGORIES:
        logger.warning(
            "llm_bias.exclude_drop",
            reason="bad_category",
            index=index,
            category=category,
        )
        return None
    span = find_span(title, text)
    if span is None:
        logger.warning(
            "llm_bias.exclude_drop",
            reason="span_not_found",
            index=index,
            text=text[:60],
        )
        return None
    return {
        "start": span[0],
        "end": span[1],
        "text": title[span[0] : span[1]],
        "category": category,
    }


class LLMBiasAnnotationService:
    """Wrapper offline-only autour de `EditorialLLMClient` pour l'annotation
    fine des biais éditoriaux.

    Le validateur fonctionne en mode tolérant : un span hallucinant ou avec
    catégorie/poids invalide est **dropped + logué**, l'annotation reste
    valide avec les spans restants. Seule une racine non-objet ou un champ
    `target_spans`/`exclude_spans` non-liste invalide la réponse complète
    (retour `None`).
    """

    LLM_VERSION = LLM_VERSION
    DEFAULT_MODEL = DEFAULT_MODEL

    def __init__(
        self,
        client: EditorialLLMClient | None = None,
        model: str = DEFAULT_MODEL,
    ) -> None:
        self._client = client or EditorialLLMClient()
        self._model = model

    @property
    def is_ready(self) -> bool:
        return self._client.is_ready

    @property
    def model(self) -> str:
        return self._model

    async def close(self) -> None:
        await self._client.close()

    def build_system_prompt(self, fewshot_examples: list[str] | None = None) -> str:
        if not fewshot_examples:
            return SCHEMA_DESCRIPTION
        return (
            SCHEMA_DESCRIPTION
            + "\n\n## Exemples calibrés par le PO\n\n"
            + "\n\n".join(fewshot_examples)
        )

    @staticmethod
    def build_user_prompt(
        ref_title: str,
        variant_title: str,
        bias_stance: str,
        peers: list[str] | None = None,
    ) -> str:
        peer_block = ""
        if peers:
            peer_block = (
                "\nAutres titres du cluster (contexte, ne pas annoter) :\n"
                + "\n".join(f"- {t}" for t in peers)
            )
        return (
            f"Titre référence : {ref_title}\n"
            f"Titre perspective (bias = {bias_stance}) : {variant_title}"
            f"{peer_block}\n\n"
            "Annote la perspective. Retourne le JSON strict."
        )

    @staticmethod
    def validate_response(payload: object, title: str) -> dict | None:
        """Valide la réponse LLM contre le schéma v2.

        - Retourne `None` si la racine est non-dict ou si target/exclude_spans
          ne sont pas des listes.
        - Sinon retourne un dict normalisé. Les spans invalides individuels
          sont droppés + logués (graceful degradation).
        """
        if not isinstance(payload, dict):
            logger.warning("llm_bias.invalid_root", got=type(payload).__name__)
            return None

        targets_raw = payload.get("target_spans", [])
        excludes_raw = payload.get("exclude_spans", [])
        if not isinstance(targets_raw, list) or not isinstance(excludes_raw, list):
            logger.warning("llm_bias.invalid_spans_field")
            return None

        cleaned_targets: list[dict] = []
        for i, raw in enumerate(targets_raw):
            t = _validate_target(raw, title, i)
            if t is not None:
                cleaned_targets.append(t)

        cleaned_excludes: list[dict] = []
        for i, raw in enumerate(excludes_raw):
            e = _validate_exclude(raw, title, i)
            if e is not None:
                cleaned_excludes.append(e)

        confidence_raw = payload.get("confidence")
        confidence: float | None
        try:
            confidence = float(confidence_raw) if confidence_raw is not None else None
        except (TypeError, ValueError):
            confidence = None

        return {
            "target_spans": cleaned_targets,
            "exclude_spans": cleaned_excludes,
            "notes": str(payload.get("notes", "")),
            "confidence": confidence,
        }

    async def annotate_variant(
        self,
        ref_title: str,
        variant_title: str,
        bias_stance: str,
        peers: list[str] | None = None,
        fewshot_examples: list[str] | None = None,
    ) -> dict | None:
        """Annote un variant unique.

        Retourne le dict validé ou `None` si la racine de la réponse LLM est
        invalide (pas de retry interne — la stratégie de retry est portée par
        l'appelant, ex. script calibration en PR 2 ou pipeline en PR 4).
        """
        system = self.build_system_prompt(fewshot_examples)
        user = self.build_user_prompt(
            ref_title=ref_title,
            variant_title=variant_title,
            bias_stance=bias_stance,
            peers=peers,
        )
        raw = await self._client.chat_json(
            system=system,
            user_message=user,
            model=self._model,
            temperature=0.1,
            max_tokens=1500,
        )
        if raw is None:
            logger.warning(
                "llm_bias.no_response",
                variant_preview=variant_title[:60],
            )
            return None
        return self.validate_response(raw, variant_title)
