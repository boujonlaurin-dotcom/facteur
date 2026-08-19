import json
from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.models.enums import SourceType
from app.services.perspective_service import (
    PERSPECTIVE_TITLE_JACCARD_MIN,
    Perspective,
    PerspectiveService,
    _strip_source_suffix,
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

    # 1. Test without exclusion — titles are stripped at ingestion
    results = await service._parse_rss(mock_rss)
    assert len(results) == 3
    assert [r.title for r in results] == [
        "Article Original",
        "Autre Article",
        "Doublon Titre",
    ]

    # 2. Test with URL exclusion
    results_url = await service._parse_rss(
        mock_rss, exclude_url="http://lemonde.fr/article1"
    )
    assert len(results_url) == 2
    assert results_url[0].title == "Autre Article"

    # 3. Test with Title exclusion (similarity check on stripped title)
    results_title = await service._parse_rss(mock_rss, exclude_title="Doublon Titre")
    titles = [r.title for r in results_title]
    assert "Doublon Titre" not in titles
    assert len(results_title) == 2


def test_strip_source_suffix_uses_known_source_name():
    """Primary path: exact match against <source> element."""
    assert (
        _strip_source_suffix("Macron annonce une réforme - Le Monde", "Le Monde")
        == "Macron annonce une réforme"
    )
    # Em-dash variant
    assert (
        _strip_source_suffix("Sujet brûlant – Libération", "Libération")
        == "Sujet brûlant"
    )
    # Pipe variant
    assert _strip_source_suffix("Headline | The Guardian", "The Guardian") == "Headline"
    # Case-insensitive
    assert _strip_source_suffix("Foo - LE MONDE", "Le Monde") == "Foo"


def test_strip_source_suffix_fallback_regex_when_source_mismatches():
    """When <source> doesn't match (Google News localized variant), fallback."""
    # `Figaro` doesn't equal `Le Figaro` exactly → fallback regex catches it.
    assert (
        _strip_source_suffix("Autre Article - Figaro", "Le Figaro") == "Autre Article"
    )


def test_strip_source_suffix_preserves_legitimate_dash_titles():
    """Hyphens in real titles must NOT trigger a strip."""
    # Suffix too long (>40 chars after separator)
    assert (
        _strip_source_suffix(
            "Flipper One - Le Linux de poche qui terrifie ses propres créateurs",
            None,
        )
        == "Flipper One - Le Linux de poche qui terrifie ses propres créateurs"
    )
    # Contains a colon → not a source suffix
    assert (
        _strip_source_suffix("Accord États-Unis – Iran : Finkielkraut espère", None)
        == "Accord États-Unis – Iran : Finkielkraut espère"
    )
    # Numeric date suffix (Google News-style timestamp on radio shows)
    assert (
        _strip_source_suffix("Le Grand entretien - 26/05", None)
        == "Le Grand entretien - 26/05"
    )


def test_strip_source_suffix_handles_empty_and_whitespace():
    assert _strip_source_suffix("", "Le Monde") == ""
    assert _strip_source_suffix("Foo - Le Monde  ", "Le Monde") == "Foo"
    assert _strip_source_suffix("Foo", "Le Monde") == "Foo"


def _coverage_content(
    domain: str,
    *,
    title: str = "Le Parlement adopte la réforme des retraites",
    bias: str | None = None,
    source_type=None,
    topics: list[str] | None = None,
):
    return SimpleNamespace(
        id=uuid4(),
        title=title,
        url=f"https://{domain}/article",
        description="Description",
        topics=topics if topics is not None else ["politique", "retraites"],
        entities=[],
        language="fr",
        published_at=datetime.now(UTC),
        source=SimpleNamespace(
            name=domain,
            url=f"https://{domain}/",
            bias_stance=(SimpleNamespace(value=bias) if bias else None),
            reliability_score=None,
            type=source_type,
        ),
    )


@pytest.mark.asyncio
async def test_coverage_universe_keeps_fourteen_domains_including_unknown_bias():
    """A single known political bias must not collapse a 14-outlet topic."""
    service = PerspectiveService()
    contents = [
        _coverage_content(
            f"media-{index}.example",
            bias="center" if index == 0 else None,
        )
        for index in range(14)
    ]

    universe = await service.build_coverage_universe(contents[0], contents, [])

    assert len(universe) == 14
    assert universe[0].content_id == str(contents[0].id)
    assert sum(p.bias_stance != "unknown" for p in universe) == 1
    assert sum(p.bias_stance == "unknown" for p in universe) == 13
    assert len({p.source_domain for p in universe}) == 14


@pytest.mark.asyncio
async def test_coverage_universe_rejects_off_topic_duplicates_and_aggregators():
    service = PerspectiveService()
    pivot = _coverage_content("pivot.example", bias="center")
    duplicate = _coverage_content("pivot.example", bias="right")
    off_topic = _coverage_content(
        "weather.example",
        title="Une tempête de neige paralyse plusieurs régions américaines",
        topics=["meteo"],
    )
    reddit_repost = _coverage_content(
        "reddit.com",
        source_type=SourceType.REDDIT,
    )
    discovered = [
        Perspective(
            title=pivot.title,
            url="https://news.google.com/story",
            source_name="Google News",
            source_domain="news.google.com",
            bias_stance="unknown",
        ),
        Perspective(
            title=pivot.title,
            url="https://pivot.example/duplicate",
            source_name="Pivot duplicate",
            source_domain="www.pivot.example",
            bias_stance="unknown",
        ),
        Perspective(
            title=pivot.title,
            url="https://other.example/story",
            source_name="Other",
            source_domain="other.example",
            bias_stance="unknown",
        ),
    ]

    universe = await service.build_coverage_universe(
        pivot,
        [pivot, duplicate, off_topic, reddit_repost],
        discovered,
    )

    assert [p.source_domain for p in universe] == [
        "pivot.example",
        "other.example",
    ]
    assert universe[1].bias_stance == "unknown"


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


def test_topical_signals_shared_topic_alone_insufficient_with_zero_jaccard():
    """1 topic partagé seul + Jaccard ≈ 0 → rejeter (faux-positif "Trump partout").

    Un topic générique ("politics", "religion"…) partagé sans entité discriminante
    ET sans aucune similarité de titre ne suffit plus à valider une perspective.
    Empêche ex: Congo/Trump vs Ukraine/Trump via seul topic "politics".
    """
    seed_tokens, seed_topics, _ = _seed_signals_inputs()
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics,
        seed_disc_entities=set(),
        cand_title="Article au titre totalement différent qui ne matche rien",
        cand_topics=["religion"],  # 1 topic en commun, mais 0 entité, jaccard ≈ 0
        cand_entities=[],
    )
    assert signals["title_jaccard"] < PERSPECTIVE_TITLE_JACCARD_MIN
    assert signals["shared_topics"] == 1
    is_ok, reason = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is False
    assert reason == "no_signal"


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


