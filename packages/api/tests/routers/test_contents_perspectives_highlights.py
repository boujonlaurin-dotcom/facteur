"""Integration tests for `_attach_highlight_spans` (Story 7.4).

Covers the contract between the perspectives endpoint and the new
`TitleAnnotationService` without mocking the full Google News / digest
stack. The helper is called by both the stored and the live response paths,
so testing it directly proves the integration in both.
"""

from datetime import UTC, datetime
from unittest.mock import patch
from uuid import uuid4

import pytest
import pytest_asyncio

from app.models.cluster_title_annotation import ClusterTitleAnnotation
from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.routers.contents import _attach_highlight_spans
from app.services.llm_bias_annotation_service import LLM_VERSION as LLM_BIAS_VERSION
from app.services.title_annotation_service import TitleAnnotationService
from tests.fixtures.fake_spacy import (
    FakeDoc,
    FakeEnt,
    FakeNlp,
    FakeToken,
    service_with_nlp,
)

# --- Cluster fixture --------------------------------------------------------


@pytest_asyncio.fixture
async def cluster_setup(db_session):
    """Source + 1 ref + 2 cluster siblings sharing a cluster_id."""
    source = Source(
        id=uuid4(),
        name="Le Monde",
        url="https://lemonde.fr",
        feed_url=f"https://lemonde.fr/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()

    cluster_id = uuid4()
    ref = Content(
        id=uuid4(),
        source_id=source.id,
        title="Tsahal frappe Gaza",
        url="https://lemonde.fr/ref",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid="ref",
        cluster_id=cluster_id,
    )
    alt_a = Content(
        id=uuid4(),
        source_id=source.id,
        title="Armée israélienne bombarde Gaza",
        url="https://liberation.fr/alt-a",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid="alt-a",
        cluster_id=cluster_id,
    )
    alt_b = Content(
        id=uuid4(),
        source_id=source.id,
        title="Tsahal frappe Gaza",  # identical to ref → no spans expected
        url="https://figaro.fr/alt-b",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid="alt-b",
        cluster_id=cluster_id,
    )
    db_session.add_all([ref, alt_a, alt_b])
    await db_session.commit()
    return {"ref": ref, "alt_a": alt_a, "alt_b": alt_b, "cluster_id": cluster_id}


# --- Tests ------------------------------------------------------------------


@pytest.mark.asyncio
async def test_attach_highlight_spans_computes_for_content_without_cluster(db_session):
    """No cluster_id → highlight_spans are still computed via the off-cluster batch.

    Regression for the prod incident where clustering was never activated,
    so the early-return on `not content.cluster_id` silently disabled the
    feature for every article.
    """
    source = Source(
        id=uuid4(),
        name="Solo",
        url="https://solo.fr",
        feed_url=f"https://solo.fr/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()
    standalone = Content(
        id=uuid4(),
        source_id=source.id,
        title="Tsahal frappe Gaza",
        url="https://solo.fr/x",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid="x",
        cluster_id=None,
    )
    db_session.add(standalone)
    await db_session.commit()

    docs = {
        "Tsahal frappe Gaza": FakeDoc(
            tokens=[
                FakeToken("Tsahal", 0, "PROPN", "Tsahal"),
                FakeToken("frappe", 7, "VERB", "frapper"),
                FakeToken("Gaza", 14, "PROPN", "Gaza"),
            ],
        ),
        "Une frappe sur Gaza fait 20 morts": FakeDoc(
            tokens=[
                FakeToken("frappe", 4, "NOUN", "frappe"),
                FakeToken("Gaza", 14, "PROPN", "Gaza"),
                FakeToken("morts", 25, "NOUN", "mort"),
            ],
        ),
    }
    fake_svc = service_with_nlp(FakeNlp(docs))

    perspectives = [
        {
            "title": "Une frappe sur Gaza fait 20 morts",
            "url": "https://other.fr/x",
            "bias_stance": "left",
        }
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        pivot, _ = await _attach_highlight_spans(db_session, standalone, perspectives)

    texts = {s["text"] for s in perspectives[0]["highlight_spans"]}
    assert "morts" in texts  # diverges from ref (lemma not in {Tsahal, frapper, Gaza})
    assert all(s["bias"] == "left" for s in perspectives[0]["highlight_spans"])
    # Reference pivot still resolves to the ref title's first VERB.
    assert pivot == {"start": 7, "end": 13, "text": "frappe"}
    # Shared tokens (lemma match): "Gaza".
    assert [s["text"] for s in perspectives[0]["shared_tokens"]] == ["Gaza"]


@pytest.mark.asyncio
async def test_attach_highlight_spans_no_spans_when_titles_identical(
    db_session, cluster_setup
):
    """alt_b has the same title as ref → zero divergent tokens."""
    docs = {
        "Tsahal frappe Gaza": FakeDoc(
            tokens=[
                FakeToken("Tsahal", 0, "PROPN", "Tsahal"),
                FakeToken("frappe", 7, "VERB", "frapper"),
                FakeToken("Gaza", 14, "PROPN", "Gaza"),
            ],
            ents=[FakeEnt(0, 6, "ORG"), FakeEnt(14, 18, "LOC")],
        ),
        "Armée israélienne bombarde Gaza": FakeDoc(
            tokens=[
                FakeToken("Armée", 0, "NOUN", "armée"),
                FakeToken("israélienne", 6, "ADJ", "israélien"),
                FakeToken("bombarde", 18, "VERB", "bombarder"),
                FakeToken("Gaza", 27, "PROPN", "Gaza"),
            ],
            ents=[FakeEnt(27, 31, "LOC")],
        ),
    }
    fake_svc = service_with_nlp(FakeNlp(docs))

    perspectives = [
        {
            "title": "Tsahal frappe Gaza",
            "url": cluster_setup["alt_b"].url,
            "bias_stance": "right",
        }
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        await _attach_highlight_spans(db_session, cluster_setup["ref"], perspectives)

    assert perspectives[0]["highlight_spans"] == []


@pytest.mark.asyncio
async def test_attach_highlight_spans_uses_cache_for_in_cluster_perspectives(
    db_session, cluster_setup
):
    """Perspective.url matches a cluster Content → tokens read from cache, not recomputed."""
    docs = {
        "Tsahal frappe Gaza": FakeDoc(
            tokens=[
                FakeToken("Tsahal", 0, "PROPN", "Tsahal"),
                FakeToken("frappe", 7, "VERB", "frapper"),
                FakeToken("Gaza", 14, "PROPN", "Gaza"),
            ],
        ),
        "Armée israélienne bombarde Gaza": FakeDoc(
            tokens=[
                FakeToken("Armée", 0, "NOUN", "armée"),
                FakeToken("israélienne", 6, "ADJ", "israélien"),
                FakeToken("bombarde", 18, "VERB", "bombarder"),
                FakeToken("Gaza", 27, "PROPN", "Gaza"),
            ],
        ),
    }
    fake_svc = service_with_nlp(FakeNlp(docs))

    perspectives = [
        {
            "title": "Armée israélienne bombarde Gaza",
            "url": cluster_setup["alt_a"].url,
            "bias_stance": "left",
        }
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        await _attach_highlight_spans(db_session, cluster_setup["ref"], perspectives)

    spans = perspectives[0]["highlight_spans"]
    texts = {s["text"] for s in spans}
    # "Armée", "israélienne", "bombarde" diverge from ref. "Gaza" is shared.
    assert "Gaza" not in texts
    assert {"Armée", "israélienne", "bombarde"} <= texts
    assert all(s["bias"] == "left" for s in spans)


@pytest.mark.asyncio
async def test_attach_highlight_spans_computes_on_fly_for_google_news_url(
    db_session, cluster_setup
):
    """Google News perspective URL absent from the cluster → spaCy invoked at call time."""
    docs = {
        "Tsahal frappe Gaza": FakeDoc(
            tokens=[
                FakeToken("Tsahal", 0, "PROPN", "Tsahal"),
                FakeToken("frappe", 7, "VERB", "frapper"),
                FakeToken("Gaza", 14, "PROPN", "Gaza"),
            ],
        ),
        "Armée israélienne bombarde Gaza": FakeDoc(
            tokens=[
                FakeToken("Armée", 0, "NOUN", "armée"),
                FakeToken("israélienne", 6, "ADJ", "israélien"),
                FakeToken("bombarde", 18, "VERB", "bombarder"),
                FakeToken("Gaza", 27, "PROPN", "Gaza"),
            ],
        ),
        "Une frappe sur Gaza fait 20 morts": FakeDoc(
            tokens=[
                FakeToken("frappe", 4, "NOUN", "frappe"),
                FakeToken("Gaza", 14, "PROPN", "Gaza"),
                FakeToken("morts", 25, "NOUN", "mort"),
            ],
        ),
    }
    fake_svc = service_with_nlp(FakeNlp(docs))

    perspectives = [
        {
            "title": "Une frappe sur Gaza fait 20 morts",
            "url": "https://google-news-only-source.com/x",  # not in cluster
            "bias_stance": "unknown",
        }
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        await _attach_highlight_spans(db_session, cluster_setup["ref"], perspectives)

    spans = perspectives[0]["highlight_spans"]
    texts = {s["text"] for s in spans}
    assert "morts" in texts  # diverges from ref
    assert all(s["bias"] == "unknown" for s in spans)


@pytest.mark.asyncio
async def test_attach_highlight_spans_batches_off_cluster_titles_in_one_executor_hop(
    db_session, cluster_setup
):
    """Multiple Google News perspectives must hit spaCy via a single batched call.

    Guards against the regression of looping `compute_strong_tokens()` per
    perspective on the event loop (8 hops instead of 1).
    """
    docs = {
        "Tsahal frappe Gaza": FakeDoc(
            tokens=[FakeToken("Tsahal", 0, "PROPN", "Tsahal")]
        ),
        "GN title 1": FakeDoc(tokens=[FakeToken("GN1", 0, "PROPN", "gn1")]),
        "GN title 2": FakeDoc(tokens=[FakeToken("GN2", 0, "PROPN", "gn2")]),
        "GN title 3": FakeDoc(tokens=[FakeToken("GN3", 0, "PROPN", "gn3")]),
    }
    nlp = FakeNlp(docs)
    pipe_calls: list[list[str]] = []
    original_pipe = nlp.pipe

    def tracking_pipe(titles):
        titles_list = list(titles)
        pipe_calls.append(titles_list)
        return original_pipe(titles_list)

    nlp.pipe = tracking_pipe
    fake_svc = service_with_nlp(nlp)

    perspectives = [
        {"title": f"GN title {i}", "url": f"https://gn-{i}.com",
         "bias_stance": "center"}
        for i in (1, 2, 3)
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        await _attach_highlight_spans(db_session, cluster_setup["ref"], perspectives)

    # 2 batched pipe() calls: 1 for the cluster cache miss, 1 for the
    # off-cluster Google News titles — never N separate `nlp()` invocations.
    assert len(pipe_calls) == 2
    assert pipe_calls[1] == ["GN title 1", "GN title 2", "GN title 3"]


@pytest.mark.asyncio
async def test_attach_highlight_spans_returns_empty_when_nlp_unavailable(
    db_session, cluster_setup
):
    """`_nlp is None` → spans vides sans crash (cf. bug doc round 2)."""
    fake_svc = service_with_nlp(None)

    perspectives = [
        {
            "title": "Une frappe sur Gaza fait 20 morts",
            "url": "https://other.fr/x",
            "bias_stance": "left",
        }
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        pivot, _ = await _attach_highlight_spans(
            db_session, cluster_setup["ref"], perspectives
        )

    assert perspectives[0]["highlight_spans"] == []
    assert perspectives[0]["shared_tokens"] == []
    assert pivot is None


@pytest.mark.asyncio
async def test_attach_highlight_spans_swallows_exceptions(
    db_session, cluster_setup
):
    """If the service raises, every perspective gets `highlight_spans: []` — no 500."""
    perspectives = [
        {"title": "X", "url": "https://x.com", "bias_stance": "left"}
    ]

    class BrokenService:
        async def get_or_compute_cluster_annotations(self, *_a, **_kw):
            raise RuntimeError("boom")

    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=BrokenService(),
    ):
        pivot, _ = await _attach_highlight_spans(
            db_session, cluster_setup["ref"], perspectives
        )

    assert perspectives[0]["highlight_spans"] == []
    assert perspectives[0]["shared_tokens"] == []
    assert pivot is None


@pytest.mark.asyncio
async def test_attach_highlight_spans_returns_reference_pivot_and_shared_tokens(
    db_session, cluster_setup
):
    """Happy path: ref pivot bubbles up, alt perspective carries shared_tokens."""
    docs = {
        "Tsahal frappe Gaza": FakeDoc(
            tokens=[
                FakeToken("Tsahal", 0, "PROPN", "Tsahal"),
                FakeToken("frappe", 7, "VERB", "frapper"),
                FakeToken("Gaza", 14, "PROPN", "Gaza"),
            ],
        ),
        "Armée israélienne bombarde Gaza": FakeDoc(
            tokens=[
                FakeToken("Armée", 0, "NOUN", "armée"),
                FakeToken("israélienne", 6, "ADJ", "israélien"),
                FakeToken("bombarde", 18, "VERB", "bombarder"),
                FakeToken("Gaza", 27, "PROPN", "Gaza"),
            ],
        ),
    }
    fake_svc = service_with_nlp(FakeNlp(docs))

    perspectives = [
        {
            "title": "Armée israélienne bombarde Gaza",
            "url": cluster_setup["alt_a"].url,
            "bias_stance": "left",
        }
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        pivot, _ = await _attach_highlight_spans(
            db_session, cluster_setup["ref"], perspectives
        )

    assert pivot == {"start": 7, "end": 13, "text": "frappe"}
    shared = perspectives[0]["shared_tokens"]
    assert [s["text"] for s in shared] == ["Gaza"]
    assert shared[0]["start"] == 27
    assert "bias" not in shared[0]


@pytest.mark.asyncio
async def test_attach_highlight_spans_without_cluster_skips_db_scan(db_session):
    """No cluster_id → cluster cache lookup is skipped (no `WHERE cluster_id IS NULL` scan).

    Guards against the cheap-to-make regression of calling
    `get_or_compute_cluster_annotations(None)`, which would iterate every
    standalone Content row in the DB.
    """
    source = Source(
        id=uuid4(),
        name="Solo",
        url="https://solo2.fr",
        feed_url=f"https://solo2.fr/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()
    standalone = Content(
        id=uuid4(),
        source_id=source.id,
        title="Standalone",
        url="https://solo2.fr/x",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid="solo2-x",
        cluster_id=None,
    )
    db_session.add(standalone)
    await db_session.commit()

    fake_svc = service_with_nlp(FakeNlp({}))
    cluster_calls: list[object] = []

    async def tracking_cluster_lookup(_db, cluster_id):
        cluster_calls.append(cluster_id)
        from app.services.title_annotation_service import ClusterAnnotations

        return ClusterAnnotations()

    fake_svc.get_or_compute_cluster_annotations = tracking_cluster_lookup

    perspectives = [
        {"title": "Anything", "url": "https://other.fr/y", "bias_stance": "left"}
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        await _attach_highlight_spans(db_session, standalone, perspectives)

    assert cluster_calls == []  # no DB scan on cluster_id IS NULL
    assert perspectives[0]["highlight_spans"] == []
    assert perspectives[0]["shared_tokens"] == []


# --- PR 5 : LLM enriched contract -------------------------------------------

# Shared fixtures for the LLM/spaCy branch tests. The Tsahal/Gaza pair is the
# canonical example used across the calibration corpus.
_REF_TOKENS_GAZA: list[dict] = [
    {"start": 0, "end": 6, "text": "Tsahal", "lemma": "tsahal", "pos": "PROPN"},
    {"start": 7, "end": 13, "text": "frappe", "lemma": "frapper", "pos": "VERB"},
    {"start": 14, "end": 18, "text": "Gaza", "lemma": "gaza", "pos": "PROPN"},
]
_ALT_TOKENS_GAZA: list[dict] = [
    {"start": 0, "end": 5, "text": "Armée", "lemma": "armée", "pos": "NOUN"},
    {"start": 18, "end": 26, "text": "bombarde", "lemma": "bombarder", "pos": "VERB"},
    {"start": 27, "end": 31, "text": "Gaza", "lemma": "gaza", "pos": "PROPN"},
]


async def _seed_strong_tokens_cache(
    db_session, cluster_setup, ref_tokens, alt_tokens
):
    """Pré-peuple `cluster_title_annotations.strong_tokens` pour ref + alt_a.

    Imite la sortie du pipeline spaCy déterministe (PR cta01) avant que la
    couche LLM (PR 4) écrive `semantic_equiv`. Sans ces rows, l'appel
    `get_or_compute_cluster_annotations` tomberait dans la branche
    "compute_strong_tokens_batch" qui dépend du spaCy réel.
    """
    db_session.add_all(
        [
            ClusterTitleAnnotation(
                cluster_id=cluster_setup["cluster_id"],
                content_id=cluster_setup["ref"].id,
                strong_tokens=ref_tokens,
                model_version=TitleAnnotationService.MODEL_VERSION,
            ),
            ClusterTitleAnnotation(
                cluster_id=cluster_setup["cluster_id"],
                content_id=cluster_setup["alt_a"].id,
                strong_tokens=alt_tokens,
                model_version=TitleAnnotationService.MODEL_VERSION,
            ),
            ClusterTitleAnnotation(
                cluster_id=cluster_setup["cluster_id"],
                content_id=cluster_setup["alt_b"].id,
                strong_tokens=ref_tokens,
                model_version=TitleAnnotationService.MODEL_VERSION,
            ),
        ]
    )
    await db_session.commit()


def _cluster_signature(cluster_setup) -> str:
    """Recompute the deterministic signature for the cluster_setup fixture."""
    return TitleAnnotationService.compute_cluster_signature(
        [
            cluster_setup["ref"].id,
            cluster_setup["alt_a"].id,
            cluster_setup["alt_b"].id,
        ]
    )


def _llm_payload(target_spans: list[dict], signature: str) -> dict:
    """Mirror what `write_llm_annotations` persists for one variant."""
    return {
        "target_spans": target_spans,
        "exclude_spans": [],
        "notes": "test",
        "confidence": 0.9,
        "llm_version": LLM_BIAS_VERSION,
        "annotated_at": "2026-05-23T12:00:00+00:00",
        "cluster_signature": signature,
    }


@pytest.mark.asyncio
async def test_attach_highlight_spans_uses_llm_when_semantic_equiv_present(
    db_session, cluster_setup
):
    """semantic_equiv populated → LLM target_spans surfaced verbatim
    (weight/category/justification) with bias injected from the perspective."""
    await _seed_strong_tokens_cache(
        db_session, cluster_setup, _REF_TOKENS_GAZA, _ALT_TOKENS_GAZA
    )

    signature = _cluster_signature(cluster_setup)
    llm_target_spans = [
        {
            "start": 18,
            "end": 26,
            "text": "bombarde",
            "category": "editorial_angle",
            "weight": 1.0,
            "justification": "Verbe chargé qui dramatise l'action.",
        }
    ]
    alt_row = await db_session.get(
        ClusterTitleAnnotation,
        (cluster_setup["cluster_id"], cluster_setup["alt_a"].id),
    )
    alt_row.semantic_equiv = _llm_payload(llm_target_spans, signature)
    await db_session.commit()

    fake_svc = service_with_nlp(FakeNlp({}))
    perspectives = [
        {
            "title": "Armée israélienne bombarde Gaza",
            "url": cluster_setup["alt_a"].url,
            "bias_stance": "left",
        }
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        pivot, source = await _attach_highlight_spans(
            db_session, cluster_setup["ref"], perspectives
        )

    assert source == "llm"
    spans = perspectives[0]["highlight_spans"]
    assert len(spans) == 1
    span = spans[0]
    assert span["text"] == "bombarde"
    assert span["category"] == "editorial_angle"
    assert span["weight"] == 1.0
    assert span["justification"] == "Verbe chargé qui dramatise l'action."
    assert span["bias"] == "left"  # injected from p["bias_stance"] for compat
    # Reference pivot still resolves via spaCy ref_tokens.
    assert pivot == {"start": 7, "end": 13, "text": "frappe"}


@pytest.mark.asyncio
async def test_attach_highlight_spans_falls_back_to_spacy_when_no_semantic_equiv(
    db_session, cluster_setup
):
    """Cluster row exists but semantic_equiv IS NULL → spaCy fallback,
    spans keep the legacy {start, end, text, bias} shape."""
    await _seed_strong_tokens_cache(
        db_session, cluster_setup, _REF_TOKENS_GAZA, _ALT_TOKENS_GAZA
    )

    fake_svc = service_with_nlp(FakeNlp({}))
    perspectives = [
        {
            "title": "Armée israélienne bombarde Gaza",
            "url": cluster_setup["alt_a"].url,
            "bias_stance": "left",
        }
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        _, source = await _attach_highlight_spans(
            db_session, cluster_setup["ref"], perspectives
        )

    assert source == "spacy"
    spans = perspectives[0]["highlight_spans"]
    assert spans, "spaCy fallback must still produce spans"
    for span in spans:
        # Legacy contract: no LLM fields leak in.
        assert set(span.keys()) == {"start", "end", "text", "bias"}
        assert span["bias"] == "left"


@pytest.mark.asyncio
async def test_attach_highlight_spans_invalidates_llm_on_cluster_signature_mismatch(
    db_session, cluster_setup
):
    """semantic_equiv exists but cluster_signature is stale → cache ignored,
    fallback to spaCy. End-to-end check of the versioning gate from PR 3."""
    await _seed_strong_tokens_cache(
        db_session, cluster_setup, _REF_TOKENS_GAZA, _ALT_TOKENS_GAZA
    )

    stale_payload = _llm_payload(
        [
            {
                "start": 18,
                "end": 26,
                "text": "bombarde",
                "category": "editorial_angle",
                "weight": 1.0,
                "justification": "stale",
            }
        ],
        signature="deadbeefdeadbeef",  # not the real signature
    )
    alt_row = await db_session.get(
        ClusterTitleAnnotation,
        (cluster_setup["cluster_id"], cluster_setup["alt_a"].id),
    )
    alt_row.semantic_equiv = stale_payload
    await db_session.commit()

    fake_svc = service_with_nlp(FakeNlp({}))
    perspectives = [
        {
            "title": "Armée israélienne bombarde Gaza",
            "url": cluster_setup["alt_a"].url,
            "bias_stance": "left",
        }
    ]
    with patch(
        "app.routers.contents.get_title_annotation_service",
        return_value=fake_svc,
    ):
        _, source = await _attach_highlight_spans(
            db_session, cluster_setup["ref"], perspectives
        )

    assert source == "spacy"
    for span in perspectives[0]["highlight_spans"]:
        assert "weight" not in span  # no LLM fields leaked through


@pytest.mark.asyncio
async def test_build_cluster_perspectives_propagates_content_language(db_session):
    """`Perspective.language` mirrors `Content.language` so the endpoint
    list-comp can expose it without an extra DB lookup."""
    from app.services.perspective_service import PerspectiveService

    source = Source(
        id=uuid4(),
        name="Reuters",  # not in is_french_source whitelist → simulate EN feed
        url="https://reuters.com",
        feed_url=f"https://reuters.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()
    content_en = Content(
        id=uuid4(),
        source_id=source.id,
        title="Israel strikes Gaza after attacks",
        url="https://reuters.com/article-en",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid="en",
        language="en",
    )
    content_fr = Content(
        id=uuid4(),
        source_id=source.id,
        title="Tsahal frappe Gaza",
        url="https://reuters.com/article-fr",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid="fr",
        language="fr",
    )
    db_session.add_all([content_en, content_fr])
    await db_session.commit()
    # Reload so `content.source` relationship is populated.
    await db_session.refresh(content_en, attribute_names=["source"])
    await db_session.refresh(content_fr, attribute_names=["source"])

    perspectives = await PerspectiveService(db_session).build_cluster_perspectives(
        [content_en, content_fr]
    )
    # Single perspective per source_id — keep the one that landed first.
    assert len(perspectives) == 1
    assert perspectives[0].language == "en"
