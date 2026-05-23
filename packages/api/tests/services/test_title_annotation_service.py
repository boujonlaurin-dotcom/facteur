"""Tests for TitleAnnotationService (Story 7.4 — diff highlighting backend).

Hermetic: the tests do not depend on spaCy or the `fr_core_news_md` model.
A `FakeNlp` callable (shared with router tests) mimics the minimal subset
of the spaCy Doc / Token / Ent API consumed by `compute_strong_tokens`.
"""

from uuid import uuid4

import pytest
import pytest_asyncio
from sqlalchemy import select

from app.models.cluster_title_annotation import ClusterTitleAnnotation
from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.services.title_annotation_service import TitleAnnotationService
from tests.fixtures.fake_spacy import (
    FakeDoc,
    FakeEnt,
    FakeNlp,
    FakeToken,
    service_with_nlp,
)


# --- compute_strong_tokens --------------------------------------------------


def test_compute_strong_tokens_filters_stopwords_and_keeps_noun_adj_verb_propn():
    title = "Tsahal frappe une cible brutale"
    doc = FakeDoc(
        tokens=[
            FakeToken("Tsahal", 0, "PROPN", "Tsahal"),
            FakeToken("frappe", 7, "VERB", "frapper"),
            FakeToken("une", 14, "DET", "un", is_stop=True),
            FakeToken("cible", 18, "NOUN", "cible"),
            FakeToken("brutale", 24, "ADJ", "brutal"),
        ]
    )
    svc = service_with_nlp(FakeNlp({title: doc}))

    tokens = svc.compute_strong_tokens(title)

    assert [t["text"] for t in tokens] == ["Tsahal", "frappe", "cible", "brutale"]
    assert {t["pos"] for t in tokens} == {"PROPN", "VERB", "NOUN", "ADJ"}
    assert tokens[0]["start"] == 0
    assert tokens[0]["end"] == 6


def test_compute_strong_tokens_extracts_entities_from_ner():
    title = "Macron rencontre Merkel à Berlin"
    doc = FakeDoc(
        tokens=[
            FakeToken("Macron", 0, "PROPN", "Macron"),
            FakeToken("rencontre", 7, "VERB", "rencontrer"),
            FakeToken("Merkel", 17, "PROPN", "Merkel"),
            FakeToken("à", 24, "ADP", "à", is_stop=True),
            FakeToken("Berlin", 26, "PROPN", "Berlin"),
        ],
        ents=[
            FakeEnt(0, 6, "PER"),
            FakeEnt(17, 23, "PER"),
            FakeEnt(26, 32, "LOC"),
        ],
    )
    svc = service_with_nlp(FakeNlp({title: doc}))

    by_text = {t["text"]: t for t in svc.compute_strong_tokens(title)}

    assert by_text["Macron"]["entity_kind"] == "PER"
    assert by_text["Merkel"]["entity_kind"] == "PER"
    assert by_text["Berlin"]["entity_kind"] == "LOC"
    assert "entity_kind" not in by_text["rencontre"]


def test_compute_strong_tokens_filters_against_project_stopword_list():
    """Even if spaCy keeps a word, FRENCH_STOP_WORDS (project-wide) trumps it.

    FRENCH_STOP_WORDS is stored accent-stripped, so the service must strip
    accents before lookup — otherwise accented stop words like "société"
    or "analyse" slip through.
    """
    title = "Société Tsahal"
    doc = FakeDoc(
        tokens=[
            FakeToken("Société", 0, "NOUN", "société"),
            FakeToken("Tsahal", 8, "PROPN", "Tsahal"),
        ]
    )
    svc = service_with_nlp(FakeNlp({title: doc}))

    kept = {t["text"] for t in svc.compute_strong_tokens(title)}
    assert "Société" not in kept  # rejected by FRENCH_STOP_WORDS via accent strip
    assert "Tsahal" in kept


def test_compute_strong_tokens_returns_empty_when_nlp_missing():
    svc = service_with_nlp(None)
    assert svc.compute_strong_tokens("Un titre quelconque") == []


# --- diff_spans -------------------------------------------------------------


def _tok(text, lemma, pos="NOUN", start=0, entity_kind=None):
    out = {"start": start, "end": start + len(text), "text": text,
           "lemma": lemma, "pos": pos}
    if entity_kind:
        out["entity_kind"] = entity_kind
    return out


def test_diff_spans_identical_lemmas_returns_empty():
    ref = [_tok("ministre", "ministre"), _tok("réforme", "réforme", start=10)]
    alt = [_tok("Ministre", "ministre"), _tok("Réformes", "réforme", start=10)]
    svc = service_with_nlp(None)
    assert svc.diff_spans(ref, alt, "left") == []


