"""Classifieur dédié `is_good_news` (passe 2 du pipeline).

La passe 1 (`ClassificationService` / mistral-small-latest) classifie
topics + serene + entities en batch sur tous les articles. Cette passe 2
prend uniquement les survivants `serene=true` issus de sources francophones
et leur applique un prompt strict sur `mistral-large-latest` pour décider
si l'article est une vraie « bonne nouvelle » au sens du PO.

Pourquoi un service séparé ?
- mistral-small a montré 32 % de précision sur l'audit PO du 10/05/2026.
- Le coût d'un appel large reste maîtrisé : ~10 % des articles passent le
  gate (serene=true ∧ source FR).
- La séparation permet d'itérer sur le prompt sans toucher la passe 1.
"""

from __future__ import annotations

import asyncio
import json

import httpx
import structlog

from app.config import get_settings
from app.services.ml.classification_service import _clean_text
from app.services.observability.usage_recorder import track_api_call

log = structlog.get_logger()

GOOD_NEWS_MODEL = "mistral-large-latest"
MISTRAL_API_URL = "https://api.mistral.ai/v1/chat/completions"


_SYSTEM_PROMPT = """Tu es un éditeur expérimenté chargé de sélectionner les "vraies" bonnes nouvelles pour un digest quotidien apaisant.

Tu réponds STRICTEMENT en JSON, sans texte autour.

## RÈGLE D'OR
En cas de doute, réponds false. On préfère manquer une bonne nouvelle plutôt qu'en signaler une fausse.

## VRAIES BONNES NOUVELLES (true)

Une bonne nouvelle DOIT cocher AU MOINS l'une de ces 5 cases :

1. **Progrès tangible avec application humaine claire** : avancée scientifique, médicale, sociale, environnementale ou éducative qui se traduit en bénéfice concret et démontré pour des humains, des animaux ou un écosystème.
2. **Accalmie d'un conflit ou d'une actualité stressante** : trêve, désescalade, accord de paix, libération d'otages, fin d'une crise sanitaire ou sociale.
3. **Réparation / reconnaissance historique** : indemnisation des victimes, reconnaissance d'un crime d'État, restitution, geste qui apaise une douleur collective.
4. **Avancée structurelle sur la transition écologique ou un enjeu social majeur** : législation contraignante actée, financement débloqué, infrastructure mise en service.
5. **Émancipation** : avancée mesurable des droits des femmes, de minorités opprimées, du bien-être animal.

## ANTI-PATTERNS (toujours false)

- Mort, deuil, tragédie même teintée d'un final positif (ex. "miracle après une mort").
- Découverte / exploit / record SANS application humaine immédiate démontrée.
- Reportage rétrospectif ("le jour où…", anniversaire, hommage).
- IA frontier, modèles ultra-puissants, chatbot émotionnel : anxiogènes par nature.
- Salaire / pension qui "suit l'inflation" : ne pas perdre ≠ gagner.
- Élitisme ou personnalité people qui "se fait plaisir" en aidant.
- Anecdotique, fait divers, curiosité légère, animal mignon.
- Sortie commerciale (jeu vidéo, produit, console) sauf souveraineté ou bénéfice humain direct évident.
- Personnalité culturelle (anniversaire, hommage, biographie).
- Tourisme, loisirs, sport (résultats de match, exploit sportif).
- Article principalement en anglais, quel que soit le sujet.
- Initiative limitée à une poignée d'individus sans portée plus large.

## FORMAT
Réponds en JSON array, exactement N éléments pour N articles.
Chaque élément : {"good_news": true|false}
Exemple pour 2 articles : [{"good_news": true}, {"good_news": false}]"""


def _build_user_prompt(items: list[dict]) -> str:
    """Construit le prompt utilisateur pour le batch."""
    parts = []
    for i, item in enumerate(items):
        title = _clean_text(item.get("title", ""))
        desc = _clean_text(item.get("description", "") or "")
        if len(desc) > 240:
            desc = desc[:240] + "..."
        source_name = item.get("source_name", "")

        header = f"[{i + 1}]"
        if source_name:
            header += f" [Source: {source_name}]"

        text = f"{title}. {desc}".strip() if desc else title
        parts.append(f"{header}\n{text}")

    articles_text = "\n\n".join(parts)
    return (
        f"Évalue chacun de ces {len(items)} articles selon les règles ci-dessus.\n"
        f"Réponds en JSON array de exactement {len(items)} éléments, "
        'chacun {"good_news": true|false}.\n\n'
        f"{articles_text}"
    )


