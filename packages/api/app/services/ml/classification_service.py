"""
ClassificationService: LLM-based topic classification via Mistral API.

Replaces the previous mDeBERTa zero-shot model with a fast, cheap API call.
Benefits: ~3000+ articles/hour (vs ~150), better quality (contextual), no local RAM.
"""

from __future__ import annotations

import json

import httpx
import structlog

from app.config import get_settings

log = structlog.get_logger()


# 50 topic slugs in the Facteur taxonomy
VALID_TOPIC_SLUGS: set[str] = {
    # Tech & Science
    "ai",
    "tech",
    "cybersecurity",
    "gaming",
    "space",
    "science",
    "privacy",
    # Société
    "politics",
    "economy",
    "work",
    "education",
    "health",
    "justice",
    "immigration",
    "inequality",
    "feminism",
    "lgbtq",
    "religion",
    # Environnement
    "climate",
    "environment",
    "energy",
    "biodiversity",
    "agriculture",
    "food",
    # Culture
    "cinema",
    "music",
    "literature",
    "art",
    "media",
    "fashion",
    "design",
    # Lifestyle
    "travel",
    "gastronomy",
    "sport",
    "wellness",
    "family",
    "relationships",
    # Business
    "startups",
    "finance",
    "realestate",
    "entrepreneurship",
    "marketing",
    # International
    "geopolitics",
    "europe",
    "usa",
    "africa",
    "asia",
    "middleeast",
    # Autres
    "history",
    "philosophy",
    "factcheck",
}

# Slug -> French label for the LLM prompt
SLUG_TO_LABEL: dict[str, str] = {
    "ai": "Intelligence artificielle",
    "tech": "Technologie",
    "cybersecurity": "Cybersécurité",
    "gaming": "Jeux vidéo",
    "space": "Espace et astronomie",
    "science": "Science",
    "privacy": "Données et vie privée",
    "politics": "Politique",
    "economy": "Économie",
    "work": "Emploi et travail",
    "education": "Éducation",
    "health": "Santé",
    "justice": "Justice et droit",
    "immigration": "Immigration",
    "inequality": "Inégalités sociales",
    "feminism": "Féminisme et droits des femmes",
    "lgbtq": "LGBTQ+",
    "religion": "Religion",
    "climate": "Climat",
    "environment": "Environnement",
    "energy": "Énergie",
    "biodiversity": "Biodiversité",
    "agriculture": "Agriculture",
    "food": "Alimentation",
    "cinema": "Cinéma",
    "music": "Musique",
    "literature": "Littérature",
    "art": "Art",
    "media": "Médias",
    "fashion": "Mode",
    "design": "Design",
    "travel": "Voyage",
    "gastronomy": "Gastronomie",
    "sport": "Sport",
    "wellness": "Bien-être",
    "family": "Famille et parentalité",
    "relationships": "Relations et amour",
    "startups": "Startups",
    "finance": "Finance",
    "realestate": "Immobilier",
    "entrepreneurship": "Entrepreneuriat",
    "marketing": "Marketing",
    "geopolitics": "Géopolitique",
    "europe": "Europe",
    "usa": "États-Unis",
    "africa": "Afrique",
    "asia": "Asie",
    "middleeast": "Moyen-Orient",
    "history": "Histoire",
    "philosophy": "Philosophie",
    "factcheck": "Fact-checking",
}

# Build the topic list for the prompt (sorted for consistency)
_TOPIC_LIST_FOR_PROMPT = "\n".join(
    f"- {slug}: {label}" for slug, label in sorted(SLUG_TO_LABEL.items())
)

CLASSIFICATION_SYSTEM_PROMPT = f"""Tu es un classificateur d'articles de presse francophone.

Pour chaque article, tu dois assigner 1 à 3 topics parmi cette liste prédéfinie (utilise UNIQUEMENT les slugs) :

{_TOPIC_LIST_FOR_PROMPT}

Règles :
- Retourne UNIQUEMENT les slugs, séparés par des virgules (ex: "politics, economy, europe")
- Maximum 3 topics par article
- Choisis les topics les plus spécifiques et pertinents
- Le premier topic doit être le plus pertinent
- Ne retourne JAMAIS un slug qui n'est pas dans la liste ci-dessus
- Réponds UNIQUEMENT avec les slugs, rien d'autre"""

MISTRAL_API_URL = "https://api.mistral.ai/v1/chat/completions"


