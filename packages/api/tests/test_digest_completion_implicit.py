"""Tests pour DigestService.maybe_record_implicit_completion.

Plan engagement & PMF — Sprint 1.3. Règle implicite : quand un user a consumed
≥ 80 % des items du daily_digest du jour, on INSERT idempotemment une row dans
`digest_completions` (contrainte UNIQUE sur user_id+target_date).

Les tests mockent la session SQLAlchemy et inspectent :
- l'existence (ou non) d'un appel `execute(insert stmt)` sur DigestCompletion
- le bypass quand le seuil n'est pas atteint
- le bypass quand le content_id n'appartient pas au digest
- la tolérance aux exceptions (jamais fatal pour le caller)
"""

from datetime import date
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest
from sqlalchemy.dialects.postgresql import Insert as PgInsert

from app.models.daily_digest import DailyDigest
from app.models.digest_completion import DigestCompletion
from app.services.digest_service import DigestService


def _make_digest(user_id: UUID, content_ids: list[UUID]) -> DailyDigest:
    digest = DailyDigest()
    digest.user_id = user_id
    digest.target_date = date(2026, 4, 24)
    digest.items = [{"content_id": str(cid)} for cid in content_ids]
    digest.is_serene = False
    digest.format_version = "flat_v1"
    return digest


def _mock_session_with(
    digest: DailyDigest | None,
    consumed_count: int,
    inserted_id: UUID | None = None,
):
    """Return an AsyncMock session where:
    - first execute() resolves to a list containing `digest` (or empty)
    - second execute() resolves to the consumed count (or unused)
    - third execute() is the insert statement we assert on; its
      `scalar_one_or_none()` returns `inserted_id` (None => ON CONFLICT no-op)
    """
    session = AsyncMock()

    digest_result = MagicMock()
    digest_result.scalars.return_value.all.return_value = [digest] if digest else []

    count_result = MagicMock()
    count_result.scalar_one.return_value = consumed_count

    insert_result = MagicMock()
    insert_result.scalar_one_or_none.return_value = inserted_id

    session.execute = AsyncMock(
        side_effect=[digest_result, count_result, insert_result]
    )
    return session


@pytest.fixture
def user_id() -> UUID:
    return uuid4()


@pytest.fixture
def service_with_mocks():
    def _build(session):
        with (
            patch("app.services.digest_service.DigestSelector"),
            patch("app.services.digest_service.StreakService"),
        ):
            return DigestService(session)

    return _build


@pytest.mark.asyncio
async def test_inserts_completion_when_threshold_reached(
    service_with_mocks, user_id
):
    content_ids = [uuid4() for _ in range(5)]
    digest = _make_digest(user_id, content_ids)
    # 4 / 5 = 80% → triggers
    session = _mock_session_with(digest, consumed_count=4)
    service = service_with_mocks(session)

    with patch(
        "app.services.digest_service.today_paris",
        return_value=date(2026, 4, 24),
    ):
        recorded = await service.maybe_record_implicit_completion(
            user_id, content_ids[0]
        )

    assert recorded is True
    # Third execute call should be the pg_insert on DigestCompletion
    assert session.execute.await_count == 3
    insert_stmt = session.execute.await_args_list[2].args[0]
    assert isinstance(insert_stmt, PgInsert)
    assert insert_stmt.table.name == DigestCompletion.__tablename__


@pytest.mark.asyncio
async def test_skips_when_below_threshold(service_with_mocks, user_id):
    content_ids = [uuid4() for _ in range(5)]
    digest = _make_digest(user_id, content_ids)
    # 3 / 5 = 60% → below 80%
    session = _mock_session_with(digest, consumed_count=3)
    service = service_with_mocks(session)

    with patch(
        "app.services.digest_service.today_paris",
        return_value=date(2026, 4, 24),
    ):
        recorded = await service.maybe_record_implicit_completion(
            user_id, content_ids[0]
        )

    assert recorded is False
    # Only the digest select + count query should have run — no insert.
    assert session.execute.await_count == 2


@pytest.mark.asyncio
async def test_skips_when_content_not_in_digest(service_with_mocks, user_id):
    digest_content_ids = [uuid4() for _ in range(5)]
    digest = _make_digest(user_id, digest_content_ids)
    session = _mock_session_with(digest, consumed_count=99)
    service = service_with_mocks(session)

    foreign_content_id = uuid4()

    with patch(
        "app.services.digest_service.today_paris",
        return_value=date(2026, 4, 24),
    ):
        recorded = await service.maybe_record_implicit_completion(
            user_id, foreign_content_id
        )

    assert recorded is False
    # Only the digest select should have fired — content skip short-circuits.
    assert session.execute.await_count == 1


