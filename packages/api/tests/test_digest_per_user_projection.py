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

from app.services.digest_selector import DigestContext, DigestSelector
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


def _make_subject(
    topic_id,
    content,
    *,
    rank=1,
    is_a_la_une=False,
    source_count=0,
    divergence_level=None,
):
    return EditorialSubject(
        rank=rank,
        topic_id=topic_id,
        label=f"Sujet {topic_id}",
        selection_reason="trending",
        deep_angle=None,
        is_a_la_une=is_a_la_une,
        source_count=source_count,
        divergence_level=divergence_level,
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
        return EditorialPipelineResult(subjects=subjects, metadata={"matching_ms": 0})


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


def _make_context(user_id, followed_source_ids, interests=None, custom_topics=None):
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
        user_custom_topics=custom_topics or [],
    )


def _make_topic_profile(
    topic_name,
    *,
    slug_parent="",
    keywords=None,
    entity_type=None,
    canonical_name=None,
    priority_multiplier=1.0,
):
    """Stub `UserTopicProfile`.

    `types.SimpleNamespace` et pas `MagicMock` : `_score_custom_topics` fait
    `getattr(tp, "is_veille", False)`, et un MagicMock renverrait un Mock
    truthy qui routerait vers le barème veille.
    """
    from app.models.enums import InterestState

    return types.SimpleNamespace(
        topic_name=topic_name,
        slug_parent=slug_parent,
        keywords=keywords or [],
        entity_type=entity_type,
        canonical_name=canonical_name,
        priority_multiplier=priority_multiplier,
        state=InterestState.FOLLOWED,
        is_veille=False,
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
async def test_rehydrated_clusters_do_not_depend_on_source_domains():
    """Invariant B-2 : `cluster_data` ne sérialise PAS `source_domains`.

    Le fold couverture (importance_detector) agit sur `source_ids` en phase
    globale ; les clusters réhydratés per-user en héritent via `source_ids` et
    ont `source_domains == set()`. Ce test verrouille l'invariant pour que la
    projection per-user (et une future PR de tri) ne s'appuie jamais sur
    `source_domains` d'un cluster réhydraté — sinon tout compte multi-sources
    per-user retomberait à 0. Cf. bug-curation-essentiel-personnalisation §2.
    """
    src_a = uuid4()
    src_b = uuid4()
    c1 = _make_content(src_a, title="A")
    c2 = _make_content(src_b, title="B")
    selector = _make_selector(session_maker=_FakeSessionMaker([c1, c2]))

    global_ctx = types.SimpleNamespace(
        cluster_data=[
            {
                "cluster_id": "cl-1",
                "label": "Cluster 1",
                "content_ids": [str(c1.id), str(c2.id)],
                "source_ids": [str(src_a), str(src_b)],
                "theme": "tech",
            }
        ],
        subjects=[],
    )

    clusters = await selector._rehydrate_editorial_clusters(global_ctx)
    assert len(clusters) == 1
    # source_ids (déjà foldé en global) porte le décompte multi-sources.
    assert clusters[0].source_ids == {src_a, src_b}
    assert len(clusters[0].source_ids) >= 2
    # source_domains reste vide : aucune dépendance per-user dessus. Piège
    # verrouillé : la propriété `is_multi_source` lit `source_domains`, donc
    # elle vaut False sur un cluster réhydraté — le per-user DOIT compter via
    # `source_ids`, jamais via `is_multi_source`/`source_domains`.
    assert clusters[0].source_domains == set()
    assert clusters[0].is_multi_source is False


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
    assert [s.rank for s in res_a.subjects] == list(range(1, len(res_a.subjects) + 1))


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
    a3 = _make_content(srcA, published_at=now - timedelta(hours=1), title="Solo A")
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
    solo_ids = [
        s.topic_id for s in res_follower.subjects if s.topic_id.startswith("solo-")
    ]
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


# ─── Tests: classement par importance éditoriale (bug-actus-du-jour-ranking) ──


@pytest.mark.asyncio
async def test_multi_source_ranks_above_personalized_single_source():
    """Partie C : un sujet multi-sources passe devant un sujet mono-source
    même quand ce dernier est porté par une source SUIVIE (perso fort). La
    couverture éditoriale prime, la perso ne fait que départager."""
    srcMulti, srcFollowed = uuid4(), uuid4()
    now = datetime.now(UTC)
    a_multi = _make_content(srcMulti, published_at=now, title="Sujet très couvert")
    a_solo = _make_content(
        srcFollowed, published_at=now, title="Sujet d'une source suivie"
    )

    c_multi = _make_topic_cluster("multi", [a_multi])
    c_solo = _make_topic_cluster("solo", [a_solo])
    clusters = [c_multi, c_solo]

    subjects = [
        _make_subject("multi", a_multi, rank=1, source_count=5),
        _make_subject("solo", a_solo, rank=2, source_count=1),
    ]
    global_ctx = types.SimpleNamespace(subjects=subjects, cluster_data=[])

    selector = _make_selector()
    pipeline = _StubPipeline()

    # L'utilisateur SUIT la source du sujet mono-source → perso boost dessus.
    ctx = _make_context(uuid4(), {srcFollowed})
    res = await selector._project_editorial_for_user(
        pipeline=pipeline,
        global_ctx=global_ctx,
        clusters=clusters,
        context=ctx,
        mode="pour_vous",
    )
    order = [s.topic_id for s in res.subjects]
    # Le multi-sources est en tête malgré la perso favorable au mono-source.
    assert order[0] == "multi"
    assert order.index("multi") < order.index("solo")


@pytest.mark.asyncio
async def test_solo_subject_never_above_multi_source(monkeypatch):
    """Partie C : un sujet solo (source suivie, créé per-user) est relégué sous
    tout sujet multi-sources, même si son score perso est élevé."""
    monkeypatch.setenv("EDITORIAL_SOLO_SUBJECT_MIN_SCORE", "0")

    srcMulti, srcFollowed = uuid4(), uuid4()
    now = datetime.now(UTC)
    a_multi = _make_content(srcMulti, published_at=now, title="Multi")
    # Source suivie, non représentée → deviendra un sujet solo per-user.
    a_leftover = _make_content(srcFollowed, published_at=now, title="Leftover suivi")

    c_multi = _make_topic_cluster("multi", [a_multi])
    c_followed = _make_topic_cluster("followed", [a_leftover])
    clusters = [c_multi, c_followed]

    # Seul le sujet multi est dans le contexte global ; a_leftover devient solo.
    subjects = [_make_subject("multi", a_multi, rank=1, source_count=4)]
    global_ctx = types.SimpleNamespace(subjects=subjects, cluster_data=[])

    selector = _make_selector()
    pipeline = _StubPipeline()

    ctx = _make_context(uuid4(), {srcFollowed})
    res = await selector._project_editorial_for_user(
        pipeline=pipeline,
        global_ctx=global_ctx,
        clusters=clusters,
        context=ctx,
        mode="pour_vous",
    )
    order = [s.topic_id for s in res.subjects]
    solo_ids = [t for t in order if t.startswith("solo-")]
    assert solo_ids, "le sujet solo doit exister"
    # Aucun solo ne précède le sujet multi-sources.
    assert order[0] == "multi"
    assert order.index("multi") < order.index(solo_ids[0])


@pytest.mark.asyncio
async def test_a_la_une_stays_rank_1_despite_higher_importance_elsewhere():
    """Partie C : « À la Une » reste rang 1 même si un autre sujet a une
    importance éditoriale supérieure (couverture/récence)."""
    srcUne, srcBig = uuid4(), uuid4()
    now = datetime.now(UTC)
    a_une = _make_content(srcUne, published_at=now, title="À la Une")
    a_big = _make_content(srcBig, published_at=now, title="Énorme couverture")

    c_une = _make_topic_cluster("une", [a_une])
    c_big = _make_topic_cluster("big", [a_big])
    clusters = [c_une, c_big]

    subjects = [
        _make_subject("une", a_une, rank=1, is_a_la_une=True, source_count=2),
        _make_subject("big", a_big, rank=2, source_count=10),
    ]
    global_ctx = types.SimpleNamespace(subjects=subjects, cluster_data=[])

    selector = _make_selector()
    pipeline = _StubPipeline()

    ctx = _make_context(uuid4(), set())
    res = await selector._project_editorial_for_user(
        pipeline=pipeline,
        global_ctx=global_ctx,
        clusters=clusters,
        context=ctx,
        mode="pour_vous",
    )
    assert res.subjects[0].topic_id == "une"
    assert res.subjects[0].is_a_la_une is True


@pytest.mark.asyncio
async def test_polarization_breaks_tie_between_multi_sources():
    """Partie C : à couverture et récence égales, le sujet le plus polarisé
    (divergence_level high) passe devant."""
    srcA, srcB = uuid4(), uuid4()
    now = datetime.now(UTC)
    a_plain = _make_content(srcA, published_at=now, title="Consensus")
    a_polar = _make_content(srcB, published_at=now, title="Polarisé")

    clusters = [
        _make_topic_cluster("plain", [a_plain]),
        _make_topic_cluster("polar", [a_polar]),
    ]
    subjects = [
        _make_subject("plain", a_plain, rank=1, source_count=4, divergence_level="low"),
        _make_subject(
            "polar", a_polar, rank=2, source_count=4, divergence_level="high"
        ),
    ]
    global_ctx = types.SimpleNamespace(subjects=subjects, cluster_data=[])

    selector = _make_selector()
    pipeline = _StubPipeline()

    ctx = _make_context(uuid4(), set())
    res = await selector._project_editorial_for_user(
        pipeline=pipeline,
        global_ctx=global_ctx,
        clusters=clusters,
        context=ctx,
        mode="pour_vous",
    )
    order = [s.topic_id for s in res.subjects]
    assert order.index("polar") < order.index("plain")


# ─── Tests: persistance des scores (jauge CTR) ────────────────────────────────


@pytest.mark.asyncio
async def test_representative_carries_its_score_and_pillar_scores():
    """Le score du représentant survit à la boucle de renumérotation.

    C'est la donnée que `scripts/evaluate_feed_ranking.py` croise avec la
    consommation. Avant cette PR le `pillar_scores` était calculé puis jeté
    (`score_map` ne gardait que le score final), et le rattacher AVANT la
    renumérotation ne servait à rien : cette boucle recopie chaque sujet.
    """
    srcA, srcB = uuid4(), uuid4()
    now = datetime.now(UTC)
    a1 = _make_content(srcA, published_at=now, title="Article A")
    a2 = _make_content(srcB, published_at=now, title="Article B")

    clusters = [_make_topic_cluster("c1", [a1]), _make_topic_cluster("c2", [a2])]
    subjects = [_make_subject("c1", a1, rank=1), _make_subject("c2", a2, rank=2)]
    global_ctx = types.SimpleNamespace(subjects=subjects, cluster_data=[])

    selector = _make_selector()
    res = await selector._project_editorial_for_user(
        pipeline=_StubPipeline(),
        global_ctx=global_ctx,
        clusters=clusters,
        context=_make_context(uuid4(), {srcA}),
        mode="pour_vous",
    )

    for subject in res.subjects:
        assert subject.actu_article is not None
        assert subject.actu_article.score is not None
        assert set(subject.actu_article.pillar_scores) == {
            "pertinence",
            "source",
            "fraicheur",
            "qualite",
        }

    # La source suivie doit scorer au-dessus de la non-suivie : le score
    # persisté est bien celui qui a servi au tri, pas une valeur décorative.
    by_topic = {s.topic_id: s for s in res.subjects}
    assert by_topic["c1"].actu_article.score > by_topic["c2"].actu_article.score


@pytest.mark.asyncio
async def test_score_stays_none_when_scoring_fails():
    """Dégradation sûre : un scoring en échec ne doit pas casser le digest."""
    src = uuid4()
    a1 = _make_content(src, published_at=datetime.now(UTC), title="Article A")
    clusters = [_make_topic_cluster("c1", [a1])]
    global_ctx = types.SimpleNamespace(
        subjects=[_make_subject("c1", a1, rank=1)], cluster_data=[]
    )

    selector = _make_selector()
    selector._score_candidates = AsyncMock(side_effect=RuntimeError("boom"))

    res = await selector._project_editorial_for_user(
        pipeline=_StubPipeline(),
        global_ctx=global_ctx,
        clusters=clusters,
        context=_make_context(uuid4(), {src}),
        mode="pour_vous",
    )

    assert len(res.subjects) == 1
    assert res.subjects[0].actu_article.score is None
    assert res.subjects[0].actu_article.pillar_scores is None


def test_legacy_snapshots_without_score_still_parse():
    """Les digests déjà persistés n'ont ni `score` ni `pillar_scores`."""
    article = MatchedActuArticle(
        content_id=uuid4(),
        title="Legacy",
        source_name="Source",
        source_id=uuid4(),
        is_user_source=False,
        published_at=datetime.now(UTC),
    )
    assert article.score is None
    assert article.pillar_scores is None


# ─── Tests: threading user_custom_topics (PR1b) ───────────────────────────────


def _scorable(source_id, *, title, description=""):
    """Content scorable par le pilier Pertinence (titre/description réels)."""
    c = _make_content(source_id, title=title)
    c.description = description
    c.entities = None
    c.cluster_id = None
    c.duration_seconds = None
    return c


@pytest.mark.asyncio
async def test_custom_topics_reach_the_scoring_context():
    """`_score_candidates` construisait le ScoringContext sans les Sujets.

    La garde `if not context.user_custom_topics: return 0.0, []` avalait donc
    tout : `_score_custom_topics` n'a jamais tiré sur le digest.
    """
    src = uuid4()
    profile = _make_topic_profile("Intelligence artificielle", keywords=["openai"])
    selector = _make_selector()
    context = _make_context(uuid4(), [src], custom_topics=[profile])

    captured = {}
    real_engine = selector.rec_service.pillar_engine
    selector.rec_service.pillar_engine = Mock()
    selector.rec_service.pillar_engine.compute_score = lambda content, ctx: (
        captured.setdefault("topics", ctx.user_custom_topics),
        real_engine.compute_score(content, ctx),
    )[1]

    await selector._score_candidates(
        [_scorable(src, title="OpenAI annonce un nouveau modèle")], context
    )

    assert captured["topics"] == [profile]


@pytest.mark.asyncio
async def test_custom_topic_keyword_match_outranks_neutral_article():
    """Le blast radius assumé de PR1b : la branche slug/keyword à +25 s'active."""
    src = uuid4()
    selector = _make_selector()
    profile = _make_topic_profile("Intelligence artificielle", keywords=["openai"])

    matching = _scorable(src, title="OpenAI annonce un nouveau modèle")
    neutral = _scorable(src, title="Un tout autre sujet")

    scored = await selector._score_candidates(
        [matching, neutral],
        _make_context(uuid4(), [src], custom_topics=[profile]),
    )
    by_id = {c.id: score for c, score, _bd, _ps in scored}

    assert by_id[matching.id] > by_id[neutral.id]

    breakdown = next(bd for c, _s, bd, _ps in scored if c.id == matching.id)
    assert any(b.label == "Votre sujet : Intelligence artificielle" for b in breakdown)


@pytest.mark.asyncio
async def test_no_custom_topics_leaves_scoring_unchanged():
    """Sans Sujet suivi, aucun bonus ni malus custom-topic n'apparaît."""
    src = uuid4()
    selector = _make_selector()

    scored = await selector._score_candidates(
        [_scorable(src, title="OpenAI annonce un nouveau modèle")],
        _make_context(uuid4(), [src]),
    )

    breakdown = scored[0][2]
    assert not any("Votre sujet" in b.label for b in breakdown)


@pytest.mark.asyncio
async def test_entity_subscription_outranks_neutral_article_in_digest():
    """PR1b2 bout-en-bout : abonnement entité -> l'article monte dans le digest."""
    import json

    src = uuid4()
    selector = _make_selector()
    profile = _make_topic_profile(
        "Angela Merkel", entity_type="PERSON", canonical_name="Angela Merkel"
    )

    matching = _scorable(src, title="Une décision européenne")
    matching.entities = [json.dumps({"name": "Angela Merkel", "type": "PERSON"})]
    neutral = _scorable(src, title="Un tout autre sujet")

    scored = await selector._score_candidates(
        [matching, neutral],
        _make_context(uuid4(), [src], custom_topics=[profile]),
    )
    by_id = {c.id: score for c, score, _bd, _ps in scored}

    assert by_id[matching.id] > by_id[neutral.id]

    breakdown = next(bd for c, _s, bd, _ps in scored if c.id == matching.id)
    assert any(b.label == "Votre sujet : Angela Merkel" for b in breakdown)
