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

from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.routers.contents import _attach_highlight_spans
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
        pivot = await _attach_highlight_spans(db_session, standalone, perspectives)

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
        pivot = await _attach_highlight_spans(
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
        pivot = await _attach_highlight_spans(
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