@pytest.mark.asyncio
async def test_no_digest_today_returns_false(service_with_mocks, user_id):
    session = _mock_session_with(None, consumed_count=0)
    service = service_with_mocks(session)

    with patch(
        "app.services.digest_service.today_paris",
        return_value=date(2026, 4, 24),
    ):
        recorded = await service.maybe_record_implicit_completion(
            user_id, uuid4()
        )

    assert recorded is False


@pytest.mark.asyncio
async def test_swallows_exceptions(service_with_mocks, user_id):
    session = AsyncMock()
    session.execute = AsyncMock(side_effect=RuntimeError("db offline"))
    service = service_with_mocks(session)

    # Must never raise — caller (update_content_status) relies on this.
    recorded = await service.maybe_record_implicit_completion(
        user_id, uuid4()
    )
    assert recorded is False


@pytest.mark.asyncio
async def test_insert_uses_on_conflict_do_nothing(
    service_with_mocks, user_id
):
    """The INSERT must be idempotent via ON CONFLICT DO NOTHING on the
    (user_id, target_date) UNIQUE — otherwise the explicit completion path
    and the implicit path would race and one would raise IntegrityError."""
    content_ids = [uuid4() for _ in range(5)]
    digest = _make_digest(user_id, content_ids)
    session = _mock_session_with(digest, consumed_count=5)
    service = service_with_mocks(session)

    with patch(
        "app.services.digest_service.today_paris",
        return_value=date(2026, 4, 24),
    ):
        await service.maybe_record_implicit_completion(user_id, content_ids[0])

    insert_stmt = session.execute.await_args_list[2].args[0]
    # Compile to inspect the ON CONFLICT clause.
    from sqlalchemy.dialects import postgresql

    compiled_sql = str(
        insert_stmt.compile(dialect=postgresql.dialect())
    ).lower()
    assert "on conflict" in compiled_sql
    assert "do nothing" in compiled_sql


@pytest.mark.asyncio
async def test_updates_closure_streak_on_successful_insert(
    service_with_mocks, user_id
):
    """When the implicit INSERT actually writes a new row, the closure streak
    must be incremented so users who never tap `terminer` still see their
    streak tick. Conflict no-ops should skip the streak update."""
    content_ids = [uuid4() for _ in range(5)]
    digest = _make_digest(user_id, content_ids)
    session = _mock_session_with(
        digest, consumed_count=5, inserted_id=uuid4()
    )
    service = service_with_mocks(session)
    service._update_closure_streak = AsyncMock(return_value={"current": 1})

    with patch(
        "app.services.digest_service.today_paris",
        return_value=date(2026, 4, 24),
    ):
        await service.maybe_record_implicit_completion(user_id, content_ids[0])

    service._update_closure_streak.assert_awaited_once_with(user_id)


@pytest.mark.asyncio
async def test_skips_closure_streak_on_conflict(service_with_mocks, user_id):
    """ON CONFLICT no-op (row already existed via explicit path) must NOT
    bump the streak a second time."""
    content_ids = [uuid4() for _ in range(5)]
    digest = _make_digest(user_id, content_ids)
    session = _mock_session_with(digest, consumed_count=5, inserted_id=None)
    service = service_with_mocks(session)
    service._update_closure_streak = AsyncMock()

    with patch(
        "app.services.digest_service.today_paris",
        return_value=date(2026, 4, 24),
    ):
        await service.maybe_record_implicit_completion(user_id, content_ids[0])

    service._update_closure_streak.assert_not_awaited()


@pytest.mark.asyncio
async def test_supports_topics_v1_format(service_with_mocks, user_id):
    """Digest stored in `topics_v1` dict format should also be parsed."""
    content_ids = [uuid4() for _ in range(5)]
    digest = DailyDigest()
    digest.user_id = user_id
    digest.target_date = date(2026, 4, 24)
    digest.items = {
        "format": "topics_v1",
        "topics": [
            {
                "topic_id": "t1",
                "articles": [{"content_id": str(cid)} for cid in content_ids],
            }
        ],
    }
    digest.is_serene = False
    digest.format_version = "topics_v1"

    session = _mock_session_with(digest, consumed_count=5)
    service = service_with_mocks(session)

    with patch(
        "app.services.digest_service.today_paris",
        return_value=date(2026, 4, 24),
    ):
        recorded = await service.maybe_record_implicit_completion(
            user_id, content_ids[0]
        )

    assert recorded is True
