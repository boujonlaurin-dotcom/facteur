"""Tests pour l'exclusion des articles récemment impressionés du feed chronologique.

Vérifie que le filtre SQL de `_get_candidates` :
- Exclut les articles avec `last_impressed_at` dans la dernière heure (default feed)
- Ré-inclut les articles dont l'impression date de plus d'une heure
- N'exclut pas les articles impressionés en cas de filtre explicite (source_id)
- Exclut les articles avec `manually_impressed = True`
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy.dialects.postgresql import insert

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType
from app.models.source import Source, SourceType
from app.services.recommendation_service import RecommendationService


@pytest.fixture
async def curated_source(db_session):
    """Source curée (is_curated=True) requise pour passer le filtre de _get_candidates
    sans followed_source_ids — la branche par défaut filtre sur Source.is_curated."""
    source = Source(
        id=uuid4(),
        name="Curated Test Source",
        url="https://curated-test.com",
        feed_url=f"https://curated-test.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.commit()
    return source


@pytest.fixture
async def test_contents(db_session, curated_source):
    """Create 2 Content rows from a curated source, published now."""
    contents = []
    for i in range(2):
        c = Content(
            id=uuid4(),
            source_id=curated_source.id,
            title=f"Chrono refresh article {i}",
            url=f"https://example.com/chrono-{i}-{uuid4()}",
            guid=f"chrono-guid-{uuid4()}",
            published_at=datetime.now(UTC),
            content_type=ContentType.ARTICLE,
        )
        db_session.add(c)
        contents.append(c)
    await db_session.commit()
    return contents


@pytest.fixture
def user_id() -> UUID:
    return uuid4()


async def _set_impression(
    db_session,
    user_id: UUID,
    content_id: UUID,
    *,
    last_impressed_at: datetime | None = None,
    manually_impressed: bool = False,
):
    """Upsert a UserContentStatus row with the given impression state."""
    now = datetime.now(UTC)
    stmt = (
        insert(UserContentStatus)
        .values(
            user_id=user_id,
            content_id=content_id,
            status=ContentStatus.UNSEEN.value,
            last_impressed_at=last_impressed_at,
            manually_impressed=manually_impressed,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=["user_id", "content_id"],
            set_={
                "last_impressed_at": last_impressed_at,
                "manually_impressed": manually_impressed,
                "updated_at": now,
            },
        )
    )
    await db_session.execute(stmt)
    await db_session.commit()


class TestChronologicalRefreshFilter:
    async def test_recently_impressed_article_excluded_from_default_feed(
        self, db_session, test_contents, user_id
    ):
        """<1h impression → article absent du feed par défaut (mode=None)."""
        target, other = test_contents

        await _set_impression(
            db_session,
            user_id,
            target.id,
            last_impressed_at=datetime.now(UTC) - timedelta(minutes=5),
        )

        service = RecommendationService(db_session)
        candidates = await service._get_candidates(
            user_id=user_id,
            limit_candidates=50,
            mode=None,
        )

        candidate_ids = {c.id for c in candidates}
        assert target.id not in candidate_ids
        assert other.id in candidate_ids

    async def test_old_impression_article_reappears(
        self, db_session, test_contents, user_id
    ):
        """>1h impression → article re-éligible au feed par défaut."""
        target, _ = test_contents

        await _set_impression(
            db_session,
            user_id,
            target.id,
            last_impressed_at=datetime.now(UTC) - timedelta(hours=2),
        )

        service = RecommendationService(db_session)
        candidates = await service._get_candidates(
            user_id=user_id,
            limit_candidates=50,
            mode=None,
        )

        assert target.id in {c.id for c in candidates}

    async def test_explicit_source_filter_ignores_impression(
        self, db_session, test_contents, curated_source, user_id
    ):
        """source_id explicite → articles impressionés encore visibles."""
        target, _ = test_contents

        await _set_impression(
            db_session,
            user_id,
            target.id,
            last_impressed_at=datetime.now(UTC) - timedelta(minutes=5),
        )

        service = RecommendationService(db_session)
        candidates = await service._get_candidates(
            user_id=user_id,
            limit_candidates=50,
            mode=None,
            source_id=curated_source.id,
        )

        assert target.id in {c.id for c in candidates}

    async def test_manually_impressed_article_excluded(
        self, db_session, test_contents, user_id
    ):
        """manually_impressed=True → article définitivement exclu du feed défaut."""
        target, other = test_contents

        await _set_impression(
            db_session,
            user_id,
            target.id,
            last_impressed_at=None,
            manually_impressed=True,
        )

        service = RecommendationService(db_session)
        candidates = await service._get_candidates(
            user_id=user_id,
            limit_candidates=50,
            mode=None,
        )

        candidate_ids = {c.id for c in candidates}
        assert target.id not in candidate_ids
        assert other.id in candidate_ids


# ---------------------------------------------------------------------------
# Story 12.8 — Tests P1/P2 : formule multiplier² + halving quota sans intérêt
# ---------------------------------------------------------------------------


def _fake_article(source_id, *, theme=None, topics=None, title="", description=""):
    """Build a lightweight Content-like object for diversification tests.

    `_apply_chronological_diversification` and `_article_matches_interests`
    only touch `source_id`, `published_at`, `theme`, `topics`, `title`,
    `description` — we avoid full DB fixtures to keep these tests fast.
    """
    from types import SimpleNamespace

    return SimpleNamespace(
        id=uuid4(),
        source_id=source_id,
        published_at=datetime.now(UTC),
        theme=theme,
        topics=topics or [],
        title=title,
        description=description,
    )


class TestChronoMultiplierSquared:
    """P2 — la formule quota utilise `multiplier²` (pas `multiplier`)."""

    def test_multiplier_half_yields_quarter_quota(self):
        from app.services.recommendation_service import RecommendationService

        src_a = uuid4()  # priority 1.0
        src_b = uuid4()  # priority 0.5 → multiplier² = 0.25
        candidates = [_fake_article(src_a) for _ in range(40)] + [
            _fake_article(src_b) for _ in range(40)
        ]
        multipliers = {src_a: 1.0, src_b: 0.5}

        retained, _ = RecommendationService._apply_chronological_diversification(
            candidates,
            multipliers,
            limit=20,
            offset=0,
        )
        counts = {src_a: 0, src_b: 0}
        for a in retained:
            counts[a.source_id] += 1

        assert counts[src_b] < counts[src_a]
        assert counts[src_b] <= 4

    def test_multiplier_two_yields_four_times_quota(self):
        from app.services.recommendation_service import RecommendationService

        src_a = uuid4()  # priority 1.0
        src_b = uuid4()  # priority 2.0 → multiplier² = 4
        candidates = [_fake_article(src_a) for _ in range(40)] + [
            _fake_article(src_b) for _ in range(40)
        ]
        multipliers = {src_a: 1.0, src_b: 2.0}

        retained, _ = RecommendationService._apply_chronological_diversification(
            candidates,
            multipliers,
            limit=20,
            offset=0,
        )
        counts = {src_a: 0, src_b: 0}
        for a in retained:
            counts[a.source_id] += 1

        assert counts[src_b] > counts[src_a]


class TestChronoInterestHalving:
    """P1 — quota ÷2 si la source n'a aucun article qui matche les intérêts."""

    def test_source_without_interest_match_is_halved(self):
        from app.services.recommendation_service import (
            InterestContext,
            RecommendationService,
        )

        src_match = uuid4()
        src_no_match = uuid4()
        candidates = [
            _fake_article(src_match, theme="tech") for _ in range(40)
        ] + [_fake_article(src_no_match, theme="sports") for _ in range(40)]
        multipliers = {src_match: 1.0, src_no_match: 1.0}
        interest_ctx = InterestContext(
            user_interests={"tech"},
            user_subtopics=set(),
            custom_topic_keywords=[],
        )

        retained, _ = RecommendationService._apply_chronological_diversification(
            candidates,
            multipliers,
            limit=20,
            offset=0,
            interest_context=interest_ctx,
        )
        counts = {src_match: 0, src_no_match: 0}
        for a in retained:
            counts[a.source_id] += 1

        assert counts[src_no_match] < counts[src_match]

    def test_any_single_match_keeps_full_quota(self):
        """Un seul article qui matche suffit à éviter le halving."""
        from app.services.recommendation_service import (
            InterestContext,
            RecommendationService,
        )

        src_a = uuid4()
        src_b = uuid4()
        candidates_a = [_fake_article(src_a, theme="tech") for _ in range(40)]
        candidates_b = [_fake_article(src_b, theme="sports") for _ in range(39)] + [
            _fake_article(src_b, theme="tech")
        ]
        multipliers = {src_a: 1.0, src_b: 1.0}
        interest_ctx = InterestContext(
            user_interests={"tech"},
            user_subtopics=set(),
            custom_topic_keywords=[],
        )

        retained, _ = RecommendationService._apply_chronological_diversification(
            candidates_a + candidates_b,
            multipliers,
            limit=20,
            offset=0,
            interest_context=interest_ctx,
        )
        counts = {src_a: 0, src_b: 0}
        for a in retained:
            counts[a.source_id] += 1

        assert counts[src_b] >= counts[src_a] - 2

    def test_empty_interest_context_disables_halving(self):
        """Sans intérêts déclarés → backward-compat (P2 seul)."""
        from app.services.recommendation_service import (
            InterestContext,
            RecommendationService,
        )

        src_a = uuid4()
        src_b = uuid4()
        candidates = [_fake_article(src_a) for _ in range(40)] + [
            _fake_article(src_b) for _ in range(40)
        ]
        multipliers = {src_a: 1.0, src_b: 1.0}
        empty_ctx = InterestContext()
        assert empty_ctx.is_empty()

        retained, _ = RecommendationService._apply_chronological_diversification(
            candidates,
            multipliers,
            limit=20,
            offset=0,
            interest_context=empty_ctx,
        )
        counts = {src_a: 0, src_b: 0}
        for a in retained:
            counts[a.source_id] += 1

        assert abs(counts[src_a] - counts[src_b]) <= 1

    def test_subtopic_match_via_topics(self):
        from app.services.recommendation_service import (
            InterestContext,
            _article_matches_interests,
        )

        article = _fake_article(uuid4(), theme="other", topics=["startups", "ai"])
        ctx = InterestContext(
            user_interests=set(),
            user_subtopics={"ai"},
            custom_topic_keywords=[],
        )
        assert _article_matches_interests(article, ctx) is True

    def test_custom_topic_keyword_match(self):
        from app.services.recommendation_service import (
            InterestContext,
            _article_matches_interests,
        )

        article = _fake_article(
            uuid4(),
            theme="other",
            title="Mistral AI lève un tour de série C",
            description="Une startup française…",
        )
        ctx = InterestContext(
            user_interests=set(),
            user_subtopics=set(),
            custom_topic_keywords=["mistral ai"],
        )
        assert _article_matches_interests(article, ctx) is True
