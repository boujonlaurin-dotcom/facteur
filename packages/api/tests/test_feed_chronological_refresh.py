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
from app.services.recommendation_service import RecommendationService


@pytest.fixture
async def test_contents(db_session, test_source):
    """Create 2 Content rows from the same source, published now."""
    contents = []
    for i in range(2):
        c = Content(
            id=uuid4(),
            source_id=test_source.id,
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
        self, db_session, test_contents, test_source, user_id
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
            source_id=test_source.id,
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
