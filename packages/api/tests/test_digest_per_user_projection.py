"""Tests P2 — projection editorial per-user (DigestSelector).

Couvre :
- _rehydrate_editorial_clusters : cluster_data (IDs) -> TopicCluster consommable.
- _project_editorial_for_user : deux users aux sources différentes -> ordres de
  sujets différents depuis le MÊME EditorialGlobalContext (divergence), et sujet
  solo créé pour le suiveur uniquement (contexte global reste partagé).
"""

import types
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, Mock, patch
from uuid import uuid4

import pytest

from app.services.digest_selector import DigestSelector, DigestContext
from app.services.editorial.schemas import (
    EditorialPipelineResult,
    EditorialSubject,
    MatchedActuArticle,
)


# ─── Factories ────────────────────────────────────────────────────────────────


def _make_content(source_id, *, theme="tech", published_at=None, title="Article"):
    c = MagicMock()
    c.id = uuid4()
    c.source_id = source_id
    c.is_paid = False
    c.content_type = None  # texte
    c.theme = theme
    c.topics = None
    c.published_at = published_at or datetime.now(UTC)
    c.title = title
    c.thumbnail_url = None
    c.source = MagicMock()
    c.source.name = f"Source {source_id}"
    c.source.theme = theme
    c.source.is_curated = False
    c.source.reliability_score = None
    c.source.secondary_themes = []
    return c


def _make_topic_cluster(cluster_id, contents):
    from app.services.briefing.importance_detector import TopicCluster

    return TopicCluster(
        cluster_id=cluster_id,
        label="Cluster",
        tokens=set(),
        contents=contents,
        source_ids={c.source_id for c in contents},
        theme="tech",
    )


def _make_subject(topic_id, content, *, rank=1, is_a_la_une=False):
    return EditorialSubject(
        rank=rank,
        topic_id=topic_id,
        label=f"Sujet {topic_id}",
        selection_reason="trending",
        deep_angle=None,
        is_a_la_une=is_a_la_une,
        actu_article=MatchedActuArticle(
            content_id=content.id,
            title=content.title,
            source_name=content.source.name,
            source_id=content.source_id,
            is_user_source=False,
            published_at=content.published_at,
        ),
    )


class _StubPipeline:
    """Pipeline minimal : run_for_user délègue au vrai ActuMatcher."""

    def run_for_user(
        self, *, global_ctx, clusters, user_source_ids, excluded_content_ids
    ):
        from app.services.editorial.actu_matcher import ActuMatcher

        subjects = ActuMatcher(actu_max_age_hours=24).match_for_user(
            subjects=global_ctx.subjects,
            clusters=clusters,
            user_source_ids=user_source_ids,
            excluded_content_ids=excluded_content_ids,
        )
        return EditorialPipelineResult(
            subjects=subjects, metadata={"matching_ms": 0}
        )


class _FakeSessionMaker:
    """async_sessionmaker stub renvoyant une session dont execute -> contents."""

    def __init__(self, contents):
        self._contents = contents

    def __call__(self):
        return self

    async def __aenter__(self):
        sess = AsyncMock()
        scalars = MagicMock()
        scalars.all = MagicMock(return_value=self._contents)
        res = MagicMock()
        res.scalars = MagicMock(return_value=scalars)
        sess.execute = AsyncMock(return_value=res)
        return sess

    async def __aexit__(self, *args):
        return False


def _make_selector(session_maker=None):
    from app.services.recommendation.scoring_engine import PillarScoringEngine

    with patch("app.services.digest_selector.RecommendationService"):
        sel = DigestSelector(AsyncMock(), session_maker=session_maker)
    sel.rec_service = Mock()
    sel.rec_service.fetch_impression_data = AsyncMock(return_value={})
    sel.rec_service.pillar_engine = PillarScoringEngine()
    return sel


def _make_context(user_id, followed_source_ids, interests=None):
    return DigestContext(
        user_id=user_id,
        user_profile=Mock(),
        user_interests=interests or set(),
        user_interest_weights={},
        followed_source_ids=set(followed_source_ids),
        custom_source_ids=set(),
        user_prefs={},
        user_subtopics=set(),
        user_subtopic_weights={},
        muted_sources=set(),
        muted_themes=set(),
        muted_topics=set(),
        muted_content_types=set(),
    )


# ─── Tests: rehydration ───────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_rehydrate_clusters_from_cluster_data():
    """cluster_data (IDs sérialisés) -> TopicCluster avec Content chargés."""
    src = uuid4()
    c1 = _make_content(src, title="A")
    c2 = _make_content(src, title="B")
    selector = _make_selector(session_maker=_FakeSessionMaker([c1, c2]))

    global_ctx = types.SimpleNamespace(
        cluster_data=[
            {
                "cluster_id": "cl-1",
                "label": "Cluster 1",
                "content_ids": [str(c1.id), str(c2.id)],
                "source_ids": [str(src)],
                "theme": "tech",
            }
        ],
        subjects=[],
    )

    clusters = await selector._rehydrate_editorial_clusters(global_ctx)
    assert len(clusters) == 1
    assert clusters[0].cluster_id == "cl-1"
    assert {c.id for c in clusters[0].contents} == {c1.id, c2.id}
    assert clusters[0].source_ids == {src}


