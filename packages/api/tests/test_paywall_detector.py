"""Tests unitaires du niveau 1 : les signaux HTML déclaratifs.

Ces cas sont autonomes (fixtures inline, pas de corpus, pas de réseau) et
verrouillent les deux propriétés du parseur JSON-LD qui décident réellement :
descendre dans `@graph`, et ne jamais lire `isAccessibleForFree` sur un
fragment de page.

Le second point porte l'asymétrie de la feature : un faux positif retire
définitivement un article gratuit de l'offre (`_save_content` n'upgrade
`is_paid` que de False vers True), là où un faux négatif se rattrape au sync
suivant.
"""

import json

from app.services.paywall_detector import detect_paywall_from_html


def _ld(payload: dict | list) -> str:
    return (
        '<html><head><script type="application/ld+json">'
        f"{json.dumps(payload)}"
        "</script></head><body></body></html>"
    )


def test_graph_wrapped_article_is_detected():
    """Yoast (WordPress) emballe l'article dans `@graph` — cas Novethic.

    Sans descente dans `@graph`, le signal est invisible alors que le média le
    déclare : c'est le mécanisme des faux négatifs constatés sur Novethic.
    """
    html = _ld(
        {
            "@context": "https://schema.org",
            "@graph": [
                {"@type": "Organization", "name": "Novethic"},
                {
                    "@type": "NewsArticle",
                    "headline": "Un article payant",
                    "isAccessibleForFree": False,
                },
            ],
        }
    )
    assert detect_paywall_from_html(html) is True


def test_graph_wrapped_free_article_stays_free():
    html = _ld(
        {
            "@context": "https://schema.org",
            "@graph": [{"@type": "NewsArticle", "isAccessibleForFree": True}],
        }
    )
    assert detect_paywall_from_html(html) is False


def test_haspart_paywalled_block_does_not_mark_free_page_as_paid():
    """Le garde-fou anti-faux-positif.

    La spec Google place `isAccessibleForFree` aussi dans `hasPart`. Une page
    gratuite qui embarque un encart payant ne doit pas basculer en payante.
    """
    html = _ld(
        {
            "@type": "NewsArticle",
            "isAccessibleForFree": True,
            "hasPart": {
                "@type": "WebPageElement",
                "isAccessibleForFree": False,
                "cssSelector": ".paywall",
            },
        }
    )
    assert detect_paywall_from_html(html) is False


def test_standalone_webpageelement_node_is_ignored():
    """Un fragment promu en nœud racine de `@graph` ne décide pas non plus."""
    html = _ld(
        {
            "@context": "https://schema.org",
            "@graph": [
                {
                    "@type": "WebPageElement",
                    "isAccessibleForFree": False,
                    "cssSelector": ".paywall",
                },
                {"@type": "NewsArticle", "isAccessibleForFree": True},
            ],
        }
    )
    assert detect_paywall_from_html(html) is False


def test_contradictory_nodes_resolve_to_free():
    """Nœuds contradictoires : « gratuit » gagne, par asymétrie des coûts."""
    html = _ld(
        {
            "@context": "https://schema.org",
            "@graph": [
                {"@type": "NewsArticle", "isAccessibleForFree": False},
                {"@type": "WebPage", "isAccessibleForFree": True},
            ],
        }
    )
    assert detect_paywall_from_html(html) is False


def test_string_valued_flag_is_honoured():
    """Certains CMS sérialisent le booléen en chaîne (cas Philosophie Magazine)."""
    html = _ld({"@type": "NewsArticle", "isAccessibleForFree": "False"})
    assert detect_paywall_from_html(html) is True


def test_absent_signal_returns_none_so_scoring_can_take_over():
    html = _ld({"@type": "NewsArticle", "headline": "Sans marqueur"})
    assert detect_paywall_from_html(html) is None


def test_invalid_json_ld_block_does_not_hide_a_later_valid_one():
    html = (
        '<html><head><script type="application/ld+json">{ pas du JSON</script>'
        '<script type="application/ld+json">'
        f"{json.dumps({'@type': 'NewsArticle', 'isAccessibleForFree': False})}"
        "</script></head></html>"
    )
    assert detect_paywall_from_html(html) is True


def test_content_tier_still_decides_when_json_ld_is_silent():
    html = (
        "<html><head>"
        '<meta property="og:article:content_tier" content="locked">'
        "</head></html>"
    )
    assert detect_paywall_from_html(html) is True


# ── Généricité : mêmes marqueurs, autres formes ─────────────────────────────
# Ces cas ne sont pas représentés dans le corpus des 12 sources collectées. Ils
# décrivent le *même* comportement déclaratif sous une sérialisation différente,
# et existent pour que la détection profite aux sources non observées.


def test_article_nested_under_main_entity_is_detected():
    """`WebPage.mainEntity` → l'article : même sens que `@graph`, autre forme."""
    html = _ld(
        {
            "@type": "WebPage",
            "mainEntity": {"@type": "NewsArticle", "isAccessibleForFree": False},
        }
    )
    assert detect_paywall_from_html(html) is True


def test_item_list_element_is_not_traversed():
    """Une liste renvoie vers d'AUTRES articles : leur accès ne dit rien d'ici.

    Les traverser ferait basculer en payante une page de rubrique gratuite qui
    liste des articles payants — un faux positif.
    """
    html = _ld(
        {
            "@type": "CollectionPage",
            "itemListElement": [
                {"@type": "NewsArticle", "isAccessibleForFree": False},
            ],
        }
    )
    assert detect_paywall_from_html(html) is None


def test_schema_org_uri_boolean_is_understood():
    """Certains CMS sérialisent le booléen en URI plutôt qu'en littéral."""
    paid = _ld({"@type": "NewsArticle", "isAccessibleForFree": "https://schema.org/False"})
    free = _ld({"@type": "NewsArticle", "isAccessibleForFree": "https://schema.org/True"})
    assert detect_paywall_from_html(paid) is True
    assert detect_paywall_from_html(free) is False


def test_content_tier_ignores_attribute_order():
    """`content` avant `property` est du HTML aussi valide que l'inverse."""
    html = (
        "<html><head>"
        '<meta content="locked" property="og:article:content_tier">'
        "</head></html>"
    )
    assert detect_paywall_from_html(html) is True


def test_content_tier_free_ignores_attribute_order():
    html = (
        "<html><head>"
        "<meta content='free' property='og:article:content_tier'>"
        "</head></html>"
    )
    assert detect_paywall_from_html(html) is False
