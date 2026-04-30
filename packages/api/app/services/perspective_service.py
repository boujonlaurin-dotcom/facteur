"""Perspectives service - hybrid search via DB entities + Google News RSS."""

import html
import json
import os
import re
import xml.etree.ElementTree as ET
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from urllib.parse import quote

import certifi
import httpx
import structlog
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.services.text_similarity import jaccard_similarity, normalize_title

logger = structlog.get_logger(__name__)


# --- Post-filtre cohérence sujet (anti-clustering trop large) ---
# Voir docs/bugs/bug-comparison-clustering-too-loose.md
PERSPECTIVE_TITLE_JACCARD_MIN = 0.30
PERSPECTIVE_MIN_VALID_RESULTS = 2
PERSPECTIVE_MIN_BIAS_GROUPS = 2
# Entités jugées suffisamment discriminantes (LOCATION exclu : trop générique)
PERSPECTIVE_DISCRIMINANT_ENTITY_TYPES = frozenset({"PERSON", "ORG", "EVENT"})
# Feature flag (rollback rapide en cas de régression)
PERSPECTIVE_FILTER_ENABLED = (
    os.environ.get("PERSPECTIVE_FILTER_ENABLED", "true").lower() == "true"
)


def _parse_entity_names(
    entities: list[str] | None, types: set[str] | None = None
) -> list[str]:
    """Parse entity JSON strings, return names filtered by type."""
    if not entities:
        return []
    names: list[str] = []
    for raw in entities:
        try:
            obj = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            continue
        if types and obj.get("type") not in types:
            continue
        name = obj.get("name")
        if name:
            names.append(name)
    return names


# User-Agent to avoid being blocked by Google News
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Bias mapping for major French news sources
DOMAIN_BIAS_MAP = {
    # LEFT
    "liberation.fr": "left",
    "mediapart.fr": "left",
    "humanite.fr": "left",
    "politis.fr": "left",
    "lobs.com": "left",
    "lesinrocks.com": "left",
    "bonpote.com": "left",
    "reporterre.net": "left",
    "lareleve.fr": "left",
    "bastamag.net": "left",
    "regards.fr": "left",
    "frontpopulaire.fr": "left",
    # CENTER-LEFT
    "lemonde.fr": "center-left",
    "francetvinfo.fr": "center-left",
    "franceinter.fr": "center-left",
    "franceinfo.fr": "center-left",
    "france3-regions.franceinfo.fr": "center-left",
    "telerama.fr": "center-left",
    "slate.fr": "center-left",
    "france24.com": "center-left",
    "rfi.fr": "center-left",
    "nouvelobs.com": "center-left",
    "marianne.net": "center-left",  # Sovereignist but left-leaning on social issues
    "arte.tv": "center-left",
    "radiofrance.fr": "center-left",
    "philomag.com": "center-left",
    "philosophiemagazine.com": "center-left",
    "linforme.com": "center-left",
    "alternatives-economiques.fr": "center-left",
    "francebleu.fr": "center-left",
    "information.tv5monde.com": "center-left",
    "fr.euronews.com": "center-left",
    "lecanardenchaine.fr": "center-left",
    # CENTER
    "20minutes.fr": "center",
    "ouest-france.fr": "center",
    "sudouest.fr": "center",
    "lavoixdunord.fr": "center",
    "leparisien.fr": "center",
    "huffingtonpost.fr": "center",
    "rtl.fr": "center",
    "courrierinternational.com": "center",
    "legrandcontinent.eu": "center",
    "theconversation.com": "center",
    "tf1info.fr": "center",
    "publicsenat.fr": "center",
    "actu.fr": "center",
    "la-croix.com": "center",
    "vie-publique.fr": "center",
    "ladepeche.fr": "center",
    "midilibre.fr": "center",
    "laprovence.com": "center",
    "larep.fr": "center",
    "objectifgard.com": "center",
    "lequipe.fr": "center",
    "rmcsport.bfmtv.com": "center",
    "lactualite.com": "center",  # Canadian francophone
    "letemps.ch": "center",  # Swiss francophone
    "politico.eu": "center",
    "next.ink": "center",
    "boursorama.com": "center",
    # CENTER-RIGHT
    "lesechos.fr": "center-right",
    "latribune.fr": "center-right",
    "lopinion.fr": "center-right",
    "lexpress.fr": "center-right",
    "lepoint.fr": "center-right",
    "lejdd.fr": "center-right",
    "challenges.fr": "center-right",
    "lci.fr": "center-right",
    "parismatch.com": "center-right",
    "parismatch.fr": "center-right",
    "capital.fr": "center-right",
    "fr.timesofisrael.com": "center-right",
    # RIGHT
    "lefigaro.fr": "right",
    "valeursactuelles.com": "right",
    "atlantico.fr": "right",
    "contrepoints.org": "right",
    "bfmtv.com": "right",  # Pro-business, liberal economics
    "europe1.fr": "center-right",
    "cnews.fr": "right",  # Bolloré-owned, very conservative
}