@pytest.mark.asyncio
async def test_rehydrate_clusters_empty_when_no_data():
    selector = _make_selector(session_maker=_FakeSessionMaker([]))
    global_ctx = types.SimpleNamespace(cluster_data=[], subjects=[])
    assert await selector._rehydrate_editorial_clusters(global_ctx) == []


# ─── Tests: per-user projection divergence ────────────────────────────────────


@pytest.mark.asyncio
async def test_two_users_diverge_on_followed_source_order():
    """Même contexte global, sources suivies différentes -> ordres différents."""
    srcA, srcB = uuid4(), uuid4()
    now = datetime.now(UTC)
    a1 = _make_content(srcA, published_at=now, title="Article A")
    a2 = _make_content(srcB, published_at=now, title="Article B")

    c1 = _make_topic_cluster("c1", [a1])
    c2 = _make_topic_cluster("c2", [a2])
    clusters = [c1, c2]

    subjects = [
        _make_subject("c1", a1, rank=1),
        _make_subject("c2", a2, rank=2),
    ]
    global_ctx = types.SimpleNamespace(subjects=subjects, cluster_data=[])

    selector = _make_selector()
    pipeline = _StubPipeline()

    # User A suit srcA.
    ctx_a = _make_context(uuid4(), {srcA})
    res_a = await selector._project_editorial_for_user(
        pipeline=pipeline,
        global_ctx=global_ctx,
        clusters=clusters,
        context=ctx_a,
        mode="pour_vous",
    )
    order_a = [s.topic_id for s in res_a.subjects]

    # User B suit srcB.
    ctx_b = _make_context(uuid4(), {srcB})
    res_b = await selector._project_editorial_for_user(
        pipeline=pipeline,
        global_ctx=global_ctx,
        clusters=clusters,
        context=ctx_b,
        mode="pour_vous",
    )
    order_b = [s.topic_id for s in res_b.subjects]

    # Le sujet adossé à la source suivie remonte en tête pour chaque user.
    assert order_a[0] == "c1"
    assert order_b[0] == "c2"
    assert order_a != order_b
    # Le représentant de la source suivie est marqué is_user_source.
    top_a = res_a.subjects[0]
    assert top_a.actu_article.is_user_source is True
    # Les rangs sont renumérotés 1..n.
    assert [s.rank for s in res_a.subjects] == list(
        range(1, len(res_a.subjects) + 1)
    )


@pytest.mark.asyncio
async def test_solo_subject_created_for_follower_only(monkeypatch):
    """Un article de source suivie non représenté devient un sujet solo — pour
    le suiveur seulement (le contexte global reste partagé)."""
    # Seuil à 0 : tout article de source suivie récent franchit le gate.
    monkeypatch.setenv("EDITORIAL_SOLO_SUBJECT_MIN_SCORE", "0")

    srcA, srcB = uuid4(), uuid4()
    now = datetime.now(UTC)
    # c1 contient a1 (représentant, plus récent) + a3 (même source srcA, leftover).
    a1 = _make_content(srcA, published_at=now, title="Rep A")
    a3 = _make_content(
        srcA, published_at=now - timedelta(hours=1), title="Solo A"
    )
    a2 = _make_content(srcB, published_at=now, title="Rep B")

    c1 = _make_topic_cluster("c1", [a1, a3])
    c2 = _make_topic_cluster("c2", [a2])
    clusters = [c1, c2]
    subjects = [
        _make_subject("c1", a1, rank=1),
        _make_subject("c2", a2, rank=2),
    ]
    global_ctx = types.SimpleNamespace(subjects=subjects, cluster_data=[])

    selector = _make_selector()
    pipeline = _StubPipeline()

    # Suiveur de srcA : a3 (leftover, source suivie, récent) -> sujet solo.
    ctx_follower = _make_context(uuid4(), {srcA})
    res_follower = await selector._project_editorial_for_user(
        pipeline=pipeline,
        global_ctx=global_ctx,
        clusters=clusters,
        context=ctx_follower,
        mode="pour_vous",
    )
    solo_ids = [s.topic_id for s in res_follower.subjects if s.topic_id.startswith("solo-")]
    assert solo_ids, "le suiveur doit obtenir un sujet solo"
    solo = next(s for s in res_follower.subjects if s.topic_id.startswith("solo-"))
    assert solo.actu_article.content_id == a3.id
    assert solo.actu_article.is_user_source is True

    # Non-suiveur de srcA (suit srcB) : pas de sujet solo issu de a3.
    ctx_other = _make_context(uuid4(), {srcB})
    res_other = await selector._project_editorial_for_user(
        pipeline=pipeline,
        global_ctx=global_ctx,
        clusters=clusters,
        context=ctx_other,
        mode="pour_vous",
    )
    other_solo = [s for s in res_other.subjects if s.topic_id.startswith("solo-")]
    assert other_solo == [], "pas de fuite cross-user : aucun solo pour le non-suiveur"
