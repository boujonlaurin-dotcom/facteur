"""Perspectives service - hybrid search via DB entities + Google News RSS."""

import asyncio
import html
import json
import os
import re
import xml.etree.ElementTree as ET
from collections import Counter
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from urllib.parse import quote

import certifi
import httpx
import structlog
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import selectinload

from app.services.search.providers.denylist import is_listicle_host
from app.services.text_similarity import jaccard_similarity, normalize_title

logger = structlog.get_logger(__name__)


# --- Post-filtre cohérence sujet (anti-clustering trop large) ---
# Voir docs/bugs/bug-comparison-clustering-too-loose.md
PERSPECTIVE_TITLE_JACCARD_MIN = 0.30
# Jaccard minimum exigé même dans le chemin full_signals (bypass Layer 1).
# Empêche qu'un seul topic générique ("politics") suffise à valider deux articles
# sur des sujets radicalement différents (ex: Congo/prisonniers vs Ukraine/trêve)
# partageant seulement un nom propre omniprésent (Trump, Macron…).
# Calibré sur le gold « event_membership » (Iter 1, 2026-06-09) : 0.08 → 0.12
# coupe ~36% des FP « weak double signal » (contamination −24%) pour −7,6% de
# rappel. Cf. docs/maintenance/maintenance-clustering-calibration.md.
PERSPECTIVE_MIN_JACCARD_FLOOR = 0.12
PERSPECTIVE_MIN_VALID_RESULTS = 2
PERSPECTIVE_MIN_BIAS_GROUPS = 2
# Entités jugées suffisamment discriminantes (LOCATION exclu : trop générique)
PERSPECTIVE_DISCRIMINANT_ENTITY_TYPES = frozenset({"PERSON", "ORG", "EVENT"})
# Feature flag (rollback rapide en cas de régression)
PERSPECTIVE_FILTER_ENABLED = (
    os.environ.get("PERSPECTIVE_FILTER_ENABLED", "true").lower() == "true"
)

# Domaines qui redistribuent des liens sans produire eux-mêmes la couverture
# éditoriale comptée. Google News expose normalement le domaine de l'éditeur
# via la balise ``<source>`` ; cette liste reste un garde-fou contre les
# candidats mal résolus et les agrégateurs internes.
# Le test d'appartenance est doublé d'un test de suffixe (`*.google.com`), donc
# les sous-domaines connus (news.google.com, old.reddit.com) sont déjà couverts.
NON_EDITORIAL_AGGREGATOR_DOMAINS: frozenset[str] = frozenset(
    {
        "google.com",
        "reddit.com",
    }
)

# --- Matière envoyée à l'Analyse Facteur (analyze_divergences) ---
# Fenêtres élargies en prompt v2 : moins de résumé = le modèle se rabat sur les
# variations de titres, ce qu'on cherche justement à éviter.
# Cf. docs/maintenance/maintenance-analyse-facteur-prompt-v2.md
PERSPECTIVE_DESC_CHARS = 450
REFERENCE_DESC_CHARS = 900


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

# Google News RSS titles end with " - Source Name" / " | Source" / " – Source".
# Stripping at ingestion keeps the source name out of DiffTitle highlight spans
# (spaCy would otherwise tag « Le Monde » as PROPN and surligher).
# Primary path: exact match against the known source name from <source>.
# Fallback regex stays restrictive — uppercase-initial, no colon, no internal
# separator, ≤ 40 chars — to avoid eating legitimate dash-bearing titles
# (« Foo - Le Linux de poche… », « Etats-Unis – Iran : … », « … - 26/05 »).
_SOURCE_SUFFIX_FALLBACK_RE = re.compile(
    r"\s+[-–|]\s+[A-ZÀ-Ý][A-Za-zÀ-ÿ0-9\s'.&-]{0,40}\s*$"
)


