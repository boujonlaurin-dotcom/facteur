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


def test_diff_spans_caps_at_4_with_priority_entity_first():
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
    assert texts[:2] == ["Macron", "Bercy"]  # entities first
    assert "brutale" in texts  # ADJ kept
    assert "austérité" in texts  # NOUN kept
    assert "dénoncer" not in texts  # VERB bumped


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