# ---------------------------------------------------------------------------
# Calibration Iter 1 — floor « weak double signal » 0.08 → 0.12
# Ref : docs/maintenance/maintenance-clustering-calibration.md
# Pool junk-drawer « Trump » : deux articles ne partageant que l'entité saillante
# (Trump) + un topic générique (geopolitics) mais parlant d'événements distincts.
# ---------------------------------------------------------------------------

# Le cas Cuba/Chagos du plan : Jaccard ≈ 0.091, dans la fenêtre [0.08, 0.12).
# Avant Iter 1 (floor 0.08) → accepté à tort via « weak double signal » (FP).
# Après Iter 1 (floor 0.12) → rejeté.
TRUMP_CUBA = {
    "title": "Cuba : l'ultimatum économique de Trump",
    "topics": ["geopolitics", "usa"],
    "entities": [json.dumps({"name": "Trump", "type": "PERSON"})],
}
TRUMP_CHAGOS = {
    "title": (
        "Après le Groenland, Donald Trump convoite un autre territoire, "
        "l'archipel des îles Chagos"
    ),
    "topics": ["geopolitics", "usa"],
    "entities": [json.dumps({"name": "Trump", "type": "PERSON"})],
}

# Vrai intra-événement (mobilisation anti-projet immobilier Trump en Albanie) :
# Jaccard ≈ 0.143 ≥ 0.12 → reste accepté après Iter 1 (rappel préservé).
TRUMP_ALBANIE_A = {
    "title": (
        "En Albanie, la mobilisation prend de l'ampleur contre le projet "
        "immobilier de luxe porté par Trump"
    ),
    "topics": ["geopolitics", "usa"],
    "entities": [json.dumps({"name": "Trump", "type": "PERSON"})],
}
TRUMP_ALBANIE_B = {
    "title": (
        "« Ce serait fatal » : des Albanais continuent à protester contre un "
        "projet immobilier lié à Trump"
    ),
    "topics": ["geopolitics", "usa"],
    "entities": [json.dumps({"name": "Trump", "type": "PERSON"})],
}