def test_diff_spans_caps_at_4_with_priority_editorial_first():
    """ADJ → VERB → NOUN → PROPN → entity. Entities are bumped last."""
    ref = [_tok("été", "été")]
    alt = [
        _tok("dénoncer", "dénoncer", pos="VERB", start=0),
        _tok("austérité", "austérité", pos="NOUN", start=10),
        _tok("brutale", "brutale", pos="ADJ", start=20),
        _tok("Macron", "Macron", pos="PROPN", start=30, entity_kind="PER"),
        _tok("Bercy", "Bercy", pos="PROPN", start=40, entity_kind="ORG"),
        _tok("présentée", "présenter", pos="VERB", start=50),
    ]
    svc = service_with_nlp(None)
    spans = svc.diff_spans(ref, alt, "left")

    assert len(spans) == 4
    texts = [s["text"] for s in spans]
    assert texts[0] == "brutale"  # ADJ wins
    assert texts[1] in ("dénoncer", "présentée")  # VERB next
    assert texts[2] in ("dénoncer", "présentée")
    assert texts[3] == "austérité"  # NOUN closes
    assert "Macron" not in texts  # entities bumped
    assert "Bercy" not in texts


def test_diff_spans_demotes_entity_when_editorial_tokens_present():
    """When a divergent VERB + ADJ exist, an NER entity loses its slot."""
    ref: list[dict] = []
    alt = [
        _tok("Acmecorp", "acmecorp", pos="PROPN", start=0, entity_kind="ORG"),
        _tok("crushes", "crusher", pos="VERB", start=10),
        _tok("brutale", "brutal", pos="ADJ", start=20),
    ]
    svc = service_with_nlp(None)
    spans = svc.diff_spans(ref, alt, "left")
    texts = [s["text"] for s in spans]

    assert texts == ["brutale", "crushes", "Acmecorp"]
    # The entity is still highlighted here (cap is 4, only 3 candidates),
    # but it ranks last — proves the relative order, not exclusion.


def test_diff_spans_keeps_entity_when_no_editorial_alternative():
    """Pure factual title: an entity is the only divergent token → kept."""
    ref = [_tok("réforme", "réforme")]
    alt = [
        _tok("Examplestan", "examplestan", pos="PROPN", start=0, entity_kind="LOC"),
    ]
    svc = service_with_nlp(None)
    spans = svc.diff_spans(ref, alt, "left")

    assert [s["text"] for s in spans] == ["Examplestan"]


def test_diff_spans_passes_bias_through_unchanged():
    """Each span carries the alt source's raw bias_stance string (no mapping)."""
    ref: list[dict] = []
    alt = [_tok("guerre", "guerre")]
    svc = service_with_nlp(None)

    for bias in ("left", "center-left", "center", "center-right",
                 "right", "alternative", "specialized", "unknown"):
        spans = svc.diff_spans(ref, alt, bias)
        assert spans[0]["bias"] == bias


def test_diff_spans_preserves_offsets():
    ref: list[dict] = []
    alt = [_tok("guerre", "guerre", start=15)]
    svc = service_with_nlp(None)
    spans = svc.diff_spans(ref, alt, "left")
    assert spans[0]["start"] == 15
    assert spans[0]["end"] == 21


# --- compute_shared_tokens --------------------------------------------------


def test_compute_shared_tokens_returns_alt_spans_with_matching_lemma():
    ref = [_tok("ministre", "ministre"), _tok("réforme", "réforme", start=10)]
    alt = [
        _tok("Ministre", "ministre", start=0),
        _tok("brutale", "brutal", pos="ADJ", start=10),
        _tok("Réformes", "réforme", start=20),
    ]
    svc = service_with_nlp(None)

    shared = svc.compute_shared_tokens(ref, alt)
    texts = [s["text"] for s in shared]

    assert texts == ["Ministre", "Réformes"]
    # No bias / pos fields exposed — just position + text
    assert all(set(s.keys()) == {"start", "end", "text"} for s in shared)


def test_compute_shared_tokens_preserves_alt_offsets():
    ref = [_tok("guerre", "guerre")]
    alt = [_tok("guerre", "guerre", start=42)]
    svc = service_with_nlp(None)

    shared = svc.compute_shared_tokens(ref, alt)
    assert shared == [{"start": 42, "end": 48, "text": "guerre"}]


def test_compute_shared_tokens_empty_when_no_overlap():
    ref = [_tok("paix", "paix")]
    alt = [_tok("guerre", "guerre", start=10)]
    svc = service_with_nlp(None)
    assert svc.compute_shared_tokens(ref, alt) == []


