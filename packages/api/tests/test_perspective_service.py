import json

import pytest

from app.services.perspective_service import (
    PERSPECTIVE_TITLE_JACCARD_MIN,
    Perspective,
    PerspectiveService,
)
from app.services.text_similarity import normalize_title


@pytest.mark.asyncio
async def test_perspective_filtering_logic():
    service = PerspectiveService()

    # Mock RSS content with 3 items
    mock_rss = b"""<?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
    <channel>
        <item>
            <title>Article Original - Le Monde</title>
            <link>http://lemonde.fr/article1</link>
            <source url="http://lemonde.fr">Le Monde</source>
        </item>
        <item>
            <title>Autre Article - Figaro</title>
            <link>http://lefigaro.fr/article2</link>
            <source url="http://lefigaro.fr">Le Figaro</source>
        </item>
        <item>
            <title>Doublon Titre - Libe</title>
            <link>http://liberation.fr/article3</link>
            <source url="http://liberation.fr">Liberation</source>
        </item>
    </channel>
    </rss>"""

    # 1. Test without exclusion
    results = await service._parse_rss(mock_rss)
    assert len(results) == 3

    # 2. Test with URL exclusion
    results_url = await service._parse_rss(mock_rss, exclude_url="http://lemonde.fr/article1")
    assert len(results_url) == 2
    assert results_url[0].title == "Autre Article - Figaro"

    # 3. Test with Title exclusion (similarity check)
    # The logic splits by " - " and compares
    results_title = await service._parse_rss(mock_rss, exclude_title="Doublon Titre")
    assert len(results_title) == 2
    assert results_title[1].title == "Autre Article - Figaro"  # Order might change due to set, but here list
    # Actually Liberation was the 3rd one.
    titles = [r.title for r in results_title]
    assert "Doublon Titre - Libe" not in titles


# ---------------------------------------------------------------------------
# Post-filtre cohérence sujet — anti-clustering trop large
# Ref : docs/bugs/bug-comparison-clustering-too-loose.md
# ---------------------------------------------------------------------------

# Fixture du bug rapporté : seed Texas-Dix-Commandements + 3 candidats
SEED_TITLE = (
    "Le Texas autorisé à imposer l'affichage des Dix commandements dans les écoles"
)
SEED_TOPICS = ["religion", "education"]
SEED_ENTITIES = [
    json.dumps({"name": "Texas", "type": "LOCATION"}),
    json.dumps({"name": "Cour suprême", "type": "ORG"}),
]

# Candidat on-topic (Le Monde, même sujet)
CAND_ON_TOPIC = {
    "title": "Le Texas autorisé à imposer l'affichage des Dix commandements dans les écoles publiques",
    "topics": ["religion", "education"],
    "entities": [
        json.dumps({"name": "Texas", "type": "LOCATION"}),
        json.dumps({"name": "Cour suprême", "type": "ORG"}),
    ],
}

# Candidats off-topic (partagent juste "Texas")
CAND_OFF_TEMPETE = {
    "title": "Du Texas à New York, une méga tempête hivernale s'apprête à balayer les États-Unis",
    "topics": ["weather", "climate"],
    "entities": [
        json.dumps({"name": "Texas", "type": "LOCATION"}),
        json.dumps({"name": "New York", "type": "LOCATION"}),
    ],
}

CAND_OFF_AVORTEMENT = {
    "title": "États-Unis : au Texas, le combat des femmes pour avorter",
    "topics": ["health", "society"],
    "entities": [
        json.dumps({"name": "Texas", "type": "LOCATION"}),
    ],
}


def _seed_signals_inputs():
    """Reproduit le pré-calcul fait dans search_internal_perspectives."""
    seed_tokens = normalize_title(SEED_TITLE)
    seed_topics = {t.lower() for t in SEED_TOPICS if t}
    # Notre fixture seed n'a pas d'entité PERSON/ORG/EVENT discriminante
    # (Texas=LOCATION, Cour suprême=ORG en théorie mais on garde simple ici).
    # On simule le cas où seules les entités discriminantes comptent.
    from app.services.perspective_service import (
        PERSPECTIVE_DISCRIMINANT_ENTITY_TYPES,
        _parse_entity_names,
    )
    seed_disc = set(
        _parse_entity_names(SEED_ENTITIES, types=PERSPECTIVE_DISCRIMINANT_ENTITY_TYPES)
    )
    return seed_tokens, seed_topics, seed_disc


def test_topical_signals_on_topic_high_jaccard():
    seed_tokens, seed_topics, seed_disc = _seed_signals_inputs()
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics,
        seed_disc,
        cand_title=CAND_ON_TOPIC["title"],
        cand_topics=CAND_ON_TOPIC["topics"],
        cand_entities=CAND_ON_TOPIC["entities"],
    )
    assert signals["title_jaccard"] >= 0.5  # ~0.8 en pratique
    assert signals["shared_topics"] == 2
    is_ok, reason = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is True
    assert reason == ""


def test_topical_signals_off_tempete_rejected():
    seed_tokens, seed_topics, seed_disc = _seed_signals_inputs()
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics,
        seed_disc,
        cand_title=CAND_OFF_TEMPETE["title"],
        cand_topics=CAND_OFF_TEMPETE["topics"],
        cand_entities=CAND_OFF_TEMPETE["entities"],
    )
    assert signals["title_jaccard"] < PERSPECTIVE_TITLE_JACCARD_MIN
    assert signals["shared_topics"] == 0
    is_ok, reason = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is False
    assert reason == "no_signal"


