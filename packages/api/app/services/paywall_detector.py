"""Service de détection d'articles payants (paywall).

Détection multi-signaux:
1. JSON-LD Schema.org `isAccessibleForFree` (signal prioritaire, standard Google)
2. Meta tag `og:article:content_tier` (Courrier International, etc.)
3. Scoring RSS fallback: keywords, URL patterns, contenu court

Le signal HTML (1+2) est fiable car déclaratif (le média lui-même déclare l'article payant).
Le scoring (3) sert de filet de sécurité quand pas de HTML disponible.
"""

import json
import re
import time

import structlog

logger = structlog.get_logger()

# Default paywall config used as fallback for sources without custom config
DEFAULT_PAYWALL_CONFIG: dict = {
    "keywords": [
        "Réservé aux abonnés",
        "Article réservé aux abonnés",
        "Article réservé",
        "Contenu réservé",
        "Contenu payant",
        "Abonnez-vous",
        "Article premium",
        "Pour lire la suite",
        "S'abonner",
        "🔒",
        "🔐",
    ],
    "url_patterns": [
        "/premium/",
        "/abonnes/",
        "/subscribers/",
    ],
    "min_content_length": 200,
}

PAYWALL_THRESHOLD = 5

# Types Schema.org qui décrivent un *fragment* de page, pas la page. La spec
# Google place `isAccessibleForFree` à la fois sur l'article et dans `hasPart`
# (le bloc payant, typé WebPageElement). Une page gratuite contenant un encart
# payant porte donc `hasPart.isAccessibleForFree=false` : la lire produirait un
# faux positif — la seule erreur irréversible ici, `_save_content` n'upgradant
# `is_paid` que de False vers True.
_LD_SUBELEMENT_TYPES = frozenset({"webpageelement"})

# Clés qui, par la sémantique Schema.org, pointent vers l'entité principale de
# la page — donc vers un nœud qui parle bien de CET article. On les traverse
# pour rester générique : `@graph` est la forme Yoast, mais un CMS qui imbrique
# l'article sous `WebPage.mainEntity` décrit exactement la même chose.
# `itemListElement` en est volontairement absent : une liste renvoie vers
# d'AUTRES articles, dont l'état d'accès ne dit rien de la page courante.
_LD_CONTAINER_KEYS = ("@graph", "mainEntity", "mainEntityOfPage")

# Certains CMS sérialisent le booléen en URI Schema.org plutôt qu'en littéral.
_LD_FALSE_LITERALS = frozenset({"false", "0", "no", "http://schema.org/false", "https://schema.org/false"})

# In-memory cache: source_id -> (config, expiry_timestamp)
_config_cache: dict[str, tuple[dict, float]] = {}
_CACHE_TTL_SECONDS = 3600  # 1 hour


def _get_config(source_id: str, paywall_config: dict | None) -> dict:
    """Get paywall config for a source, with in-memory caching."""
    now = time.monotonic()
    cache_key = str(source_id)

    cached = _config_cache.get(cache_key)
    if cached and cached[1] > now:
        return cached[0]

    if paywall_config and any(
        [
            paywall_config.get("keywords"),
            paywall_config.get("url_patterns"),
            paywall_config.get("min_content_length"),
        ]
    ):
        config = paywall_config
    else:
        config = DEFAULT_PAYWALL_CONFIG

    _config_cache[cache_key] = (config, now + _CACHE_TTL_SECONDS)
    return config


def _iter_ld_page_nodes(data: object):
    """Parcourt les nœuds Schema.org décrivant la page, `@graph` inclus.

    Yoast SEO (WordPress) n'émet jamais l'article au niveau racine : il
    l'emballe dans `{"@context": ..., "@graph": [...]}`. Sans cette descente le
    signal déclaratif est purement invisible, alors même que le média le
    publie — c'est le mécanisme des faux négatifs constatés sur Novethic.

    On ne descend délibérément pas dans `hasPart` (cf. `_LD_SUBELEMENT_TYPES`).
    """
    if isinstance(data, list):
        for item in data:
            yield from _iter_ld_page_nodes(item)
        return
    if not isinstance(data, dict):
        return

    for key in _LD_CONTAINER_KEYS:
        nested = data.get(key)
        if nested is not None:
            yield from _iter_ld_page_nodes(nested)

    raw_type = data.get("@type")
    types = raw_type if isinstance(raw_type, list) else [raw_type]
    types = {t.lower() for t in types if isinstance(t, str)}
    # Un nœud sans `@type` reste lu : c'est le comportement historique sur les
    # blocs JSON-LD racine, qu'on ne veut pas restreindre au passage.
    if not types & _LD_SUBELEMENT_TYPES:
        yield data


def _ld_access_value(node: dict) -> bool | None:
    """`isAccessibleForFree` d'un nœud, normalisé en is_paid. None si absent."""
    access = node.get("isAccessibleForFree")
    if isinstance(access, bool):
        return not access  # isAccessibleForFree=false → is_paid=True
    if isinstance(access, str):
        return access.strip().lower() in _LD_FALSE_LITERALS
    return None