def test_trump_cross_event_rejected_after_floor_calibration():
    """Cuba ↔ Chagos : même entité Trump + topic geopolitics, événements distincts.

    Jaccard ≈ 0.091 tombe dans la fenêtre [ancien floor 0.08, nouveau floor 0.12) :
    c'était la fuite « weak double signal » (cf. capture PO « cluster Trump »).
    Après calibration Iter 1, la porte rejette la paire.
    """
    from app.services.perspective_service import PERSPECTIVE_MIN_JACCARD_FLOOR

    seed_tokens = normalize_title(TRUMP_CUBA["title"])
    seed_disc = {"Trump"}
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics={"geopolitics", "usa"},
        seed_disc_entities=seed_disc,
        cand_title=TRUMP_CHAGOS["title"],
        cand_topics=TRUMP_CHAGOS["topics"],
        cand_entities=TRUMP_CHAGOS["entities"],
    )
    # Le signal qui fuyait : topic + entité partagés, Jaccard faible mais > 0.08.
    assert signals["shared_topics"] >= 1
    assert signals["shared_entities"] >= 1
    assert 0.08 <= signals["title_jaccard"] < PERSPECTIVE_MIN_JACCARD_FLOOR
    # La porte calibrée (floor 0.12) doit rejeter.
    is_ok, reason = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is False
    assert reason == "no_signal"


def test_trump_intra_event_still_accepted_after_floor_calibration():
    """Albanie ↔ Albanie : même événement, Jaccard ≈ 0.143 ≥ 0.12 → reste accepté.

    Garde-fou de rappel : le durcissement du floor ne doit pas casser les vraies
    paires intra-événement multi-sources qui dépassent le nouveau seuil.
    """
    from app.services.perspective_service import PERSPECTIVE_MIN_JACCARD_FLOOR

    seed_tokens = normalize_title(TRUMP_ALBANIE_A["title"])
    signals = PerspectiveService._topical_signals(
        seed_tokens,
        seed_topics={"geopolitics", "usa"},
        seed_disc_entities={"Trump"},
        cand_title=TRUMP_ALBANIE_B["title"],
        cand_topics=TRUMP_ALBANIE_B["topics"],
        cand_entities=TRUMP_ALBANIE_B["entities"],
    )
    assert signals["title_jaccard"] >= PERSPECTIVE_MIN_JACCARD_FLOOR
    assert signals["shared_topics"] >= 1
    assert signals["shared_entities"] >= 1
    is_ok, reason = PerspectiveService._is_topically_coherent(signals)
    assert is_ok is True
    assert reason == ""


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


# ─── Analyse Facteur — prompt v2 (« établi » vs « en débat ») ─────────────────
# Cf. docs/maintenance/maintenance-analyse-facteur-prompt-v2.md


class _FakeLLMClient:
    """Capture les arguments passés à `chat_json` sans appeler Mistral."""

    calls: list[dict] = []
    response: dict | None = {
        "analysis": "Faits partagés.\n\n→ **Objet du désaccord** : A vs B.",
        "divergence_level": "medium",
    }

    def __init__(self, *args, **kwargs):
        pass

    @property
    def is_ready(self) -> bool:
        return True

    async def chat_json(self, **kwargs):
        type(self).calls.append(kwargs)
        return type(self).response

    async def close(self):
        return None


@pytest.fixture
def fake_llm(monkeypatch):
    """Patch le client LLM importé dans `analyze_divergences` (import local)."""
    import app.services.editorial.llm_client as llm_module

    _FakeLLMClient.calls = []
    _FakeLLMClient.response = {
        "analysis": "Faits partagés.\n\n→ **Objet du désaccord** : A vs B.",
        "divergence_level": "medium",
    }
    monkeypatch.setattr(llm_module, "EditorialLLMClient", _FakeLLMClient)
    return _FakeLLMClient


PERSPECTIVES_FIXTURE = [
    {
        "title": "Budget 2026 : 12 milliards d'économies annoncés",
        "source_name": "Les Échos",
        "bias_stance": "center-right",
        "description": "D" * 800,
    },
    {
        "title": "Budget 2026 : un tour de vis sur la santé",
        "source_name": "Libération",
        "bias_stance": "left",
        "description": "Un résumé court.",
    },
]


async def _run_analysis(**overrides):
    service = PerspectiveService()
    kwargs = {
        "article_title": "Bercy présente le budget 2026",
        "source_name": "Le Monde",
        "source_bias": "center-left",
        "perspectives": PERSPECTIVES_FIXTURE,
        "article_description": "R" * 1500,
    }
    kwargs.update(overrides)
    return await service.analyze_divergences(**kwargs)


