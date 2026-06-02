"""Tests pour la curation des sections thématiques de la Tournée.

Couvre les deux fixes du bug « qualité de curation des sections thématiques »
(docs/bugs/bug-curation-qualite-sections-thematiques.md) :

- **Fix #2 — fenêtre de fraîcheur adaptative** (`_get_candidates`) : quand le
  pool 24h des sources suivies est sous le seuil, la fenêtre s'élargit (48h puis
  72h) ; sinon elle reste à 24h sans requête superflue. Testé bout-à-bout contre
  la DB via `_get_candidates` (même véhicule que test_feed_chronological_refresh).

- **Fix #1 — routage vers le PillarScoringEngine** : le moteur de scoring (vers
  lequel `personalized_theme_mode` est désormais routé) classe un article riche
  (`content_quality='full'` + image) au-dessus d'un teaser `none` à thème égal.
  C'est exactement le reclassement que le fix introduit (cf. la preuve empirique
  end-to-end dans scripts/prove_thematic_scoring.py).
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest

from app.models.content import Content
from app.models.enums import ContentType, ReliabilityScore
from app.models.source import Source, SourceType
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import (
    PillarScoringEngine,
    ScoringContext,
)
from app.services.recommendation_service import RecommendationService


@pytest.fixture
def user_id() -> UUID:
    return uuid4()


@pytest.fixture
async def followed_tech_source(db_session):
    source = Source(
        id=uuid4(),
        name="Tech Test Source",
        url="https://tech-test.com",
        feed_url=f"https://tech-test.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.commit()
    return source


async def _add_tech_contents(db_session, source_id: UUID, count: int, hours_ago: float):
    """Insert `count` tech articles published `hours_ago` hours before now."""
    published = datetime.now(UTC) - timedelta(hours=hours_ago)
    ids = []
    for _ in range(count):
        cid = uuid4()
        ids.append(cid)
        db_session.add(
            Content(
                id=cid,
                source_id=source_id,
                title=f"Tech article {cid}",
                url=f"https://example.com/{cid}",
                guid=f"guid-{cid}",
                published_at=published,
                content_type=ContentType.ARTICLE,
                theme="tech",
                topics=["tech", "ai"],
                content_quality="full",
            )
        )
    await db_session.commit()
    return set(ids)


# --------------------------------------------------------------------------
# Fix #2 — fenêtre de fraîcheur adaptative
# --------------------------------------------------------------------------


async def test_adaptive_window_widens_when_24h_pool_below_threshold(
    db_session, followed_tech_source, user_id
):
    """Pool 24h sous le seuil → la fenêtre s'élargit pour récupérer du contenu
    plus ancien (48h) plutôt que de rendre une section quasi vide."""
    assert ScoringWeights.THEMATIC_MIN_POOL_SIZE == 8  # garde-fou du test
    in_24h = await _add_tech_contents(
        db_session, followed_tech_source.id, count=3, hours_ago=10
    )
    in_48h = await _add_tech_contents(
        db_session, followed_tech_source.id, count=10, hours_ago=36
    )

    service = RecommendationService(db_session)
    candidates = await service._get_candidates(
        user_id=user_id,
        limit_candidates=100,
        theme="tech",
        personalized=True,
        followed_source_ids={followed_tech_source.id},
        user_subtopics={"tech", "ai"},
    )

    ids = {c.id for c in candidates}
    # 3 < 8 → on élargit à 48h et on récupère les 10 articles de 36h.
    assert len(candidates) >= ScoringWeights.THEMATIC_MIN_POOL_SIZE
    assert in_24h <= ids
    assert in_48h & ids, "la fenêtre élargie doit inclure les articles de 36h"


async def test_adaptive_window_stays_24h_when_pool_sufficient(
    db_session, followed_tech_source, user_id
):
    """Pool 24h suffisant → on reste à 24h, sans aller chercher le contenu plus
    ancien (pas d'élargissement superflu)."""
    in_24h = await _add_tech_contents(
        db_session, followed_tech_source.id, count=10, hours_ago=10
    )
    older = await _add_tech_contents(
        db_session, followed_tech_source.id, count=5, hours_ago=36
    )

    service = RecommendationService(db_session)
    candidates = await service._get_candidates(
        user_id=user_id,
        limit_candidates=100,
        theme="tech",
        personalized=True,
        followed_source_ids={followed_tech_source.id},
        user_subtopics={"tech", "ai"},
    )

    ids = {c.id for c in candidates}
    # 10 >= 8 → on s'arrête à 24h : les articles de 36h ne doivent PAS apparaître.
    assert in_24h <= ids
    assert not (older & ids), "le pool 24h suffit, pas d'élargissement à 48h"


def test_thematic_window_tiers_and_floor_config():
    """Paliers (24,48,72) — plafond 72h, pas de palier 7j (décision PO) — et
    le plancher absolu THEMATIC_HARD_FLOOR=5 existe."""
    assert ScoringWeights.THEMATIC_WINDOW_TIERS_HOURS == (24, 48, 72)
    assert max(ScoringWeights.THEMATIC_WINDOW_TIERS_HOURS) == 72  # pas de 168h
    assert ScoringWeights.THEMATIC_HARD_FLOOR == 5


@pytest.fixture
async def curated_unfollowed_tech_source(db_session):
    """Source curée tech NON suivie par l'utilisateur (alimente le backfill)."""
    source = Source(
        id=uuid4(),
        name="Tech Curated Unfollowed",
        url="https://tech-curated.com",
        feed_url=f"https://tech-curated.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.commit()
    return source


async def test_backfill_reaches_floor_with_curated_unfollowed(
    db_session, followed_tech_source, curated_unfollowed_tech_source, user_id
):
    """Pool suivi sous le plancher (3) → complété par des sources curées NON
    suivies pour atteindre ≥5 ; les articles suivis restent en tête."""
    followed = await _add_tech_contents(
        db_session, followed_tech_source.id, count=3, hours_ago=10
    )
    unfollowed = await _add_tech_contents(
        db_session, curated_unfollowed_tech_source.id, count=6, hours_ago=20
    )

    service = RecommendationService(db_session)
    candidates = await service._get_candidates(
        user_id=user_id,
        limit_candidates=100,
        theme="tech",
        personalized=True,
        followed_source_ids={followed_tech_source.id},
    )

    ids = [c.id for c in candidates]
    id_set = set(ids)
    assert len(candidates) >= ScoringWeights.THEMATIC_HARD_FLOOR
    assert followed <= id_set, "les articles suivis doivent être présents"
    assert unfollowed & id_set, "le backfill curé non-suivi doit compléter le pool"
    # Suivies d'abord : tous les articles suivis précèdent le 1er article backfill.
    last_followed = max(i for i, cid in enumerate(ids) if cid in followed)
    first_backfill = min(i for i, cid in enumerate(ids) if cid in unfollowed)
    assert last_followed < first_backfill, "followed sources must precede backfill"


async def test_no_backfill_when_followed_pool_sufficient_db(
    db_session, followed_tech_source, curated_unfollowed_tech_source, user_id
):
    """Pool suivi ≥ plancher → aucun article de source non-suivie n'est ajouté."""
    await _add_tech_contents(
        db_session, followed_tech_source.id, count=6, hours_ago=10
    )
    unfollowed = await _add_tech_contents(
        db_session, curated_unfollowed_tech_source.id, count=6, hours_ago=20
    )

    service = RecommendationService(db_session)
    candidates = await service._get_candidates(
        user_id=user_id,
        limit_candidates=100,
        theme="tech",
        personalized=True,
        followed_source_ids={followed_tech_source.id},
    )

    id_set = {c.id for c in candidates}
    assert not (unfollowed & id_set), (
        "pool suivi suffisant (≥ plancher) → pas de backfill non-suivi"
    )


# --------------------------------------------------------------------------
# Fix #1 — le PillarScoringEngine privilégie la qualité (article riche > teaser)
# --------------------------------------------------------------------------


def _content(quality: str, has_image: bool, source: Source) -> Content:
    return Content(
        id=uuid4(),
        source_id=source.id,
        source=source,
        title="Article",
        theme="tech",
        topics=["tech", "ai"],
        content_quality=quality,
        thumbnail_url="https://img" if has_image else None,
        language=None,
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        description="",
        duration_seconds=None,
        entities=[],
    )


def test_pillar_engine_ranks_rich_article_above_none_teaser():
    """À thème/sous-thèmes/source égaux, un article full+image score plus haut
    qu'un teaser none sans contenu lisible — c'est ce que le routage de Fix #1
    fait remonter (vs le tri chronologique pur qui les ignore)."""
    source = Source(
        id=uuid4(),
        name="Src",
        theme="tech",
        is_curated=True,
        source_tier="deep",
        reliability_score=ReliabilityScore.HIGH,
        secondary_themes=[],
        tone=None,
    )
    rich = _content("full", True, source)
    teaser = _content("none", False, source)

    context = ScoringContext(
        user_profile=None,
        user_interests={"tech"},
        user_interest_weights={"tech": 3.0},
        followed_source_ids={source.id},
        user_prefs={},
        now=datetime.now(UTC),
        user_subtopics={"tech", "ai"},
        user_subtopic_weights={"tech": 3.0, "ai": 3.0},
    )
    engine = PillarScoringEngine()

    rich_score = engine.compute_score(rich, context).final_score
    teaser_score = engine.compute_score(teaser, context).final_score
    assert rich_score > teaser_score