def detect_paywall_from_html(html_head: str) -> bool | None:
    """Detect paywall from article HTML head using structured data.

    Checks (in order):
    1. JSON-LD Schema.org `isAccessibleForFree` field
    2. Meta tag `og:article:content_tier` (value "locked" = paid)

    Args:
        html_head: First ~50KB of the article HTML (enough for <head> + JSON-LD)

    Returns:
        True (paid), False (free), or None (no signal found)
    """
    # 1. Parse JSON-LD blocks for isAccessibleForFree
    json_ld_pattern = re.compile(
        r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        re.DOTALL | re.IGNORECASE,
    )
    ld_values: list[bool] = []
    for match in json_ld_pattern.finditer(html_head):
        try:
            data = json.loads(match.group(1))
        except (json.JSONDecodeError, TypeError, AttributeError):
            continue
        for node in _iter_ld_page_nodes(data):
            value = _ld_access_value(node)
            if value is not None:
                ld_values.append(value)

    if ld_values:
        # En cas de nœuds contradictoires, « gratuit » gagne. L'asymétrie des
        # coûts l'impose : un faux négatif se rattrape au sync suivant, un faux
        # positif retire définitivement un article gratuit de l'offre.
        return all(ld_values)

    # 2. Check og:article:content_tier meta tag.
    # On isole la balise puis on en extrait `content` séparément : l'ordre des
    # attributs est libre en HTML, et un `<meta content="locked" property=…>`
    # est aussi valide que l'inverse. Exiger l'ordre ferait rater le marqueur
    # chez tout média qui sérialise ses meta dans l'autre sens.
    tier_tag = re.search(
        r"<meta[^>]*\bog:article:content_tier\b[^>]*>", html_head, re.IGNORECASE
    )
    if tier_tag:
        tier_content = re.search(
            r'\bcontent\s*=\s*["\']([^"\']+)["\']', tier_tag.group(0), re.IGNORECASE
        )
        if tier_content:
            tier_value = tier_content.group(1).strip().lower()
            if tier_value in ("locked", "metered"):
                return True
            if tier_value == "free":
                return False

    # 3. Check JS variable patterns (e.g., Le Figaro: window.FFF.isPremium = true)
    premium_js_pattern = re.compile(
        r"isPremium\s*[=:]\s*(true|false)",
        re.IGNORECASE,
    )
    premium_match = premium_js_pattern.search(html_head)
    if premium_match:
        return premium_match.group(1).lower() == "true"

    return None


def detect_paywall(
    title: str,
    description: str | None,
    url: str,
    html_content: str | None,
    source_id: str,
    paywall_config: dict | None = None,
    html_head: str | None = None,
) -> bool:
    """Detect if an article is behind a paywall.

    Uses HTML structured data as primary signal (reliable, declarative).
    Falls back to keyword/URL scoring when no HTML is available.

    Args:
        title: Article title
        description: Article description/summary
        url: Article URL
        html_content: Article HTML content (may be truncated in RSS)
        source_id: Source UUID as string (for caching)
        paywall_config: Source-specific paywall config (JSONB from DB)
        html_head: First ~50KB of the article page HTML (for JSON-LD detection)

    Returns:
        True if article is likely behind a paywall
    """
    # Priority 1: HTML-based detection (JSON-LD, meta tags)
    if html_head:
        html_result = detect_paywall_from_html(html_head)
        if html_result is not None:
            if html_result:
                logger.debug(
                    "paywall_detected_html",
                    title=title[:80],
                    source_id=source_id,
                )
            return html_result

    # Priority 2: Scoring fallback (RSS keywords, URL patterns, content length)
    config = _get_config(source_id, paywall_config)
    score = 0

    # 2a. Keyword detection in title + description + content (+3 per match, max once)
    keywords = config.get("keywords", [])
    if keywords:
        searchable_text = (title or "").lower()
        if description:
            searchable_text += " " + description.lower()
        if html_content:
            searchable_text += " " + html_content.lower()

        for keyword in keywords:
            if keyword.lower() in searchable_text:
                score += 3
                break  # Only count keyword match once

    # 2b. URL pattern detection (+3 per match, max once)
    url_patterns = config.get("url_patterns", [])
    if url_patterns and url:
        url_lower = url.lower()
        for pattern in url_patterns:
            if pattern.lower() in url_lower:
                score += 3
                break  # Only count URL pattern once

    # 2c. Content length check (+2 if content is suspiciously short)
    min_content_length = config.get("min_content_length")
    if min_content_length is not None:
        content_text = html_content or description or ""
        # Strip HTML tags for length check
        plain_text = re.sub(r"<[^>]+>", "", content_text).strip()
        if len(plain_text) < min_content_length:
            score += 2

    is_paid = score >= PAYWALL_THRESHOLD
    if is_paid:
        logger.debug(
            "paywall_detected_scoring",
            title=title[:80],
            score=score,
            source_id=source_id,
        )

    return is_paid


def clear_cache() -> None:
    """Clear the in-memory config cache (useful for testing)."""
    _config_cache.clear()