@pytest.mark.asyncio
async def test_analyze_divergences_prompt_targets_substance(fake_llm):
    """Le prompt doit demander « ce qu'on sait / ce qui fait débat », pas une
    lexicométrie des titres (plainte PO : analyse trop centrée sur les
    variations de formulation)."""
    await _run_analysis()

    assert len(fake_llm.calls) == 1
    system = fake_llm.calls[0]["system"]

    # Structure v2 attendue
    for directive in (
        "CE QUI EST ÉTABLI",
        "CE QUI FAIT DÉBAT",
        "POINTS LITIGIEUX",
        "TEST DE RECEVABILITÉ",
    ):
        assert directive in system, f"directive manquante : {directive}"

    # La section « établi » n'est plus une phrase unique famélique
    assert "45-75 mots" in system
    assert "15-25 mots" not in system

    # Les consignes de lexicométrie v1 ont disparu comme OBJECTIF
    for banned in (
        "marqueur d'opinion",
        "mots forts vs neutres",
        "REGROUPE les médias",
        "emploient le terme",
    ):
        assert banned not in system, f"consigne v1 encore présente : {banned}"

    # Le lexique reste admis, mais borné à un rôle de preuve
    assert "au plus UN terme cité entre guillemets" in system
    assert "jamais comme sujet de la ligne" in system

    # « d'après leurs titres » passe d'obligation à interdiction
    assert "d'après leurs titres" in system
    assert "Interdits :" in system
    interdits_block = system.split("Interdits :", 1)[1]
    assert "d'après leurs titres" in interdits_block


@pytest.mark.asyncio
async def test_analyze_divergences_preserves_two_section_contract(fake_llm):
    """Le prompt doit continuer d'imposer le séparateur `\\n\\n` entre les deux
    sections : c'est le contrat lu par `splitAnalysisSections` côté mobile."""
    await _run_analysis()

    system = fake_llm.calls[0]["system"]
    assert "Saut de ligne double (\\n\\n)" in system
    # Les puces de la section 2 restent préfixées "→ " (rendu markdown mobile)
    assert '"→ "' in system
    # divergence_level : mêmes valeurs, consommées par polarization_bonus()
    for level in ('"low"', '"medium"', '"high"'):
        assert level in system


@pytest.mark.asyncio
async def test_analyze_divergences_feeds_wider_context(fake_llm):
    """Fenêtres de matière élargies : sans résumé, le modèle se rabat sur les
    titres — exactement le biais qu'on corrige."""
    from app.services.perspective_service import (
        PERSPECTIVE_DESC_CHARS,
        REFERENCE_DESC_CHARS,
    )

    await _run_analysis()

    call = fake_llm.calls[0]
    user_message = call["user_message"]

    assert PERSPECTIVE_DESC_CHARS == 450
    assert REFERENCE_DESC_CHARS == 900
    # Résumé de perspective tronqué à la nouvelle borne (ni 300, ni 800)
    assert "D" * PERSPECTIVE_DESC_CHARS in user_message
    assert "D" * (PERSPECTIVE_DESC_CHARS + 1) not in user_message
    # Résumé de l'article de référence tronqué à la nouvelle borne
    assert "R" * REFERENCE_DESC_CHARS in user_message
    assert "R" * (REFERENCE_DESC_CHARS + 1) not in user_message
    # Ancrage factuel renforcé + budget de sortie pour la section « établi »
    assert call["temperature"] == 0.3
    assert call["max_tokens"] == 900


@pytest.mark.asyncio
async def test_analyze_divergences_json_contract_unchanged(fake_llm):
    """Contrat de retour inchangé : dict {analysis, divergence_level}, et None
    si le LLM ne renvoie pas de clé `analysis`."""
    result = await _run_analysis()
    assert result == {
        "analysis": "Faits partagés.\n\n→ **Objet du désaccord** : A vs B.",
        "divergence_level": "medium",
    }
    # Le premier \n\n sépare bien deux sections non vides (contrat mobile)
    essentiel, _, divergent = result["analysis"].partition("\n\n")
    assert essentiel.strip()
    assert divergent.strip().startswith("→")

    fake_llm.response = {"divergence_level": "high"}
    assert await _run_analysis() is None


@pytest.mark.asyncio
async def test_analyze_divergences_no_perspectives_skips_llm(fake_llm):
    """Aucune perspective → pas d'appel Mistral (garde-fou de coût inchangé)."""
    assert await _run_analysis(perspectives=[]) is None
    assert fake_llm.calls == []
