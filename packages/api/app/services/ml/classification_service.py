"""
ClassificationService: LLM-based topic classification via Mistral API.

Replaces the previous mDeBERTa zero-shot model with a fast, cheap API call.
Benefits: ~3000+ articles/hour (vs ~150), better quality (contextual), no local RAM.
"""

from __future__ import annotations

import json
from collections import Counter

import httpx
import structlog

from app.config import get_settings

log = structlog.get_logger()


# 51 topic slugs in the Facteur taxonomy
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

# Slug -> French label (used by topic_selector, custom_topics, topic_enrichment)
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

CLASSIFICATION_SYSTEM_PROMPT = """\
Tu es un classificateur expert d'articles de presse francophone.

## TACHE
Pour chaque article, assigne 1 à 3 topics depuis la taxonomie ci-dessous.
Utilise UNIQUEMENT les slugs anglais. Choisis le topic le PLUS SPECIFIQUE possible.

## TAXONOMIE (51 topics groupés par thème)

### Tech & Science
- ai: Intelligence artificielle, machine learning, ChatGPT, LLM — PAS la tech en général
- tech: Technologie, smartphones, apps, gadgets — PAS l'IA spécifiquement
- cybersecurity: Hacking, ransomware, failles de sécurité
- gaming: Jeux vidéo, consoles, esport
- space: Espace, astronomie, NASA, fusées
- science: Recherche scientifique, découvertes, biologie, physique — PAS le climat
- privacy: RGPD, surveillance, vie privée numérique

### Société
- politics: Politique intérieure française, lois, partis — PAS relations internationales
- economy: Macroéconomie, PIB, inflation, chômage — PAS finance perso ni startups
- work: Emploi, télétravail, grèves, droit du travail
- education: École, université, formation, Parcoursup
- health: Santé publique, maladies, hôpitaux, médicaments, santé mentale
- justice: Procès, tribunaux, police, droits fondamentaux
- immigration: Immigration, migrants, réfugiés, politique migratoire — UNIQUEMENT si le sujet EST l'immigration
- inequality: Inégalités sociales, pauvreté, précarité
- feminism: Féminisme, égalité femmes-hommes, violences sexistes
- lgbtq: Droits LGBTQ+, Pride, transidentité
- religion: Religion, laïcité, spiritualité

### Environnement
- climate: Réchauffement climatique, CO2, GIEC — LE CLIMAT spécifiquement
- environment: Pollution, déchets, écologie — PAS le climat spécifiquement
- energy: Nucléaire, renouvelables, pétrole, transition énergétique
- biodiversity: Espèces menacées, déforestation, écosystèmes
- agriculture: Agriculture, PAC, pesticides, élevage
- food: Alimentation, nutrition, sécurité alimentaire

### Culture
- cinema: Films, séries TV, Netflix, streaming vidéo, festivals
- music: Artistes, concerts, albums
- literature: Livres, romans, BD, manga
- art: Art contemporain, expositions, musées
- media: Journalisme, presse, audiovisuel, podcasts
- fashion: Mode, haute couture, luxe
- design: Design, architecture, urbanisme

### Lifestyle
- travel: Voyage, tourisme, destinations
- gastronomy: Restaurants, chefs, recettes, vin
- sport: TOUT le sport (football, JO, tennis, rugby, etc.)
- wellness: Bien-être, méditation, yoga
- family: Parentalité, enfants, natalité
- relationships: Couple, rencontres, sexualité

### Business
- startups: Startups, levées de fonds, French Tech — PAS l'économie générale
- finance: Bourse, investissement, crypto, épargne, banques
- realestate: Immobilier, loyers, construction
- entrepreneurship: Création d'entreprise, PME, management
- marketing: Publicité, réseaux sociaux, influence

### International (UNIQUEMENT quand la dimension internationale EST le sujet principal)
- geopolitics: Conflits entre nations, guerres, diplomatie, ONU, OTAN — PAS un article qui mentionne un pays
- europe: Union européenne, institutions EU, Brexit
- usa: Politique/société américaine
- africa: Actualité du continent africain
- asia: Chine, Japon, Inde, Corée
- middleeast: Israël-Palestine, Iran, Arabie saoudite

### Autres
- history: Histoire, commémorations, patrimoine
- philosophy: Philosophie, éthique, débats d'idées
- factcheck: Fact-checking, désinformation, fake news

## SÉRÉNITÉ
Pour chaque article, détermine "serene": true ou false.
serene = true : sujet positif, neutre, culturel, scientifique, lifestyle, divertissement.
serene = false : violence, guerre, attentat, meurtre, catastrophe, crise grave, agression, mort.
En cas de doute, marque false.

## RÈGLES CRITIQUES
1. Article sur un produit tech (Samsung, iPhone) → "tech" PAS "asia"/"geopolitics"
2. Article sur une série/film → "cinema" PAS "ai"/"tech"
3. Article sur un sportif → "sport" PAS son pays d'origine
4. Article médical → "health" PAS "science"
5. "geopolitics" = UNIQUEMENT conflits/diplomatie entre nations
6. Le nom de la source est un indice (L'Équipe → sport) mais le CONTENU prime
7. Assigne 2-3 topics si l'article couvre clairement plusieurs sujets
8. Le premier topic est le PLUS pertinent

## FORMAT
Réponds en JSON array. Chaque élément : {"topics": ["slug1", "slug2"], "serene": true/false}
Pas de texte avant ou après."""

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
        source_name: str = "",
        top_k: int = 3,
    ) -> dict:
        """
        Classifie un article basé sur son titre et sa description via Mistral API.

        Returns:
            Dict avec 'topics' (list[str]) et 'serene' (bool | None)
        """
        if not self._ready:
            return {"topics": [], "serene": None}

        text = f"{title}. {description}".strip() if description else title
        if not text:
            return {"topics": [], "serene": None}

        if source_name:
            text = f"[Source: {source_name}] {text}"

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
                    "max_tokens": 100,
                },
            )
            response.raise_for_status()
            data = response.json()

            choices = data.get("choices") or []
            if not choices:
                log.warning("classification_service.empty_choices", title=title[:100])
                return {"topics": [], "serene": None}
            raw_answer = (choices[0].get("message") or {}).get("content") or ""
            raw_answer = raw_answer.strip()
            if not raw_answer:
                log.warning("classification_service.empty_content", title=title[:100])
                return {"topics": [], "serene": None}

            result = self._parse_topics(raw_answer, top_k)

            log.debug(
                "classification_service.classified",
                text=text[:100],
                raw=raw_answer,
                topics=result.get("topics"),
                serene=result.get("serene"),
            )

            return result

        except Exception as e:
            log.error(
                "classification_service.classify_error", error=str(e), title=title[:100]
            )
            return {"topics": [], "serene": None}

    async def classify_batch_async(
        self,
        items: list[dict],
        top_k: int = 3,
    ) -> list[dict]:
        """
        Classifie un batch d'articles en un seul appel API.

        Args:
            items: Liste de dicts avec 'title', 'description', et optionnel 'source_name'
            top_k: Nombre maximum de topics par article

        Returns:
            Liste de dicts avec 'topics' (list[str]) et 'serene' (bool | None)
        """
        empty_results = [{"topics": [], "serene": None} for _ in items]
        if not self._ready or not items:
            return empty_results

        batch_prompt = self._build_batch_prompt(items)

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
                    "max_tokens": 60 * len(items),
                },
            )
            response.raise_for_status()
            data = response.json()

            choices = data.get("choices") or []
            if not choices:
                log.warning(
                    "classification_service.batch_empty_choices", count=len(items)
                )
                return empty_results
            raw_answer = (choices[0].get("message") or {}).get("content") or ""
            raw_answer = raw_answer.strip()
            if not raw_answer:
                log.warning(
                    "classification_service.batch_empty_content", count=len(items)
                )
                return empty_results

            results = self._parse_batch_response(raw_answer, len(items), top_k)

            self._check_distribution(results)

            log.info(
                "classification_service.batch_classified",
                count=len(items),
                successful=sum(1 for r in results if r.get("topics")),
            )

            return results

        except Exception as e:
            log.error(
                "classification_service.batch_error", error=str(e), count=len(items)
            )
            return empty_results

    def _build_batch_prompt(self, items: list[dict]) -> str:
        """Build the user prompt for batch classification."""
        parts = []
        for i, item in enumerate(items):
            title = item.get("title", "")
            desc = item.get("description", "") or ""
            if len(desc) > 200:
                desc = desc[:200] + "..."
            source_name = item.get("source_name", "")

            header = f"[{i + 1}]"
            if source_name:
                header += f" [Source: {source_name}]"

            text = f"{title}. {desc}".strip() if desc else title
            parts.append(f"{header}\n{text}")

        articles_text = "\n\n".join(parts)

        return (
            f"Classifie chacun de ces {len(items)} articles.\n"
            f"Réponds en JSON array de exactement {len(items)} éléments.\n"
            'Exemple pour 2 articles: [{"topics": ["politics", "europe"], "serene": false}, '
            '{"topics": ["ai", "tech"], "serene": true}]\n\n'
            f"{articles_text}"
        )

    def _parse_topics(self, raw: str, top_k: int) -> dict:
        """Parse la réponse du LLM pour un article unique. Retourne dict avec topics et serene."""
        raw = raw.strip()

        # Try JSON parse first (new format: single object or array with one element)
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict) and "topics" in parsed:
                topics = [
                    s.strip().lower()
                    for s in parsed["topics"]
                    if isinstance(s, str) and s.strip().lower() in VALID_TOPIC_SLUGS
                ]
                serene = parsed.get("serene")
                if not isinstance(serene, bool):
                    serene = None
                return {"topics": topics[:top_k], "serene": serene}
            if (
                isinstance(parsed, list)
                and len(parsed) == 1
                and isinstance(parsed[0], dict)
            ):
                item = parsed[0]
                topics = [
                    s.strip().lower()
                    for s in item.get("topics", [])
                    if isinstance(s, str) and s.strip().lower() in VALID_TOPIC_SLUGS
                ]
                serene = item.get("serene")
                if not isinstance(serene, bool):
                    serene = None
                return {"topics": topics[:top_k], "serene": serene}
        except (json.JSONDecodeError, TypeError):
            pass

        # Fallback: comma-separated slugs (old format)
        clean = raw.strip('"').strip("'").strip("`")
        slugs = [s.strip().lower() for s in clean.split(",")]
        valid = [s for s in slugs if s in VALID_TOPIC_SLUGS]
        return {"topics": valid[:top_k], "serene": None}

    def _parse_batch_response(
        self, raw: str, expected_count: int, top_k: int
    ) -> list[dict]:
        """Parse la réponse batch du LLM (JSON array of objects)."""
        empty_results = [{"topics": [], "serene": None} for _ in range(expected_count)]

        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                # Check count mismatch
                if len(parsed) != expected_count:
                    log.warning(
                        "classification_service.batch_count_mismatch",
                        expected=expected_count,
                        got=len(parsed),
                        raw=raw[:200],
                    )
                    return empty_results

                # New format: array of objects with "topics" and "serene"
                if parsed and isinstance(parsed[0], dict):
                    results = []
                    for item in parsed:
                        if isinstance(item, dict) and "topics" in item:
                            topics = [
                                s.strip().lower()
                                for s in item["topics"]
                                if isinstance(s, str)
                                and s.strip().lower() in VALID_TOPIC_SLUGS
                            ]
                            serene = item.get("serene")
                            if not isinstance(serene, bool):
                                serene = None
                            results.append({"topics": topics[:top_k], "serene": serene})
                        else:
                            results.append({"topics": [], "serene": None})
                    return results

                # Fallback: old format (array of arrays), treat serene as None
                if parsed and isinstance(parsed[0], list):
                    log.info("classification_service.batch_old_format_fallback")
                    results = []
                    for item in parsed:
                        if isinstance(item, list):
                            valid = [
                                s.strip().lower()
                                for s in item
                                if isinstance(s, str)
                                and s.strip().lower() in VALID_TOPIC_SLUGS
                            ]
                            results.append({"topics": valid[:top_k], "serene": None})
                        else:
                            results.append({"topics": [], "serene": None})
                    return results

        except (json.JSONDecodeError, TypeError):
            pass

        # Fallback: line-by-line parsing
        log.warning("classification_service.batch_parse_fallback", raw=raw[:200])
        lines = [line.strip() for line in raw.strip().split("\n") if line.strip()]
        results = []
        for line in lines[:expected_count]:
            clean = line.strip("[]").strip()
            slugs = [s.strip().strip('"').strip("'").lower() for s in clean.split(",")]
            valid = [s for s in slugs if s in VALID_TOPIC_SLUGS]
            results.append({"topics": valid[:top_k], "serene": None})

        while len(results) < expected_count:
            results.append({"topics": [], "serene": None})

        return results

    def _check_distribution(self, results: list[dict]) -> None:
        """Log warning if >50% of batch shares the same primary topic."""
        if len(results) < 2:
            return

        primary_topics = [r["topics"][0] for r in results if r.get("topics")]
        if not primary_topics:
            return

        counts = Counter(primary_topics)
        most_common_topic, most_common_count = counts.most_common(1)[0]

        if most_common_count > len(results) / 2:
            log.warning(
                "classification_service.skewed_distribution",
                topic=most_common_topic,
                count=most_common_count,
                total=len(results),
                ratio=round(most_common_count / len(results), 2),
            )

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