def test_compute_shared_tokens_is_uncapped():
    """Unlike diff_spans, shared has no MAX cap — the front renders them all."""
    ref = [_tok(f"w{i}", f"w{i}", start=i * 5) for i in range(8)]
    alt = [_tok(f"W{i}", f"w{i}", start=i * 5) for i in range(8)]
    svc = service_with_nlp(None)
    assert len(svc.compute_shared_tokens(ref, alt)) == 8


# --- compute_reference_pivot ------------------------------------------------


def test_compute_reference_pivot_returns_first_verb():
    ref = [
        _tok("Macron", "Macron", pos="PROPN", start=0),
        _tok("annonce", "annoncer", pos="VERB", start=7),
        _tok("réforme", "réforme", pos="NOUN", start=15),
        _tok("présente", "présenter", pos="VERB", start=23),
    ]
    svc = service_with_nlp(None)
    pivot = svc.compute_reference_pivot(ref)
    assert pivot == {"start": 7, "end": 14, "text": "annonce"}


def test_compute_reference_pivot_none_when_no_verb():
    ref = [
        _tok("Macron", "Macron", pos="PROPN"),
        _tok("réforme", "réforme", pos="NOUN", start=7),
    ]
    svc = service_with_nlp(None)
    assert svc.compute_reference_pivot(ref) is None


def test_compute_reference_pivot_none_when_empty():
    svc = service_with_nlp(None)
    assert svc.compute_reference_pivot([]) is None


# --- get_or_compute_cluster_annotations -------------------------------------