def test_topical_signals_off_avortement_rejected():
    seed_tokens, seed_topics, seed_disc = _seed_signals_inputs()
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics,
        seed_disc,
        cand_title=CAND_OFF_AVORTEMENT["title"],
        cand_topics=CAND_OFF_AVORTEMENT["topics"],
        cand_entities=CAND_OFF_AVORTEMENT["entities"],
    )
    assert signals["title_jaccard"] < PERSPECTIVE_TITLE_JACCARD_MIN
    assert signals["shared_topics"] == 0
    is_ok, _ = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is False


def test_topical_signals_external_only_title_high_jaccard_ok():
    """Pour Layer 2/3 (Google News), seul le titre est dispo. Si Jaccard ≥ seuil → OK."""
    seed_tokens = normalize_title(SEED_TITLE)
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics=set(),
        seed_disc_entities=set(),
        cand_title=CAND_ON_TOPIC["title"],
        # cand_topics et cand_entities = None (Google News : pas dispo)
    )
    assert signals["shared_topics"] is None
    assert signals["shared_entities"] is None
    assert signals["title_jaccard"] >= PERSPECTIVE_TITLE_JACCARD_MIN
    is_ok, reason = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is True
    assert reason == ""


def test_topical_signals_external_low_jaccard_rejected():
    seed_tokens = normalize_title(SEED_TITLE)
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics=set(),
        seed_disc_entities=set(),
        cand_title=CAND_OFF_TEMPETE["title"],
    )
    assert signals["title_jaccard"] < PERSPECTIVE_TITLE_JACCARD_MIN
    is_ok, reason = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is False
    assert reason == "low_jaccard"


def test_topical_signals_shared_topic_rescues_low_jaccard():
    """Si Jaccard titre faible mais 1 topic ML partagé → accepter (Layer 1)."""
    seed_tokens, seed_topics, _ = _seed_signals_inputs()
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics,
        seed_disc_entities=set(),
        cand_title="Article au titre totalement différent qui ne matche rien",
        cand_topics=["religion"],  # 1 topic en commun
        cand_entities=[],
    )
    assert signals["title_jaccard"] < PERSPECTIVE_TITLE_JACCARD_MIN
    assert signals["shared_topics"] == 1
    is_ok, _ = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is True


def test_topical_signals_2_shared_entities_rescues_low_jaccard():
    """Si Jaccard titre faible mais 2 entités discriminantes partagées → accepter."""
    seed_tokens = normalize_title(SEED_TITLE)
    # Seed avec 2 ORGs/PERSONs discriminantes
    seed_disc = {"Macron", "OMS"}
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics=set(),
        seed_disc_entities=seed_disc,
        cand_title="Titre completement different",
        cand_topics=[],
        cand_entities=[
            json.dumps({"name": "Macron", "type": "PERSON"}),
            json.dumps({"name": "OMS", "type": "ORG"}),
        ],
    )
    assert signals["shared_entities"] == 2
    is_ok, _ = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is True


def test_filter_external_perspectives_keeps_on_topic_only():
    """Test integration : filtre Layer 2/3 garde uniquement les titres similaires."""
    service = PerspectiveService()
    seed_tokens = normalize_title(SEED_TITLE)
    candidates = [
        Perspective(
            title=CAND_ON_TOPIC["title"],
            url="http://lemonde.fr/x",
            source_name="Le Monde",
            source_domain="lemonde.fr",
            bias_stance="center-left",
        ),
        Perspective(
            title=CAND_OFF_TEMPETE["title"],
            url="http://france24.com/x",
            source_name="France 24",
            source_domain="france24.com",
            bias_stance="center-left",
        ),
        Perspective(
            title=CAND_OFF_AVORTEMENT["title"],
            url="http://humanite.fr/x",
            source_name="L'Humanité",
            source_domain="humanite.fr",
            bias_stance="left",
        ),
    ]
    kept, filtered_out = service._filter_external_perspectives(seed_tokens, candidates)
    assert len(kept) == 1
    assert kept[0].source_domain == "lemonde.fr"
    assert filtered_out == 2


def test_filter_external_perspectives_disabled_via_flag(monkeypatch):
    """Si PERSPECTIVE_FILTER_ENABLED=false, le filtre est no-op."""
    monkeypatch.setattr(
        "app.services.perspective_service.PERSPECTIVE_FILTER_ENABLED", False
    )
    service = PerspectiveService()
    seed_tokens = normalize_title(SEED_TITLE)
    candidates = [
        Perspective(
            title="totalement off-topic",
            url="http://x.fr/y",
            source_name="X",
            source_domain="x.fr",
            bias_stance="left",
        ),
    ]
    kept, filtered_out = service._filter_external_perspectives(seed_tokens, candidates)
    assert len(kept) == 1
    assert filtered_out == 0


def test_topical_signals_empty_seed_title():
    """Edge case : titre seed vide → tous les candidats rejetés (Jaccard=0)."""
    signals = PerspectiveService._topical_signals(
        seed_tokens=set(),
        seed_topics=set(),
        seed_disc_entities=set(),
        cand_title="N'importe quel titre",
    )
    assert signals["title_jaccard"] == 0.0
    is_ok, reason = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is False