def _strip_source_suffix(title: str, source_name: str | None = None) -> str:
    """Remove Google News' trailing source-name suffix from an RSS title."""
    if not title:
        return title
    stripped = title.rstrip()
    if source_name:
        sn = source_name.strip()
        if sn:
            lower_title = stripped.lower()
            lower_sn = sn.lower()
            for sep in (" - ", " – ", " | "):
                suffix = f"{sep}{lower_sn}"
                if lower_title.endswith(suffix):
                    return stripped[: -len(suffix)].rstrip()
    match = _SOURCE_SUFFIX_FALLBACK_RE.search(stripped)
    if match:
        return stripped[: match.start()].rstrip()
    return stripped


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
    # Fiabilité de la source (low/medium/mixed/high/unknown). Lecture seule de
    # `Source.reliability_score` (Story 7.1) — aucune migration : la colonne
    # existe déjà. "unknown" par défaut (beaucoup de sources non évaluées).
    reliability_score: str | None = None
    # Langue détectée du titre ("fr", "en", autre — None = inconnu). Rempli
    # côté cluster depuis `Content.language` ; les perspectives Google News
    # restent None faute de row Content (le client traite null comme FR par
    # défaut).
    language: str | None = None
    # Présent pour les articles internes (pivot/cluster), absent pour Google
    # News. Il permet de rattacher chaque article du snapshot de couverture au
    # même sujet sans nouvelle requête de clustering.
    content_id: str | None = None