def _parse_response(raw: str, expected_count: int) -> list[bool | None]:
    """Parse la réponse JSON. Renvoie liste de bool | None de longueur expected_count."""
    out: list[bool | None] = [None] * expected_count
    try:
        parsed = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        log.warning("good_news_classifier.parse_failed", raw=raw[:200])
        return out

    if not isinstance(parsed, list):
        log.warning("good_news_classifier.unexpected_shape", raw=raw[:200])
        return out

    for i, item in enumerate(parsed[:expected_count]):
        if isinstance(item, dict):
            value = item.get("good_news")
        elif isinstance(item, bool):
            value = item
        else:
            value = None
        if isinstance(value, bool):
            out[i] = value
    return out


class GoodNewsClassifier:
    """Service de classification `is_good_news` (passe 2, mistral-large)."""

    def __init__(self) -> None:
        settings = get_settings()
        self._api_key = settings.mistral_api_key
        self._ready = bool(self._api_key)
        self._client: httpx.AsyncClient | None = None

        if self._ready:
            log.info("good_news_classifier.initialized", model=GOOD_NEWS_MODEL)
        else:
            log.warning(
                "good_news_classifier.no_api_key",
                message="MISTRAL_API_KEY not set. Good-news pass disabled.",
            )

    def is_ready(self) -> bool:
        return self._ready

    def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=30.0,
                headers={
                    "Authorization": f"Bearer {self._api_key}",
                    "Content-Type": "application/json",
                },
            )
        return self._client

    async def _call(self, payload: dict, *, max_retries: int = 3) -> dict | None:
        client = self._get_client()
        async with track_api_call(
            "mistral", "good_news_pass2", model=payload.get("model")
        ) as _call:
            for attempt in range(max_retries):
                try:
                    response = await client.post(MISTRAL_API_URL, json=payload)
                    response.raise_for_status()
                    _call.status = "ok"
                    return response.json()
                except httpx.HTTPStatusError as e:
                    status = e.response.status_code
                    if status == 429 and attempt < max_retries - 1:
                        _call.status = "rate_limited"
                        delay = 2**attempt
                        log.warning(
                            "good_news_classifier.rate_limited",
                            attempt=attempt,
                            delay=delay,
                        )
                        await asyncio.sleep(delay)
                        continue
                    if status == 429:
                        _call.status = "rate_limited"
                    log.error(
                        "good_news_classifier.http_error",
                        status_code=status,
                        body=e.response.text[:300],
                    )
                    return None
                except httpx.TimeoutException:
                    log.error("good_news_classifier.timeout", attempt=attempt)
                    return None
                except json.JSONDecodeError as e:
                    log.error("good_news_classifier.json_error", error=str(e))
                    return None
                except Exception as e:
                    log.error("good_news_classifier.unexpected", error=str(e))
                    return None
            return None

    async def classify_batch_async(self, items: list[dict]) -> list[bool | None]:
        """Classifie un batch d'articles. Renvoie une liste alignée sur `items`.

        Args:
            items: liste de dicts {title, description, source_name}.

        Returns:
            Liste `[True | False | None]` de même longueur que `items`.
            None signifie "le modèle n'a pas répondu de manière exploitable".
        """
        if not items:
            return []
        if not self._ready:
            return [None] * len(items)

        payload = {
            "model": GOOD_NEWS_MODEL,
            "messages": [
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": _build_user_prompt(items)},
            ],
            "temperature": 0.1,
            "response_format": {"type": "json_object"},
            "max_tokens": 32 * len(items) + 64,
        }

        data = await self._call(payload)
        if not data:
            return [None] * len(items)

        try:
            content = data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            log.error("good_news_classifier.malformed_response")
            return [None] * len(items)

        return _parse_response(content, expected_count=len(items))

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None


_singleton: GoodNewsClassifier | None = None


def get_good_news_classifier() -> GoodNewsClassifier:
    """Retourne l'instance singleton du classifieur good-news."""
    global _singleton
    if _singleton is None:
        _singleton = GoodNewsClassifier()
    return _singleton