@dataclass
class Perspective:
    """A perspective from an external source."""

    title: str
    url: str
    source_name: str
    source_domain: str
    bias_stance: str  # left, center-left, center, center-right, right, unknown
    published_at: str | None = None
    description: str | None = None


STANCE_LABELS = {
    "left": "gauche",
    "center-left": "centre-gauche",
    "center": "centre",
    "center-right": "centre-droit",
    "right": "droite",
    "unknown": "inconnu",
}


class PerspectiveService:
    """Service for fetching perspectives via Google News RSS."""

    def __init__(
        self,
        db: AsyncSession | None = None,
        timeout: float = 10.0,
        # Hard cap on perspectives returned by hybrid search. If the digest
        # header consistently shows exactly this number, results are likely
        # truncated — bump this cap or audit upstream filters.
        max_results: int = 10,
        session_maker: async_sessionmaker[AsyncSession] | None = None,
    ):
        # Préférer `session_maker` : chaque requête DB s'exécute dans une
        # session courte, évitant de tenir une connexion pendant les
        # appels Google News / LLM qui dominent le temps du service.
        # Cf. docs/bugs/bug-infinite-load-requests.md (P1).
        self.db = db
        self._session_maker = session_maker
        self.timeout = timeout
        self.max_results = max_results
        # Cache for DB bias lookups within a single request
        self._bias_cache: dict[str, str] = {}

    @asynccontextmanager
    async def _short_session(self):
        """Open a short-lived session, or fall back to self.db."""
        if self._session_maker is None:
            if self.db is None:
                yield None
                return
            yield self.db
            return
        async with self._session_maker() as session:
            try:
                yield session
            except Exception:
                await session.rollback()
                raise

    def _has_db(self) -> bool:
        return self._session_maker is not None or self.db is not None

    async def resolve_bias(self, domain: str, source_name: str | None = None) -> str:
        """Resolve bias for a domain: DOMAIN_BIAS_MAP first, then DB fallback by URL, then by name."""
        # 1. Check hardcoded map (fast)
        bias = DOMAIN_BIAS_MAP.get(domain)
        if bias:
            return bias

        # 2. Check in-memory cache from prior DB lookups
        cache_key = domain or source_name or ""
        if cache_key in self._bias_cache:
            return self._bias_cache[cache_key]

        # 3. DB lookup if session available
        if self._has_db():
            try:
                from app.models.source import Source

                async with self._short_session() as session:
                    if session is None:
                        self._bias_cache[cache_key] = "unknown"
                        return "unknown"

                    # 3a. Try domain match on source URL
                    if domain:
                        stmt = select(Source.bias_stance).where(
                            Source.url.ilike(f"%{domain}%"),
                            Source.is_active.is_(True),
                        )
                        result = await session.execute(stmt)
                        source_bias = result.scalar_one_or_none()

                        if source_bias and source_bias != "unknown":
                            self._bias_cache[cache_key] = source_bias
                            return source_bias

                    # 3b. Fallback: fuzzy match by source name (Google News source name)
                    if source_name and source_name != "Unknown":
                        stmt = select(Source.bias_stance).where(
                            Source.name.ilike(f"%{source_name}%"),
                            Source.is_active.is_(True),
                        )
                        result = await session.execute(stmt)
                        source_bias = result.scalar_one_or_none()

                        if source_bias and source_bias != "unknown":
                            self._bias_cache[cache_key] = source_bias
                            return source_bias
            except Exception as e:
                logger.warning(
                    "resolve_bias_db_error",
                    domain=domain,
                    source_name=source_name,
                    error=str(e),
                )

        self._bias_cache[cache_key] = "unknown"
        return "unknown"

    async def analyze_divergences(
        self,
        article_title: str,
        source_name: str,
        source_bias: str,
        perspectives: list[dict],  # [{title, source_name, bias_stance, description?}]
        article_description: str | None = None,
    ) -> dict | None:
        """Generate a short LLM analysis of editorial divergences.

        Returns a dict with keys:
        - "analysis": str — the editorial divergence text (~150 words)
        - "divergence_level": str — "low", "medium", or "high"
        Or None on failure.
        """
        from app.services.editorial.llm_client import EditorialLLMClient

        if not perspectives:
            return None

        client = EditorialLLMClient()
        if not client.is_ready:
            return None

        perspectives_lines = []
        for p in perspectives:
            stance = STANCE_LABELS.get(
                p.get("bias_stance", "unknown"), p.get("bias_stance", "?")
            )
            line = f'- "{p["title"]}" ({p["source_name"]}, {stance})'
            desc = p.get("description")
            if desc:
                line += f" — {desc[:300]}"
            perspectives_lines.append(line)
        perspectives_text = "\n".join(perspectives_lines)

        system = (
            "Analyste média français. Tu compares la couverture d'un même sujet "
            "par plusieurs rédactions et tu fais ressortir CE QUI LES OPPOSE.\n\n"
            "Méthode obligatoire :\n"
            "1. Lis tous les titres + résumés.\n"
            "2. REGROUPE les médias en 2 à 4 clusters selon l'angle commun qu'ils "
            "adoptent — pas un constat par média, mais un constat par groupe partageant "
            "un même cadrage. Si tous traitent le sujet de la même manière, dis-le "
            "et explique pourquoi (divergence_level: low).\n"
            "3. Pour chaque cluster, identifie : la qualification des faits choisie "
            "(mots forts vs neutres), ce qui est mis en avant ou occulté, et tout "
            "marqueur d'opinion (adjectifs chargés, attribution morale, lexique "
            'révélateur — "dérapage" vs "incident", "renoncement" vs "ajustement", '
            '"victoire" vs "concession").\n\n'
            "Réponds en JSON avec deux clés :\n"
            '- "analysis": texte structuré ainsi :\n'
            "  1. Phrase de contexte : le fait central que tous couvrent (15-25 mots).\n"
            "  2. Saut de ligne double (\\n\\n).\n"
            '  3. 2 à 4 constats, chacun préfixé "→ ", chacun 30-50 mots :\n'
            '     • cluster de médias en **gras** ("**Le Monde** et **Libération**"),\n'
            '     • verbe ou nom-clé d\'angle en **gras** ("**cadrent**", "**minimisent**"),\n'
            "     • un élément concret tiré du titre/résumé (chiffre, acteur, "
            "qualification, mot précis cité entre guillemets si possible),\n"
            "     • si pertinent : marqueur d'opinion repéré "
            '("emploient le terme «X»", "qualifient de Y", "présentent comme Z").\n'
            "  Max 5 segments en gras par ligne. Aucun titre de section.\n"
            '- "divergence_level": "low" (couvertures similaires), "medium" '
            '(angles sensiblement différents), "high" (cadrages opposés ou contradictoires).\n\n'
            "RÈGLES :\n"
            "- Uniquement les titres/résumés fournis. Zéro fait inventé, zéro "
            "intention prêtée à un média sans appui textuel.\n"
            "- Si l'angle d'un cluster repose uniquement sur le titre, ajouter "
            '"d\'après leurs titres".\n'
            "- Verbes concrets : insiste(nt) sur, minimise(nt), cadre(nt) comme, "
            "ignore(nt), met(tent) en avant, oppose(nt), contextualise(nt), "
            "relativise(nt), dramatise(nt), neutralise(nt), qualifie(nt) de, "
            "dénonce(nt), salue(nt).\n"
            '- Interdits : "met en lumière", "soulève des questions", '
            '"révèle la fragilité", "fait écho", "interroge", "questionne".\n'
            "- Ton factuel, phrases denses. Français impeccable.\n\n"
            "EXEMPLE :\n"
            "\"Tous reviennent sur l'annonce du plan budgétaire 2026 présenté par Bercy.\\n\\n"
            "→ **Le Monde** et **Libération** **insistent** sur le volet social, "
            "citant les arbitrages à venir sur les retraites et qualifiant la "
            "trajectoire de «resserrement nécessaire mais douloureux».\\n"
            "→ **Le Figaro** et **Les Échos** **cadrent** la mesure comme un signal "
            "de sérieux budgétaire, mettant en avant les 12 milliards d'économies "
            "et le terme «redressement» dans leurs titres.\\n"
            "→ **Mediapart** **dénonce** un budget «d'austérité déguisée», marqueur "
            "d'opinion explicite absent des autres couvertures.\""
        )

        source_stance = STANCE_LABELS.get(source_bias, source_bias)
        user_message = (
            "Sujet d'actualité couvert par plusieurs médias.\n\n"
            f'Article de référence : "{article_title}" ({source_name}, {source_stance})'
        )
        if article_description:
            user_message += f"\nRésumé : {article_description[:500]}"
        user_message += f"\n\nCouverture par d'autres médias :\n{perspectives_text}"

        try:
            result = await client.chat_json(
                system=system,
                user_message=user_message,
                model="mistral-large-latest",
                temperature=0.4,
                max_tokens=700,
            )
            if isinstance(result, dict) and "analysis" in result:
                return result
            return None
        except Exception as e:
            logger.error("analyze_divergences_error", error=str(e))
            return None
        finally:
            await client.close()

    async def search_perspectives(
        self,
        keywords: list[str],
        exclude_url: str | None = None,
        exclude_title: str | None = None,
        exclude_domain: str | None = None,
    ) -> list[Perspective]:
        """
        Search for perspectives using Google News RSS.

        Args:
            keywords: List of 4-5 keywords from article title for precision
            exclude_url: Optional URL to exclude from results (the source article)
            exclude_title: Optional title to exclude (if similarity is too high)

        Returns:
            List of Perspective objects, max 10
        """
        query = " ".join(keywords)
        encoded_query = quote(query)
        url = f"https://news.google.com/rss/search?q={encoded_query}&hl=fr&gl=FR&ceid=FR:fr"

        logger.info(
            "perspectives_search_start",
            keywords=keywords,
            query=query,
        )

        try:
            headers = {"User-Agent": USER_AGENT}
            async with httpx.AsyncClient(
                timeout=self.timeout,
                verify=certifi.where(),
                headers=headers,
                follow_redirects=True,
            ) as client:
                response = await client.get(url)

                if response.status_code != 200:
                    logger.warning(
                        "perspectives_search_http_error",
                        status_code=response.status_code,
                        keywords=keywords,
                    )
                    return []

                perspectives = await self._parse_rss(
                    response.content, exclude_url, exclude_title, exclude_domain
                )
                logger.info(
                    "perspectives_search_success",
                    keywords=keywords,
                    count=len(perspectives),
                )
                return perspectives

        except httpx.TimeoutException as e:
            logger.error(
                "perspectives_search_timeout",
                keywords=keywords,
                timeout=self.timeout,
                error=str(e),
            )
            return []
        except httpx.RequestError as e:
            logger.error(
                "perspectives_search_request_error",
                keywords=keywords,
                error=str(e),
                error_type=type(e).__name__,
            )
            return []
        except Exception as e:
            logger.error(
                "perspectives_search_unexpected_error",
                keywords=keywords,
                error=str(e),
                error_type=type(e).__name__,
            )
            return []

    @staticmethod
    def _topical_signals(
        seed_tokens: set[str],
        seed_topics: set[str],
        seed_disc_entities: set[str],
        cand_title: str,
        cand_topics: list[str] | None = None,
        cand_entities: list[str] | None = None,
    ) -> dict:
        """Calcule les 3 signaux de cohérence sujet seed↔candidat.

        - title_jaccard: similarité Jaccard sur tokens normalisés (toujours dispo)
        - shared_topics: nb de topics ML partagés (None si cand_topics absent)
        - shared_entities: nb d'entités discriminantes partagées
          (PERSON/ORG/EVENT, None si cand_entities absent)
        """
        cand_tokens = normalize_title(cand_title)
        title_jaccard = jaccard_similarity(seed_tokens, cand_tokens)

        shared_topics: int | None = None
        if cand_topics is not None:
            cand_topic_set = {t.lower() for t in cand_topics if t}
            shared_topics = len(seed_topics & cand_topic_set)

        shared_entities: int | None = None
        if cand_entities is not None:
            cand_disc = _parse_entity_names(
                cand_entities, types=PERSPECTIVE_DISCRIMINANT_ENTITY_TYPES
            )
            cand_disc_lower = {n.lower() for n in cand_disc}
            seed_disc_lower = {n.lower() for n in seed_disc_entities}
            shared_entities = len(seed_disc_lower & cand_disc_lower)

        return {
            "title_jaccard": title_jaccard,
            "shared_topics": shared_topics,
            "shared_entities": shared_entities,
        }

    @staticmethod
    def _is_topically_coherent(signals: dict) -> tuple[bool, str]:
        """Décide si un candidat est on-topic.

        - Si title_jaccard >= seuil → cohérent (signal fort).
        - Sinon, si signaux complets (Layer 1 DB), accepter aussi sur :
          shared_topics >= 1 OU shared_entities >= 2.
        - Sinon (Layer 2/3 Google News, titre seul) → rejeter.

        Retourne (is_coherent, reason). reason vide si cohérent.
        """
        if signals["title_jaccard"] >= PERSPECTIVE_TITLE_JACCARD_MIN:
            return True, ""
        # Signaux complets disponibles (Layer 1 interne) ?
        full_signals = (
            signals["shared_topics"] is not None
            and signals["shared_entities"] is not None
        )
        if full_signals:
            if signals["shared_topics"] and signals["shared_topics"] >= 1:
                return True, ""
            if signals["shared_entities"] and signals["shared_entities"] >= 2:
                return True, ""
            return False, "no_signal"
        return False, "low_jaccard"

    async def search_internal_perspectives(
        self, content, time_window_hours: int = 72
    ) -> list[Perspective]:
        """Search DB for articles sharing PERSON/ORG entities with the source article."""
        if not self._has_db():
            return []

        entity_names = _parse_entity_names(content.entities, types={"PERSON", "ORG"})
        if not entity_names:
            return []

        # Cap to 3 entities to keep query reasonable
        entity_names = entity_names[:3]

        from app.models.content import Content
        from app.models.source import Source

        cutoff = datetime.now(UTC) - timedelta(hours=time_window_hours)

        # Build OR conditions: entities text array contains entity name
        entity_filters = [
            func.array_to_string(Content.entities, " ").ilike(f"%{name}%")
            for name in entity_names
        ]

        stmt = (
            select(Content)
            .join(Source, Content.source_id == Source.id)
            .where(
                or_(*entity_filters),
                Content.source_id != content.source_id,
                Content.published_at >= cutoff,
                Content.id != content.id,
            )
            .order_by(Content.published_at.desc())
            .limit(self.max_results)
        )

        try:
            async with self._short_session() as session:
                if session is None:
                    return []
                result = await session.execute(stmt)
                rows = result.scalars().all()
        except Exception as e:
            logger.warning("search_internal_perspectives_error", error=str(e))
            return []

        # Pré-calcul des signaux du seed (une seule fois)
        seed_tokens = (
            normalize_title(content.title) if PERSPECTIVE_FILTER_ENABLED else set()
        )
        seed_topics = (
            {t.lower() for t in (content.topics or []) if t}
            if PERSPECTIVE_FILTER_ENABLED
            else set()
        )
        seed_disc_entities = (
            set(
                _parse_entity_names(
                    content.entities, types=PERSPECTIVE_DISCRIMINANT_ENTITY_TYPES
                )
            )
            if PERSPECTIVE_FILTER_ENABLED
            else set()
        )

        perspectives: list[Perspective] = []
        seen_sources: set = set()
        filtered_out = 0
        filter_reasons: list[str] = []

        for row in rows:
            if row.source_id in seen_sources:
                continue
            seen_sources.add(row.source_id)

            # Post-filtre cohérence sujet
            if PERSPECTIVE_FILTER_ENABLED:
                signals = self._topical_signals(
                    seed_tokens,
                    seed_topics,
                    seed_disc_entities,
                    cand_title=row.title or "",
                    cand_topics=row.topics,
                    cand_entities=row.entities,
                )
                is_ok, reason = self._is_topically_coherent(signals)
                if not is_ok:
                    filtered_out += 1
                    filter_reasons.append(reason)
                    continue

            # Extract domain from URL
            domain = self._extract_domain(row.url)
            bias = await self.resolve_bias(domain)

            perspectives.append(
                Perspective(
                    title=row.title,
                    url=row.url,
                    source_name=domain,  # Best we have without eager-loading source
                    source_domain=domain,
                    bias_stance=bias,
                    published_at=row.published_at.isoformat()
                    if row.published_at
                    else None,
                )
            )

        logger.info(
            "search_internal_perspectives_done",
            entity_names=entity_names,
            kept=len(perspectives),
            filtered_out=filtered_out,
            filter_reasons=filter_reasons,
        )
        return perspectives

    def build_entity_query(
        self, entities: list[str] | None, title: str, max_terms: int = 3
    ) -> list[str]:
        """Build Google News query using quoted entities + context words from title."""
        entity_names = _parse_entity_names(entities, types={"PERSON", "ORG", "EVENT"})

        if not entity_names:
            return self.extract_keywords(title)

        # Quote entity names, cap at max_terms
        quoted = [f'"{name}"' for name in entity_names[:max_terms]]

        # Add 1-2 context words from title (non-entity significant words)
        title_keywords = self.extract_keywords(title)
        entity_names_lower = {n.lower() for n in entity_names}
        context_words = [
            kw
            for kw in title_keywords
            if kw.lower() not in entity_names_lower
            and not any(kw.lower() in en.lower() for en in entity_names)
        ][:2]

        return quoted + context_words

    async def build_cluster_perspectives(self, contents: list) -> list[Perspective]:
        """Build Perspective objects from a list of Content (cluster articles).

        One Perspective per unique source_id (caller's ordering preserved —
        pipeline orders by published_at desc so the most-recent article wins
        per outlet). Bias is resolved via ``resolve_bias`` so cluster
        perspectives share the same code path as Google News perspectives.

        Articles without domain AND source_name are skipped: they can't be
        part of a bias spectrum and would pollute logo lookups / dedup with
        empty-string keys.

        Shared between ``editorial/pipeline.py`` and the
        ``/contents/{id}/perspectives`` endpoint so the 3-counter invariant
        from PR #390 holds: header, spectrum bar, and bottom-sheet all
        describe the same merged set (cluster ∪ Google News).
        """
        from urllib.parse import urlparse

        seen_source_ids: set = set()
        result: list[Perspective] = []
        for content in contents:
            source_id = getattr(content, "source_id", None)
            if source_id is not None:
                if source_id in seen_source_ids:
                    continue
                seen_source_ids.add(source_id)

            domain = ""
            source_name = ""
            source = getattr(content, "source", None)
            if source is not None:
                source_name = getattr(source, "name", "") or ""
                source_url = getattr(source, "url", "") or ""
                if isinstance(source_url, str) and source_url:
                    try:
                        parsed = urlparse(source_url)
                        domain = parsed.netloc or ""
                        if domain.startswith("www."):
                            domain = domain[4:]
                    except Exception:
                        domain = ""
            # Fallback: extract from article URL.
            if not domain:
                url = getattr(content, "url", "") or ""
                if isinstance(url, str) and url:
                    try:
                        parsed = urlparse(url)
                        domain = parsed.netloc or ""
                        if domain.startswith("www."):
                            domain = domain[4:]
                    except Exception:
                        domain = ""

            if not domain and not source_name:
                continue

            bias = await self.resolve_bias(domain=domain, source_name=source_name)

            result.append(
                Perspective(
                    title=getattr(content, "title", "") or "",
                    url=getattr(content, "url", "") or "",
                    source_name=source_name or domain,
                    source_domain=domain,
                    bias_stance=bias,
                    published_at=(
                        content.published_at.isoformat()
                        if getattr(content, "published_at", None)
                        else None
                    ),
                    description=getattr(content, "description", None),
                )
            )
        return result

    def _filter_external_perspectives(
        self,
        seed_tokens: set[str],
        candidates: list[Perspective],
    ) -> tuple[list[Perspective], int]:
        """Filtre les perspectives externes (Google News) par Jaccard titre.

        Retourne (kept, filtered_out_count). No-op si filter désactivé.
        """
        if not PERSPECTIVE_FILTER_ENABLED:
            return list(candidates), 0
        kept: list[Perspective] = []
        filtered_out = 0
        for p in candidates:
            sim = jaccard_similarity(seed_tokens, normalize_title(p.title or ""))
            if sim >= PERSPECTIVE_TITLE_JACCARD_MIN:
                kept.append(p)
            else:
                filtered_out += 1
        return kept, filtered_out

    async def get_perspectives_hybrid(
        self, content, exclude_domain: str | None = None
    ) -> tuple[list[Perspective], list[str]]:
        """Hybrid 3-layer search: DB entities → Google News entities → fallback keywords.

        Returns (perspectives, keywords_used).

        Toutes les couches passent par un post-filtre de cohérence sujet pour éviter
        le clustering trop large (cf. docs/bugs/bug-comparison-clustering-too-loose.md).
        """
        exclude_url = content.url
        exclude_title = content.title
        seen_domains: set[str] = set()
        if exclude_domain:
            seen_domains.add(exclude_domain)
        merged: list[Perspective] = []

        # Pré-calcul tokens du seed pour filtrer Layers 2/3
        seed_tokens = normalize_title(content.title or "")

        # Layer 1: Internal DB search by shared entities (post-filtre dans la méthode)
        internal = await self.search_internal_perspectives(content)
        for p in internal:
            if p.source_domain not in seen_domains:
                seen_domains.add(p.source_domain)
                merged.append(p)

        # Layer 2: Google News with quoted entities + post-filtre titre Jaccard
        entity_keywords = self.build_entity_query(content.entities, content.title)
        google_raw = await self.search_perspectives(
            entity_keywords, exclude_url, exclude_title, exclude_domain
        )
        google_results, google_filtered = self._filter_external_perspectives(
            seed_tokens, google_raw
        )
        for p in google_results:
            if p.source_domain not in seen_domains:
                seen_domains.add(p.source_domain)
                merged.append(p)

        # Layer 3: Fallback if < 6 results and entity query differs from title keywords
        fallback_keywords = self.extract_keywords(content.title)
        fallback_filtered = 0
        if len(merged) < 6 and entity_keywords != fallback_keywords:
            fallback_raw = await self.search_perspectives(
                fallback_keywords, exclude_url, exclude_title, exclude_domain
            )
            fallback_results, fallback_filtered = self._filter_external_perspectives(
                seed_tokens, fallback_raw
            )
            for p in fallback_results:
                if p.source_domain not in seen_domains:
                    seen_domains.add(p.source_domain)
                    merged.append(p)

        logger.info(
            "perspectives_hybrid_done",
            internal_count=len(internal),
            google_count=len(google_results),
            external_filtered_out=google_filtered + fallback_filtered,
            total_merged=len(merged),
            keywords=entity_keywords,
            filter_enabled=PERSPECTIVE_FILTER_ENABLED,
        )

        return merged[: self.max_results], entity_keywords

    async def _parse_rss(
        self,
        content: bytes,
        exclude_url: str | None = None,
        exclude_title: str | None = None,
        exclude_domain: str | None = None,
    ) -> list[Perspective]:
        """Parse Google News RSS feed."""
        try:
            root = ET.fromstring(content)
            items = root.findall(".//item")

            logger.debug(
                "perspectives_parse_rss",
                total_items=len(items),
            )

            perspectives = []
            seen_domains = set()

            for item in items:
                if len(perspectives) >= self.max_results:
                    break

                title_el = item.find("title")
                link_el = item.find("link")
                source_el = item.find("source")
                pub_date_el = item.find("pubDate")
                desc_el = item.find("description")

                if title_el is None or link_el is None:
                    continue

                title = title_el.text or ""
                link = link_el.text or ""

                # 1. Filter out exact URL match
                if exclude_url and link == exclude_url:
                    continue

                # 2. Filter out very similar titles (simple exact match or contains for now)
                # Google News titles often include " - Source Name" at the end
                if exclude_title:
                    clean_title = title.split(" - ")[0].strip().lower()
                    clean_exclude = exclude_title.strip().lower()
                    if clean_title == clean_exclude or clean_exclude in clean_title:
                        continue

                source_name = source_el.text if source_el is not None else "Unknown"
                source_url = source_el.get("url", "") if source_el is not None else ""

                # Extract domain from source URL
                domain = self._extract_domain(source_url)

                # 3. Filter out perspectives from the same domain as the source article
                if exclude_domain and domain == exclude_domain:
                    continue

                # Skip duplicates from same domain
                if domain in seen_domains:
                    continue
                seen_domains.add(domain)

                # Get bias (DB-first fallback, then name match)
                bias = await self.resolve_bias(domain, source_name=source_name)

                # Clean HTML from RSS description snippet (cap at 300 chars)
                description = None
                if desc_el is not None and desc_el.text:
                    cleaned = re.sub(r"<[^>]+>", " ", desc_el.text)
                    cleaned = html.unescape(re.sub(r"\s+", " ", cleaned).strip())
                    if cleaned:
                        description = cleaned[:300]

                perspectives.append(
                    Perspective(
                        title=title_el.text or "",
                        url=link_el.text or "",
                        source_name=source_name,
                        source_domain=domain,
                        bias_stance=bias,
                        published_at=pub_date_el.text
                        if pub_date_el is not None
                        else None,
                        description=description,
                    )
                )

            return perspectives

        except ET.ParseError as e:
            logger.error(
                "perspectives_parse_xml_error",
                error=str(e),
                content_preview=content[:200].decode("utf-8", errors="ignore"),
            )
            return []
        except Exception as e:
            logger.error(
                "perspectives_parse_unexpected_error",
                error=str(e),
                error_type=type(e).__name__,
            )
            return []

    def _extract_domain(self, url: str) -> str:
        """Extract domain from URL."""
        try:
            from urllib.parse import urlparse

            parsed = urlparse(url)
            domain = parsed.netloc
            # Remove www. prefix
            if domain.startswith("www."):
                domain = domain[4:]
            return domain
        except Exception:
            return ""

    def extract_keywords(self, title: str, max_keywords: int = 5) -> list[str]:
        """
        Extract significant keywords from a title.

        Prioritizes:
        1. Capitalized words (proper nouns like "Trump", "Powell", "Macron")
        2. Acronyms (all caps like "IA", "UE", "ONU")
        3. Long words that aren't stopwords
        """
        import re

        # French stopwords (lowercase only for comparison)
        stopwords = {
            "le",
            "la",
            "les",
            "un",
            "une",
            "des",
            "de",
            "du",
            "d",
            "l",
            "et",
            "en",
            "à",
            "au",
            "aux",
            "ce",
            "cette",
            "qui",
            "que",
            "quoi",
            "dont",
            "où",
            "se",
            "ne",
            "pas",
            "plus",
            "moins",
            "il",
            "elle",
            "on",
            "nous",
            "vous",
            "ils",
            "elles",
            "avec",
            "pour",
            "par",
            "sur",
            "sous",
            "dans",
            "entre",
            "vers",
            "chez",
            "sans",
            "est",
            "sont",
            "être",
            "avoir",
            "fait",
            "faire",
            "mais",
            "ou",
            "donc",
            "car",
            "si",
            "alors",
            "quand",
            "comme",
            "après",
            "avant",
            "pourquoi",
            "comment",
            "face",
            "contre",
            "tout",
            "tous",
            "toute",
            "toutes",
            "cet",
            "ces",
            "son",
            "sa",
            "ses",
            "leur",
            "leurs",
            "notre",
            "nos",
            "votre",
            "vos",
            "public",
            "doit",
            "peut",
            "veut",
            "sera",
            "été",
            "aussi",
            "très",
            "bien",
            "mal",
            "nouveau",
            "nouvelle",
            "nouveaux",
            "nouvelles",
            "grand",
            "grande",
            "petit",
            "petite",
            "premier",
            "première",
            "dernier",
            "dernière",
            "autre",
            "autres",
            "même",
            "mêmes",
        }

        # Common title filler words to ignore (even if capitalized at start)
        title_fillers = {
            "Le",
            "La",
            "Les",
            "Un",
            "Une",
            "Des",
            "Ce",
            "Cette",
            "Ces",
            "Son",
            "Sa",
            "Ses",
            "Comment",
            "Pourquoi",
            "Quand",
            "Qui",
            "Que",
            "Où",
            "Voici",
            "Voilà",
        }

        # Split on punctuation but preserve words
        words = re.findall(r"\b[\wÀ-ÿ]+\b", title)

        proper_nouns = []  # Capitalized words (likely names/places)
        acronyms = []  # All caps words (like IA, UE, ONU)
        regular_words = []  # Other significant words

        for i, word in enumerate(words):
            # Skip very short words
            if len(word) <= 2:
                continue

            # Skip stopwords
            if word.lower() in stopwords:
                continue

            # Skip title fillers
            if word in title_fillers:
                continue

            # Check for acronyms (all uppercase, 2-5 chars)
            if word.isupper() and 2 <= len(word) <= 5:
                acronyms.append(word)
            # Check for proper nouns (starts with capital, not at sentence start or after colon)
            elif word[0].isupper() and len(word) > 2:
                # If it's the first word, check if it looks like a proper noun
                # (not a common word that just happens to be at start)
                if i == 0:
                    # Only keep if it really looks like a name (not a common word)
                    if word.lower() not in stopwords and word not in title_fillers:
                        proper_nouns.append(word)
                else:
                    # Mid-sentence capitalization = definitely important
                    proper_nouns.append(word)
            # Regular significant words
            elif len(word) > 4 and word.lower() not in stopwords:
                regular_words.append(word.lower())

        # Combine: prioritize proper nouns and acronyms, then regular words
        keywords = []

        # First add proper nouns (most important for news)
        for pn in proper_nouns:
            if pn not in keywords:
                keywords.append(pn)
            if len(keywords) >= max_keywords:
                break

        # Add acronyms
        if len(keywords) < max_keywords:
            for acr in acronyms:
                if acr not in keywords:
                    keywords.append(acr)
                if len(keywords) >= max_keywords:
                    break

        # Fill with regular words if needed (targeting 4-5 keywords)
        if len(keywords) < max_keywords:
            for rw in regular_words:
                if rw not in keywords:
                    keywords.append(rw)
                if len(keywords) >= max_keywords:
                    break

        return keywords