@pytest_asyncio.fixture
async def cluster_fixture(db_session):
    """Create a source + 3 contents sharing a cluster_id."""
    from datetime import UTC, datetime

    source = Source(
        id=uuid4(),
        name="Test Source",
        url="https://example.com",
        feed_url=f"https://example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()

    cluster_id = uuid4()
    contents = []
    titles_urls = [
        ("Macron annonce une réforme", "https://ex.com/a"),
        ("Macron impose une réforme brutale", "https://ex.com/b"),
        ("Macron présente un projet", "https://ex.com/c"),
    ]
    for title, url in titles_urls:
        c = Content(
            id=uuid4(),
            source_id=source.id,
            title=title,
            url=url,
            published_at=datetime.now(UTC),
            content_type=ContentType.ARTICLE,
            guid=url,
            cluster_id=cluster_id,
        )
        db_session.add(c)
        contents.append(c)
    await db_session.commit()
    return {"cluster_id": cluster_id, "contents": contents}


def _trivial_nlp(titles: list[str]) -> FakeNlp:
    """One single-PROPN doc per title — enough to exercise the cache path."""
    return FakeNlp({t: FakeDoc(tokens=[FakeToken(t, 0, "PROPN", t.lower())])
                    for t in titles})


@pytest.mark.asyncio
async def test_get_or_compute_inserts_on_first_call_and_reads_cache_second(
    db_session, cluster_fixture
):
    titles = [c.title for c in cluster_fixture["contents"]]
    nlp = _trivial_nlp(titles)
    svc = service_with_nlp(nlp)

    first = await svc.get_or_compute_cluster_annotations(
        db_session, cluster_fixture["cluster_id"]
    )
    assert len(first.tokens_by_id) == 3
    assert nlp.call_count == 3
    rows = (
        await db_session.execute(
            select(ClusterTitleAnnotation).where(
                ClusterTitleAnnotation.cluster_id == cluster_fixture["cluster_id"]
            )
        )
    ).scalars().all()
    assert len(rows) == 3
    assert all(r.model_version == "v1-spacy-fr_md" for r in rows)
    assert all(r.semantic_equiv is None for r in rows)

    nlp.call_count = 0
    second = await svc.get_or_compute_cluster_annotations(
        db_session, cluster_fixture["cluster_id"]
    )
    assert nlp.call_count == 0
    assert second.tokens_by_id.keys() == first.tokens_by_id.keys()


@pytest.mark.asyncio
async def test_get_or_compute_url_map_is_populated(db_session, cluster_fixture):
    titles = [c.title for c in cluster_fixture["contents"]]
    svc = service_with_nlp(_trivial_nlp(titles))

    result = await svc.get_or_compute_cluster_annotations(
        db_session, cluster_fixture["cluster_id"]
    )

    expected_urls = {c.url: c.id for c in cluster_fixture["contents"]}
    assert result.id_by_url == expected_urls


@pytest.mark.asyncio
async def test_get_or_compute_returns_empty_for_missing_nlp(
    db_session, cluster_fixture
):
    svc = service_with_nlp(None)
    result = await svc.get_or_compute_cluster_annotations(
        db_session, cluster_fixture["cluster_id"]
    )
    assert result.tokens_by_id == {}
    # URL map is still built (no spaCy needed for that)
    assert len(result.id_by_url) == 3


@pytest.mark.asyncio
async def test_get_or_compute_returns_empty_for_unknown_cluster(db_session):
    svc = service_with_nlp(_trivial_nlp([]))
    result = await svc.get_or_compute_cluster_annotations(db_session, uuid4())
    assert result.tokens_by_id == {}
    assert result.id_by_url == {}


@pytest.mark.asyncio
async def test_get_or_compute_does_not_raise_on_partial_cache(
    db_session, cluster_fixture
):
    """Pre-populate cache for 1 of 3 contents → other 2 are computed & persisted."""
    contents = cluster_fixture["contents"]
    pre_seeded = ClusterTitleAnnotation(
        cluster_id=cluster_fixture["cluster_id"],
        content_id=contents[0].id,
        strong_tokens=[{"start": 0, "end": 5, "text": "seed",
                        "lemma": "seed", "pos": "NOUN"}],
        model_version="v1-spacy-fr_md",
    )
    db_session.add(pre_seeded)
    await db_session.commit()

    titles = [c.title for c in contents]
    nlp = _trivial_nlp(titles)
    svc = service_with_nlp(nlp)

    result = await svc.get_or_compute_cluster_annotations(
        db_session, cluster_fixture["cluster_id"]
    )

    assert nlp.call_count == 2  # only the 2 missing titles
    assert result.tokens_by_id[contents[0].id][0]["text"] == "seed"
    rows = (
        await db_session.execute(
            select(ClusterTitleAnnotation).where(
                ClusterTitleAnnotation.cluster_id == cluster_fixture["cluster_id"]
            )
        )
    ).scalars().all()
    assert len(rows) == 3

# --- LLM persistence (PR 3 Phase 4) ------------------------------------------


def test_compute_cluster_signature_is_deterministic_and_order_invariant():
    a = uuid4()
    b = uuid4()
    c = uuid4()
    sig_abc = TitleAnnotationService.compute_cluster_signature([a, b, c])
    sig_cba = TitleAnnotationService.compute_cluster_signature([c, b, a])
    assert sig_abc == sig_cba
    assert len(sig_abc) == 16


def test_compute_cluster_signature_changes_when_membership_changes():
    a = uuid4()
    b = uuid4()
    c = uuid4()
    sig_ab = TitleAnnotationService.compute_cluster_signature([a, b])
    sig_abc = TitleAnnotationService.compute_cluster_signature([a, b, c])
    assert sig_ab != sig_abc


def test_compute_cluster_signature_empty():
    sig = TitleAnnotationService.compute_cluster_signature([])
    assert isinstance(sig, str) and len(sig) == 16


@pytest_asyncio.fixture
async def cluster_with_spacy_rows(db_session, cluster_fixture):
    """Seed ClusterTitleAnnotation rows (spaCy-side) for the cluster."""
    for c in cluster_fixture["contents"]:
        db_session.add(
            ClusterTitleAnnotation(
                cluster_id=cluster_fixture["cluster_id"],
                content_id=c.id,
                strong_tokens=[],
                model_version="v1-spacy-fr_md",
            )
        )
    await db_session.commit()
    return cluster_fixture


@pytest.mark.asyncio
async def test_get_llm_annotations_returns_empty_when_no_semantic_equiv(
    db_session, cluster_with_spacy_rows
):
    svc = service_with_nlp(_trivial_nlp([]))
    result = await svc.get_llm_annotations(
        db_session,
        cluster_with_spacy_rows["cluster_id"],
        llm_version="mistral-medium-latest-v1",
        cluster_signature="any",
    )
    assert result == {}


@pytest.mark.asyncio
async def test_write_then_read_llm_annotations_round_trip(
    db_session, cluster_with_spacy_rows
):
    svc = service_with_nlp(_trivial_nlp([]))
    cluster_id = cluster_with_spacy_rows["cluster_id"]
    contents = cluster_with_spacy_rows["contents"]
    sig = TitleAnnotationService.compute_cluster_signature([c.id for c in contents])

    annotations = {
        contents[0].id: {
            "target_spans": [
                {"start": 0, "end": 6, "text": "Macron",
                 "category": "editorial_angle", "weight": 1.0,
                 "justification": "test"}
            ],
            "exclude_spans": [],
            "notes": "",
            "confidence": 0.9,
        },
        contents[1].id: {
            "target_spans": [],
            "exclude_spans": [],
            "notes": "empty",
            "confidence": None,
        },
    }
    n = await svc.write_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1",
        cluster_signature=sig,
        annotations=annotations,
    )
    assert n == 2

    read = await svc.get_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1", cluster_signature=sig,
    )
    assert set(read.keys()) == {contents[0].id, contents[1].id}
    assert read[contents[0].id]["target_spans"][0]["text"] == "Macron"
    assert read[contents[0].id]["llm_version"] == "mistral-medium-latest-v1"
    assert read[contents[0].id]["cluster_signature"] == sig
    assert read[contents[1].id]["notes"] == "empty"