class ClassificationService:
    """
    Service de classification d'articles via l'API Mistral.

    Classifie les articles dans la taxonomie 50-topics en utilisant
    un modèle LLM léger et rapide (mistral-small-latest).
    """

    def __init__(self) -> None:
        settings = get_settings()
        self._api_key = settings.mistral_api_key
        self._ready = bool(self._api_key)
        self._client: httpx.AsyncClient | None = None

        if not self._ready:
            log.warning(
                "classification_service.no_api_key",
                message="MISTRAL_API_KEY not set. Classification will be unavailable.",
            )
        else:
            log.info("classification_service.initialized", model="mistral-small-latest")

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

    async def classify_async(
        self,
        title: str,
        description: str = "",
        top_k: int = 3,
    ) -> list[str]:
        """
        Classifie un article basé sur son titre et sa description via Mistral API.

        Args:
            title: Titre de l'article
            description: Description/résumé optionnel
            top_k: Nombre maximum de topics à retourner

        Returns:
            Liste des slugs de topics (ex: ['ai', 'tech', 'startups'])
        """
        if not self._ready:
            return []

        text = f"{title}. {description}".strip() if description else title
        if not text:
            return []

        try:
            client = self._get_client()
            response = await client.post(
                MISTRAL_API_URL,
                json={
                    "model": "mistral-small-latest",
                    "messages": [
                        {"role": "system", "content": CLASSIFICATION_SYSTEM_PROMPT},
                        {"role": "user", "content": text},
                    ],
                    "temperature": 0.0,
                    "max_tokens": 50,
                },
            )
            response.raise_for_status()
            data = response.json()

            choices = data.get("choices") or []
            if not choices:
                log.warning("classification_service.empty_choices", title=title[:100])
                return []
            raw_answer = (choices[0].get("message") or {}).get("content") or ""
            raw_answer = raw_answer.strip()
            if not raw_answer:
                log.warning("classification_service.empty_content", title=title[:100])
                return []

            topics = self._parse_topics(raw_answer, top_k)

            log.debug(
                "classification_service.classified",
                text=text[:100],
                raw=raw_answer,
                topics=topics,
            )

            return topics

        except Exception as e:
            log.error(
                "classification_service.classify_error", error=str(e), title=title[:100]
            )
            return []

    async def classify_batch_async(
        self,
        items: list[dict],
        top_k: int = 3,
    ) -> list[list[str]]:
        """
        Classifie un batch d'articles en un seul appel API.

        Args:
            items: Liste de dicts avec 'title' et 'description'
            top_k: Nombre maximum de topics par article

        Returns:
            Liste de listes de slugs (même ordre que items)
        """
        if not self._ready or not items:
            return [[] for _ in items]

        # Build batch prompt
        articles_text = "\n\n".join(
            f"[Article {i + 1}]\n{item['title']}. {item.get('description', '')}"
            for i, item in enumerate(items)
        )

        batch_prompt = (
            f"Classifie chacun de ces {len(items)} articles. "
            "Réponds en JSON array, un élément par article, chaque élément étant "
            'un array de slugs. Exemple pour 2 articles: [["politics", "europe"], ["ai", "tech"]]\n\n'
            f"{articles_text}"
        )

        try:
            client = self._get_client()
            response = await client.post(
                MISTRAL_API_URL,
                json={
                    "model": "mistral-small-latest",
                    "messages": [
                        {"role": "system", "content": CLASSIFICATION_SYSTEM_PROMPT},
                        {"role": "user", "content": batch_prompt},
                    ],
                    "temperature": 0.0,
                    "max_tokens": 30 * len(items),
                },
            )
            response.raise_for_status()
            data = response.json()

            choices = data.get("choices") or []
            if not choices:
                log.warning(
                    "classification_service.batch_empty_choices", count=len(items)
                )
                return [[] for _ in items]
            raw_answer = (choices[0].get("message") or {}).get("content") or ""
            raw_answer = raw_answer.strip()
            if not raw_answer:
                log.warning(
                    "classification_service.batch_empty_content", count=len(items)
                )
                return [[] for _ in items]

            results = self._parse_batch_response(raw_answer, len(items), top_k)

            log.info(
                "classification_service.batch_classified",
                count=len(items),
                successful=sum(1 for r in results if r),
            )

            return results

        except Exception as e:
            log.error(
                "classification_service.batch_error", error=str(e), count=len(items)
            )
            return [[] for _ in items]

    def _parse_topics(self, raw: str, top_k: int) -> list[str]:
        """Parse la réponse du LLM en liste de slugs validés."""
        # Clean up common LLM artifacts
        raw = raw.strip().strip('"').strip("'").strip("`")

        slugs = [s.strip().lower() for s in raw.split(",")]
        valid = [s for s in slugs if s in VALID_TOPIC_SLUGS]
        return valid[:top_k]

    def _parse_batch_response(
        self, raw: str, expected_count: int, top_k: int
    ) -> list[list[str]]:
        """Parse la réponse batch du LLM (JSON array of arrays)."""
        try:
            # Try JSON parse first
            parsed = json.loads(raw)
            if isinstance(parsed, list) and len(parsed) == expected_count:
                results = []
                for item in parsed:
                    if isinstance(item, list):
                        valid = [
                            s.strip().lower()
                            for s in item
                            if isinstance(s, str)
                            and s.strip().lower() in VALID_TOPIC_SLUGS
                        ]
                        results.append(valid[:top_k])
                    else:
                        results.append([])
                return results
        except (json.JSONDecodeError, TypeError):
            pass

        # Fallback: try line-by-line parsing
        log.warning("classification_service.batch_parse_fallback", raw=raw[:200])
        lines = [line.strip() for line in raw.strip().split("\n") if line.strip()]
        results = []
        for line in lines[:expected_count]:
            clean = line.strip("[]").strip()
            slugs = [s.strip().strip('"').strip("'").lower() for s in clean.split(",")]
            valid = [s for s in slugs if s in VALID_TOPIC_SLUGS]
            results.append(valid[:top_k])

        while len(results) < expected_count:
            results.append([])

        return results

    def is_ready(self) -> bool:
        """Retourne True si le service est configuré et prêt."""
        return self._ready

    async def close(self) -> None:
        """Close the HTTP client."""
        if self._client:
            await self._client.aclose()
            self._client = None


# Singleton instance (lazy-loaded)
_classification_service: ClassificationService | None = None


def get_classification_service() -> ClassificationService:
    """Retourne l'instance singleton du service de classification."""
    global _classification_service
    if _classification_service is None:
        _classification_service = ClassificationService()
    return _classification_service