def perspective_to_dict(p: object) -> dict:
    """Forme sérialisée unique d'une [Perspective].

    Le snapshot persisté par le pipeline éditorial et la réponse live de
    ``/contents/{id}/perspectives`` doivent porter exactement les mêmes clés :
    un champ ajouté ici arrive des deux côtés d'un coup. ``getattr`` défensif
    pour les stubs de test qui n'implémentent qu'une partie du dataclass.
    """
    return {
        "content_id": getattr(p, "content_id", None),
        "title": p.title,
        "url": p.url,
        "source_name": p.source_name,
        "source_domain": p.source_domain,
        "bias_stance": p.bias_stance,
        "published_at": p.published_at,
        "description": p.description,
        "reliability_score": getattr(p, "reliability_score", None),
        "language": getattr(p, "language", None),
    }


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
        # Cache for DB reliability lookups within a single request
        self._reliability_cache: dict[str, str] = {}

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

    def _extract_bias_from_source(self, source, domain: str) -> str:
        """Bias from an eager-loaded Source, falling back to DOMAIN_BIAS_MAP."""
        if source is not None and source.bias_stance:
            stance = source.bias_stance.value
            if stance != "unknown":
                return stance
        return DOMAIN_BIAS_MAP.get(domain, "unknown")

    def _extract_reliability_from_source(self, source) -> str:
        """Reliability from an eager-loaded Source, default 'unknown'.

        Lecture seule de `Source.reliability_score` (déjà chargé par la requête,
        comme `bias_stance`). Pas de map en dur : la fiabilité ne vit qu'en base.
        """
        if source is not None and source.reliability_score:
            return str(source.reliability_score.value)
        return "unknown"

    async def _resolve_source_column(
        self,
        column_of,
        cache: dict[str, str],
        normalize,
        log_event: str,
        domain: str,
        source_name: str | None,
    ) -> str:
        """DB fallback shared by [resolve_bias]/[resolve_reliability].

        Cache mémoire → lookup par URL (domaine) → fallback fuzzy par nom →
        défaut "unknown". `column_of(Source)` désigne la colonne lue, `normalize`
        transforme le scalaire retourné en `str`, `log_event` nomme le warning.
        """
        cache_key = domain or source_name or ""
        if cache_key in cache:
            return cache[cache_key]

        if self._has_db():
            try:
                from app.models.source import Source

                async with self._short_session() as session:
                    if session is None:
                        cache[cache_key] = "unknown"
                        return "unknown"

                    column = column_of(Source)
                    predicates = []
                    if domain:
                        predicates.append(Source.url.ilike(f"%{domain}%"))
                    if source_name and source_name != "Unknown":
                        predicates.append(Source.name.ilike(f"%{source_name}%"))

                    for predicate in predicates:
                        stmt = select(column).where(
                            predicate, Source.is_active.is_(True)
                        )
                        raw = (await session.execute(stmt)).scalar_one_or_none()
                        if raw and raw != "unknown":
                            val = normalize(raw)
                            cache[cache_key] = val
                            return val
            except Exception as e:
                logger.warning(
                    log_event,
                    domain=domain,
                    source_name=source_name,
                    error=str(e),
                )

        cache[cache_key] = "unknown"
        return "unknown"

    async def resolve_bias(self, domain: str, source_name: str | None = None) -> str:
        """Resolve bias for a domain: DOMAIN_BIAS_MAP first, then DB fallback by URL, then by name."""
        # Hardcoded map first (fast) — propre au biais, pas à la fiabilité.
        bias = DOMAIN_BIAS_MAP.get(domain)
        if bias:
            return bias
        return await self._resolve_source_column(
            lambda S: S.bias_stance,
            self._bias_cache,
            lambda raw: raw,
            "resolve_bias_db_error",
            domain,
            source_name,
        )

    async def resolve_reliability(
        self, domain: str, source_name: str | None = None
    ) -> str:
        """Resolve reliability for a domain (read-only Source.reliability_score).

        Calqué sur [resolve_bias] mais sans map en dur (la fiabilité ne vit qu'en
        base) : DB lookup par URL puis par nom, défaut "unknown". Beaucoup de
        sources ne sont pas évaluées ⇒ "unknown" est le cas dominant attendu.
        """
        return await self._resolve_source_column(
            lambda S: S.reliability_score,
            self._reliability_cache,
            lambda raw: str(getattr(raw, "value", raw)),
            "resolve_reliability_db_error",
            domain,
            source_name,
        )

    async def _prefetch_source_attributes(self, domains: list[str]) -> None:
        """Batch-warm ``_bias_cache``/``_reliability_cache`` in a single query.

        Sans ça, chaque item RSS Google News déclenche 1-2 SELECT ``Source``
        via ``resolve_bias``/``resolve_reliability`` (predicate ``url ILIKE
        %domaine%``) → N+1 remonté par Sentry (PYTHON-50, culprit
        ``get_perspectives`` : le endpoint programme un refresh en background
        qui passe par ``_parse_rss``). On collapse les lookups par-domaine en
        UNE requête, puis on pré-remplit les caches que ``resolve_*`` consulte
        déjà. La sémantique est préservée à l'identique :

        - on ne pré-remplit QUE ce que le predicate ``url`` par-domaine aurait
          renvoyé (1 seule source active matchée, valeur ≠ "unknown") ;
        - >1 source matchée → ``scalar_one_or_none`` lèverait, et
          ``_resolve_source_column`` retombe sur "unknown" : on reproduit ce
          "unknown" ;
        - 0 match, ou match unique à valeur "unknown" → on ne pré-remplit rien,
          et l'appel per-item d'origine gère le fallback par nom inchangé.

        Best-effort : toute erreur laisse le chemin per-item d'origine intact.
        """
        if not self._has_db():
            return
        uniq = {d for d in domains if d}
        uniq = {
            d
            for d in uniq
            if d not in self._bias_cache or d not in self._reliability_cache
        }
        if not uniq:
            return
        try:
            from app.models.source import Source

            async with self._short_session() as session:
                if session is None:
                    return
                stmt = select(Source).where(
                    Source.is_active.is_(True),
                    or_(*[Source.url.ilike(f"%{d}%") for d in uniq]),
                )
                rows = (await session.execute(stmt)).scalars().all()
        except Exception as e:  # pragma: no cover - best-effort prefetch
            logger.warning("prefetch_source_attributes_error", error=str(e))
            return

        for d in uniq:
            matches = [s for s in rows if d.lower() in (s.url or "").lower()]
            if len(matches) == 1:
                s = matches[0]
                if d not in self._bias_cache:
                    b = s.bias_stance
                    if b and getattr(b, "value", b) != "unknown":
                        # normalize = identité pour le biais (cf. resolve_bias)
                        self._bias_cache[d] = b
                if d not in self._reliability_cache:
                    r = s.reliability_score
                    if r and getattr(r, "value", r) != "unknown":
                        self._reliability_cache[d] = str(getattr(r, "value", r))
            elif len(matches) > 1:
                # scalar_one_or_none lèverait → _resolve_source_column = "unknown"
                self._bias_cache.setdefault(d, "unknown")
                self._reliability_cache.setdefault(d, "unknown")
            # len(matches) == 0 → laissé au fallback per-item (predicate nom)

    async def analyze_divergences(
        self,
        article_title: str,
        source_name: str,
        source_bias: str,
        perspectives: list[dict],  # [{title, source_name, bias_stance, description?}]
        article_description: str | None = None,
    ) -> dict | None:
        """Generate a short LLM analysis of editorial divergences.

        Prompt v2 : la sortie répond à « ce que l'on sait » puis « ce qui fait
        débat » (points litigieux de fond), et non plus aux variations de
        formulation entre titres. Cf.
        docs/maintenance/maintenance-analyse-facteur-prompt-v2.md.

        Returns a dict with keys:
        - "analysis": str — texte markdown (~180 mots). Le **premier `\\n\\n`**
          sépare la section « établi » de la section « en débat » : c'est le
          contrat lu côté mobile par `splitAnalysisSections`
          (perspectives_bottom_sheet.dart). Ne pas casser ce séparateur.
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
                line += f" — {desc[:PERSPECTIVE_DESC_CHARS]}"
            perspectives_lines.append(line)
        perspectives_text = "\n".join(perspectives_lines)

        system = (
            "Analyste média français. À partir de la couverture d'un même sujet "
            "par plusieurs rédactions, tu produis deux choses : CE QUI EST ÉTABLI "
            "et CE QUI FAIT DÉBAT.\n\n"
            "Méthode obligatoire :\n"
            "1. Lis tous les titres + résumés.\n"
            "2. ÉTABLI : isole les faits que les couvertures partagent — "
            "l'événement, les acteurs, les chiffres et les dates repris d'une "
            "source à l'autre.\n"
            "3. DÉBAT : identifie 2 à 3 POINTS LITIGIEUX. Un point litigieux est "
            "une question de fond sur laquelle les couvertures ne répondent pas "
            "pareil : la cause, la responsabilité, l'ampleur, l'efficacité, la "
            "légitimité, la suite probable. Pour chacun, dis quelle position tient "
            "quel média.\n"
            "4. TEST DE RECEVABILITÉ : si un constat ne peut pas se reformuler en "
            "question (« Qui est responsable ? », « Quelle ampleur ? », « Est-ce "
            "que ça marche ? », « Et après ? »), c'est une variation de style — "
            "écarte-le. Ne retiens jamais un constat dont le seul contenu est le "
            "choix d'un mot.\n"
            "5. Si les couvertures convergent vraiment, ne fabrique pas de "
            "désaccord : dis-le et nomme ce qui reste inconnu ou non vérifié "
            "(divergence_level: low).\n\n"
            "Réponds en JSON avec deux clés :\n"
            '- "analysis": texte structuré ainsi :\n'
            "  1. CE QUI EST ÉTABLI : 2 à 3 phrases (45-75 mots), les faits "
            "partagés. Aucun nom de média ici, aucun commentaire sur les "
            "formulations.\n"
            "  2. Saut de ligne double (\\n\\n).\n"
            '  3. CE QUI FAIT DÉBAT : 2 à 3 lignes préfixées "→ ", 35-55 mots '
            "chacune :\n"
            "     • l'objet du désaccord en **gras** "
            "(« **la responsabilité du déficit** », "
            "« **l'ampleur réelle des économies** »),\n"
            "     • la position A et les médias qui la tiennent (noms en **gras**),\n"
            "     • la position opposée et les médias qui la tiennent,\n"
            "     • au plus UN terme cité entre guillemets, en appui du désaccord, "
            "jamais comme sujet de la ligne.\n"
            "  Si divergence_level = low : une seule ligne « → », qui constate la "
            "convergence et nomme ce qui reste en suspens.\n"
            "  Max 5 segments en gras par ligne. Aucun titre de section "
            "(l'app les ajoute).\n"
            '- "divergence_level": "low" (mêmes faits, mêmes conclusions), '
            '"medium" (désaccords d\'interprétation ou de priorité), "high" '
            "(conclusions contradictoires sur un même fait).\n\n"
            "RÈGLES :\n"
            "- Uniquement les titres/résumés fournis. Zéro fait inventé, zéro "
            "intention prêtée à un média sans appui textuel.\n"
            "- Position inférée d'un titre seul : nuance avec « semble » ou "
            "« laisse entendre ». Pas de formule répétée en fin de ligne.\n"
            "- Verbes de position : attribue(nt) à, impute(nt) à, chiffre(nt) à, "
            "juge(nt), conteste(nt), relativise(nt), tient/tiennent pour, "
            "avance(nt), doute(nt) de, lie(nt) à.\n"
            '- Interdits : "met en lumière", "soulève des questions", '
            '"révèle la fragilité", "fait écho", "interroge", "questionne", '
            '"d\'après leurs titres".\n'
            "- Ton assertif, phrases denses, pas de précautions inutiles. "
            "Français impeccable.\n\n"
            "EXEMPLE :\n"
            "« Bercy a présenté le 14 octobre un budget 2026 prévoyant 12 milliards "
            "d'euros d'économies, dont 4 sur l'assurance maladie et 2 sur les "
            "collectivités. Le texte arrive à l'Assemblée en novembre, sans "
            "majorité acquise. Toutes les rédactions donnent les mêmes montants et "
            "le même calendrier.\\n\\n"
            "→ **L'origine du déficit** : **Les Échos** et **Le Figaro** "
            "l'imputent à la dérive des dépenses sociales et chiffrent à 2 points "
            "de PIB le décrochage ; **Mediapart** et **Libération** l'attribuent "
            "aux baisses d'impôts consenties depuis 2017, jamais compensées.\\n"
            "→ **L'ampleur réelle de l'effort** : **Le Monde** rappelle que les "
            "12 milliards portent sur une hausse tendancielle, soit une "
            "quasi-stabilité en euros constants ; **Le Point** présente le même "
            "chiffre comme la coupe la plus forte depuis 2011.\\n"
            "→ **Les chances d'adoption** : **Politico** et **L'Opinion** jugent "
            "le 49.3 probable dès décembre ; **La Croix** croit à un compromis "
            "avec les socialistes sur le volet santé. »"
        )

        source_stance = STANCE_LABELS.get(source_bias, source_bias)
        user_message = (
            "Sujet d'actualité couvert par plusieurs médias.\n\n"
            f'Article de référence : "{article_title}" ({source_name}, {source_stance})'
        )
        if article_description:
            user_message += f"\nRésumé : {article_description[:REFERENCE_DESC_CHARS]}"
        user_message += f"\n\nCouverture par d'autres médias :\n{perspectives_text}"

        try:
            result = await client.chat_json(
                system=system,
                user_message=user_message,
                model="mistral-large-latest",
                temperature=0.3,
                max_tokens=900,
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
        - Sinon, si signaux complets (Layer 1 DB) ET jaccard >= floor minimal :
          (shared_topics >= 1 ET shared_entities >= 1) OU shared_entities >= 2.
        - Sinon (Layer 2/3 Google News, ou jaccard trop faible) → rejeter.

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
            # 2 entités discriminantes partagées → signal fort, pas de floor requis.
            if signals["shared_entities"] and signals["shared_entities"] >= 2:
                return True, ""
            # 1 topic + 1 entité : exiger aussi un Jaccard minimal pour bloquer
            # les faux-positifs "même personnalité, sujets totalement différents"
            # (ex: Congo/Trump vs Ukraine/Trump — seul token commun : "trump").
            if signals["title_jaccard"] >= PERSPECTIVE_MIN_JACCARD_FLOOR:
                topic_ok = bool(
                    signals["shared_topics"] and signals["shared_topics"] >= 1
                )
                entity_ok = bool(
                    signals["shared_entities"] and signals["shared_entities"] >= 1
                )
                if topic_ok and entity_ok:
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

        cutoff = datetime.now(UTC) - timedelta(hours=time_window_hours)

        # Build OR conditions: entities text array contains entity name.
        # Passer par le wrapper `content_entities_text` (et non le builtin
        # `array_to_string`, STABLE donc non-sargable) est requis ICI : c'est
        # l'expression exacte qu'indexe `ix_contents_entities_trgm` (GIN trigram,
        # migration pt01), sinon le planner scanne toute la fenêtre 72h.
        entity_filters = [
            func.content_entities_text(Content.entities).ilike(f"%{name}%")
            for name in entity_names
        ]

        # Eager-load Content.source so the bias lookup below is in-memory.
        # Sans selectinload, `resolve_bias(domain)` repartait au DB pour chaque
        # ligne (N+1 sur /contents/{id}/perspectives — bottom-sheet "Autres regards").
        stmt = (
            select(Content)
            .options(selectinload(Content.source))
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

            source_obj = row.source
            source_name = (source_obj.name or domain) if source_obj else domain
            bias = self._extract_bias_from_source(source_obj, domain)
            reliability = self._extract_reliability_from_source(source_obj)

            perspectives.append(
                Perspective(
                    title=row.title,
                    url=row.url,
                    source_name=source_name,
                    source_domain=domain,
                    bias_stance=bias,
                    reliability_score=reliability,
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

        seen_domains: set[str] = set()
        result: list[Perspective] = []
        for content in contents:
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

            # La couverture publique est définie par domaine, pas par ligne
            # Source : deux feeds d'un même média ne doivent compter qu'une fois.
            domain = domain.lower()
            if not domain or domain in seen_domains:
                continue
            seen_domains.add(domain)

            bias = self._extract_bias_from_source(source, domain)
            reliability = self._extract_reliability_from_source(source)

            result.append(
                Perspective(
                    title=getattr(content, "title", "") or "",
                    url=getattr(content, "url", "") or "",
                    source_name=source_name or domain,
                    source_domain=domain,
                    bias_stance=bias,
                    reliability_score=reliability,
                    published_at=(
                        content.published_at.isoformat()
                        if getattr(content, "published_at", None)
                        else None
                    ),
                    description=getattr(content, "description", None),
                    language=getattr(content, "language", None),
                    content_id=(
                        str(content.id) if getattr(content, "id", None) else None
                    ),
                )
            )
        return result

    @staticmethod
    def _is_editorial_content_candidate(content) -> bool:
        """False pour un agrégateur interne qui ne produit pas l'article."""
        from app.models.enums import SourceType

        source = getattr(content, "source", None)
        raw_type = getattr(source, "type", None) if source is not None else None
        try:
            if raw_type is not None and SourceType(raw_type) == SourceType.REDDIT:
                return False
        except (TypeError, ValueError):
            pass

        raw_url = getattr(content, "url", "")
        return not is_listicle_host(raw_url if isinstance(raw_url, str) else "")

    @staticmethod
    def _is_editorial_perspective_candidate(perspective: Perspective) -> bool:
        domain = (perspective.source_domain or "").lower().removeprefix("www.")
        if not domain or domain in NON_EDITORIAL_AGGREGATOR_DOMAINS:
            return False
        if any(domain.endswith(f".{d}") for d in NON_EDITORIAL_AGGREGATOR_DOMAINS):
            return False
        return not is_listicle_host(f"https://{domain}")

    def _filter_cluster_contents_for_coverage(
        self,
        reference,
        contents: list,
    ) -> tuple[list, list[str]]:
        """Applique le même filtre sujet au pivot et aux articles du cluster.

        Le pivot est toujours conservé. Les autres articles passent par les
        signaux Jaccard/topics/entités déjà utilisés par la recherche interne.
        """
        ordered = [reference]
        reference_id = getattr(reference, "id", None)
        ordered.extend(c for c in contents if getattr(c, "id", None) != reference_id)
        if not PERSPECTIVE_FILTER_ENABLED:
            kept = [c for c in ordered if self._is_editorial_content_candidate(c)]
            return kept, []

        reference_title = getattr(reference, "title", "")
        seed_tokens = normalize_title(
            reference_title if isinstance(reference_title, str) else ""
        )
        raw_topics = getattr(reference, "topics", None)
        raw_entities = getattr(reference, "entities", None)
        seed_topics = (
            {t.lower() for t in raw_topics if isinstance(t, str) and t}
            if isinstance(raw_topics, (list, tuple))
            else set()
        )
        seed_disc_entities = (
            set(
                _parse_entity_names(
                    list(raw_entities), types=PERSPECTIVE_DISCRIMINANT_ENTITY_TYPES
                )
            )
            if isinstance(raw_entities, (list, tuple))
            else set()
        )

        kept: list = []
        reasons: list[str] = []
        for candidate in ordered:
            if not self._is_editorial_content_candidate(candidate):
                reasons.append("non_editorial")
                continue
            if getattr(candidate, "id", None) == reference_id:
                kept.append(candidate)
                continue
            candidate_title = getattr(candidate, "title", "")
            candidate_topics = getattr(candidate, "topics", None)
            candidate_entities = getattr(candidate, "entities", None)
            signals = self._topical_signals(
                seed_tokens,
                seed_topics,
                seed_disc_entities,
                cand_title=(
                    candidate_title if isinstance(candidate_title, str) else ""
                ),
                cand_topics=(
                    list(candidate_topics)
                    if isinstance(candidate_topics, (list, tuple))
                    else None
                ),
                cand_entities=(
                    list(candidate_entities)
                    if isinstance(candidate_entities, (list, tuple))
                    else None
                ),
            )
            is_ok, reason = self._is_topically_coherent(signals)
            if is_ok:
                kept.append(candidate)
            else:
                reasons.append(reason)
        return kept, reasons

    async def build_coverage_universe(
        self,
        reference,
        cluster_contents: list,
        discovered_perspectives: list[Perspective],
    ) -> list[Perspective]:
        """Construit la vérité unique pivot + cluster + recherche hybride.

        Tous les candidats sont cohérents avec le pivot, éditoriaux et
        dédupliqués par domaine. Les biais ``unknown`` sont volontairement
        conservés : ils comptent dans la couverture et restent consultables.
        """
        coherent_contents, cluster_reasons = self._filter_cluster_contents_for_coverage(
            reference, cluster_contents
        )
        cluster_perspectives = await self.build_cluster_perspectives(coherent_contents)

        seed_title = getattr(reference, "title", "")
        seed_tokens = normalize_title(seed_title if isinstance(seed_title, str) else "")
        coherent_discovered, external_rejected = self._filter_external_perspectives(
            seed_tokens, discovered_perspectives
        )

        merged: list[Perspective] = []
        seen_domains: set[str] = set()
        duplicate_domains = 0
        non_editorial = 0
        for perspective in [*cluster_perspectives, *coherent_discovered]:
            if not self._is_editorial_perspective_candidate(perspective):
                non_editorial += 1
                continue
            domain = perspective.source_domain.lower().removeprefix("www.")
            if domain in seen_domains:
                duplicate_domains += 1
                continue
            perspective.source_domain = domain
            seen_domains.add(domain)
            merged.append(perspective)

        known = sum(1 for p in merged if p.bias_stance != "unknown")
        logger.info(
            "perspectives_coverage_universe_built",
            candidates=(len(cluster_contents) + len(discovered_perspectives)),
            cluster_rejected_off_topic=len(cluster_reasons),
            cluster_rejection_reasons=dict(Counter(cluster_reasons)),
            external_rejected_off_topic=external_rejected,
            duplicate_domains=duplicate_domains,
            non_editorial_rejected=non_editorial,
            known_sources=known,
            unknown_sources=len(merged) - known,
            coverage_count=len(merged),
        )
        return merged

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

        # Layer 2/3: run Google News entity and fallback queries in parallel.
        # The endpoint may decide not to wait for Google at all (fast-first),
        # but when this full path is used, avoid entity→fallback serial latency.
        entity_keywords = self.build_entity_query(content.entities, content.title)
        fallback_keywords = self.extract_keywords(content.title)
        google_tasks = [
            self.search_perspectives(
                entity_keywords, exclude_url, exclude_title, exclude_domain
            )
        ]
        include_fallback = entity_keywords != fallback_keywords
        if include_fallback:
            google_tasks.append(
                self.search_perspectives(
                    fallback_keywords, exclude_url, exclude_title, exclude_domain
                )
            )

        google_outputs = await asyncio.gather(*google_tasks, return_exceptions=True)
        google_raw = (
            google_outputs[0]
            if google_outputs and not isinstance(google_outputs[0], Exception)
            else []
        )
        if google_outputs and isinstance(google_outputs[0], Exception):
            logger.warning(
                "perspectives_entity_google_failed",
                error=str(google_outputs[0]),
                error_type=type(google_outputs[0]).__name__,
            )
        google_results, google_filtered = self._filter_external_perspectives(
            seed_tokens, google_raw
        )
        for p in google_results:
            if p.source_domain not in seen_domains:
                seen_domains.add(p.source_domain)
                merged.append(p)

        fallback_filtered = 0
        if include_fallback and len(merged) < 6:
            fallback_raw = (
                google_outputs[1]
                if len(google_outputs) > 1
                and not isinstance(google_outputs[1], Exception)
                else []
            )
            if len(google_outputs) > 1 and isinstance(google_outputs[1], Exception):
                logger.warning(
                    "perspectives_fallback_google_failed",
                    error=str(google_outputs[1]),
                    error_type=type(google_outputs[1]).__name__,
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

            # N+1 fix (Sentry PYTHON-50) : pré-charge en UNE requête le biais /
            # la fiabilité de tous les domaines candidats, pour que les appels
            # resolve_bias / resolve_reliability de la boucle ci-dessous tapent
            # le cache mémoire au lieu d'un SELECT Source par item RSS.
            # Sur-préchargement inoffensif : un domaine finalement filtré ne
            # fait que remplir un cache jamais lu (sortie inchangée).
            prefetch_domains = [
                self._extract_domain(el.get("url", "") or "")
                for el in (item.find("source") for item in items)
                if el is not None
            ]
            await self._prefetch_source_attributes(prefetch_domains)

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

                raw_title = title_el.text or ""
                link = link_el.text or ""

                # 1. Filter out exact URL match
                if exclude_url and link == exclude_url:
                    continue

                source_name = source_el.text if source_el is not None else "Unknown"
                source_url = source_el.get("url", "") if source_el is not None else ""

                # Strip Google News' "- Source" suffix once, at ingestion.
                # All downstream consumers (dedup, DiffTitle, LLM annotation)
                # see a clean title.
                title = _strip_source_suffix(raw_title, source_name)

                # 2. Filter out very similar titles vs. the reference article
                if exclude_title:
                    clean_title = title.lower()
                    clean_exclude = exclude_title.strip().lower()
                    if clean_title == clean_exclude or clean_exclude in clean_title:
                        continue

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
                # Get reliability (read-only DB lookup, same fallback chain)
                reliability = await self.resolve_reliability(
                    domain, source_name=source_name
                )

                # Clean HTML from RSS description snippet (cap at 300 chars)
                description = None
                if desc_el is not None and desc_el.text:
                    cleaned = re.sub(r"<[^>]+>", " ", desc_el.text)
                    cleaned = html.unescape(re.sub(r"\s+", " ", cleaned).strip())
                    if cleaned:
                        description = cleaned[:300]

                perspectives.append(
                    Perspective(
                        title=title,
                        url=link_el.text or "",
                        source_name=source_name,
                        source_domain=domain,
                        bias_stance=bias,
                        reliability_score=reliability,
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