@pytest.mark.asyncio
async def test_get_llm_annotations_filters_by_llm_version(
    db_session, cluster_with_spacy_rows
):
    svc = service_with_nlp(_trivial_nlp([]))
    cluster_id = cluster_with_spacy_rows["cluster_id"]
    contents = cluster_with_spacy_rows["contents"]
    sig = TitleAnnotationService.compute_cluster_signature([c.id for c in contents])

    await svc.write_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1", cluster_signature=sig,
        annotations={contents[0].id: {"target_spans": [], "exclude_spans": []}},
    )

    # Querying a different version → empty
    other = await svc.get_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-large-latest-v1", cluster_signature=sig,
    )
    assert other == {}

    same = await svc.get_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1", cluster_signature=sig,
    )
    assert set(same.keys()) == {contents[0].id}


@pytest.mark.asyncio
async def test_get_llm_annotations_filters_by_cluster_signature(
    db_session, cluster_with_spacy_rows
):
    svc = service_with_nlp(_trivial_nlp([]))
    cluster_id = cluster_with_spacy_rows["cluster_id"]
    contents = cluster_with_spacy_rows["contents"]
    old_sig = TitleAnnotationService.compute_cluster_signature([c.id for c in contents])

    await svc.write_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1", cluster_signature=old_sig,
        annotations={contents[0].id: {"target_spans": [], "exclude_spans": []}},
    )

    # Cluster composition changed → signature change → cache invalidated
    new_sig = TitleAnnotationService.compute_cluster_signature(
        [c.id for c in contents] + [uuid4()]
    )
    assert new_sig != old_sig
    invalidated = await svc.get_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1", cluster_signature=new_sig,
    )
    assert invalidated == {}


@pytest.mark.asyncio
async def test_write_llm_annotations_skips_missing_rows(
    db_session, cluster_with_spacy_rows
):
    svc = service_with_nlp(_trivial_nlp([]))
    cluster_id = cluster_with_spacy_rows["cluster_id"]
    ghost = uuid4()  # content_id non présent
    n = await svc.write_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1",
        cluster_signature="sig",
        annotations={ghost: {"target_spans": [], "exclude_spans": []}},
    )
    assert n == 0


@pytest.mark.asyncio
async def test_write_llm_annotations_empty_dict_is_noop(
    db_session, cluster_with_spacy_rows
):
    svc = service_with_nlp(_trivial_nlp([]))
    n = await svc.write_llm_annotations(
        db_session,
        cluster_with_spacy_rows["cluster_id"],
        llm_version="mistral-medium-latest-v1",
        cluster_signature="sig",
        annotations={},
    )
    assert n == 0


@pytest.mark.asyncio
async def test_write_llm_annotations_overwrites_existing_semantic_equiv(
    db_session, cluster_with_spacy_rows
):
    svc = service_with_nlp(_trivial_nlp([]))
    cluster_id = cluster_with_spacy_rows["cluster_id"]
    contents = cluster_with_spacy_rows["contents"]
    sig = TitleAnnotationService.compute_cluster_signature([c.id for c in contents])

    await svc.write_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1", cluster_signature=sig,
        annotations={contents[0].id: {
            "target_spans": [{"start": 0, "end": 1, "text": "M",
                              "category": "editorial_angle", "weight": 0.5}],
            "exclude_spans": [],
        }},
    )

    # Second write with different content overrides the first
    await svc.write_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1", cluster_signature=sig,
        annotations={contents[0].id: {
            "target_spans": [],
            "exclude_spans": [{"start": 0, "end": 1, "text": "M",
                              "category": "pivot_entity"}],
            "notes": "override",
        }},
    )

    read = await svc.get_llm_annotations(
        db_session, cluster_id,
        llm_version="mistral-medium-latest-v1", cluster_signature=sig,
    )
    assert read[contents[0].id]["target_spans"] == []
    assert read[contents[0].id]["exclude_spans"][0]["category"] == "pivot_entity"
    assert read[contents[0].id]["notes"] == "override"

