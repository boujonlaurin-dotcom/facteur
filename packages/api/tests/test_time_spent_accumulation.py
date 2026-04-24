"""Test l'accumulation de `time_spent_seconds` sur `user_content_status`.

Plan engagement & PMF — Sprint 1.1. Le service ne doit plus écraser la valeur
existante : le conflict_set doit utiliser `coalesce(existing, 0) + new` pour
que les sessions successives s'additionnent (pré-requis du feedback loop
interest weights).

Sprint 1.3. Vérifie aussi que la règle implicite `digest_completions` est
bien câblée dans la branche CONSUMED.

Pas de DB requise : on inspecte le SQL compilé du statement upsert.
"""

from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from sqlalchemy.dialects import postgresql

from app.models.content import UserContentStatus
from app.models.enums import ContentStatus
from app.schemas.content import ContentStatusUpdate
from app.services.content_service import ContentService


def _captured_stmt(session_mock):
    """Retrieve the compiled UPSERT passed to `session.scalars`."""
    assert session_mock.scalars.call_args is not None
    stmt = session_mock.scalars.call_args.args[0]
    return str(stmt.compile(dialect=postgresql.dialect()))


@pytest.mark.asyncio
async def test_time_spent_uses_accumulation_expression_in_conflict_set():
    session = AsyncMock()
    mock_status = UserContentStatus(
        user_id=uuid4(), content_id=uuid4(), time_spent_seconds=60
    )
    result = MagicMock()
    result.one.return_value = mock_status
    session.scalars.return_value = result

    service = ContentService(session)
    await service.update_content_status(
        user_id=uuid4(),
        content_id=uuid4(),
        update_data=ContentStatusUpdate(time_spent_seconds=30),
    )

    sql = _captured_stmt(session).lower()
    # The ON CONFLICT DO UPDATE must reference the existing row value,
    # not overwrite it with a plain parameter.
    assert "on conflict" in sql
    assert "coalesce" in sql
    assert "user_content_status.time_spent_seconds" in sql


@pytest.mark.asyncio
async def test_time_spent_absent_does_not_emit_time_spent_in_conflict_set():
    """Update sans time_spent (ex: juste reading_progress) ne doit pas toucher
    `time_spent_seconds` dans le SET clause — sinon on le reset à 0."""
    session = AsyncMock()
    mock_status = UserContentStatus(
        user_id=uuid4(), content_id=uuid4(), time_spent_seconds=60
    )
    result = MagicMock()
    result.one.return_value = mock_status
    session.scalars.return_value = result

    service = ContentService(session)
    await service.update_content_status(
        user_id=uuid4(),
        content_id=uuid4(),
        update_data=ContentStatusUpdate(reading_progress=50),
    )

    sql = _captured_stmt(session).lower()
    # When time_spent_seconds is not provided, it must NOT appear in the SET.
    # We assert the value column is never on the left side of a `=` in the SET list.
    # The upsert SQL contains columns only in VALUES and SET — none of these
    # references should mention `time_spent_seconds = …` for this call.
    assert "time_spent_seconds =" not in sql
    assert "time_spent_seconds=" not in sql


@pytest.mark.asyncio
async def test_consumed_status_triggers_implicit_digest_completion():
    """When status becomes CONSUMED, update_content_status must invoke
    DigestService.maybe_record_implicit_completion so the engagement funnel
    catches users who never tap "terminer mon digest"."""
    session = AsyncMock()
    mock_status = UserContentStatus(user_id=uuid4(), content_id=uuid4())
    result = MagicMock()
    result.one.return_value = mock_status
    session.scalars.return_value = result
    session.get = AsyncMock(return_value=None)  # skip interest/subtopic paths

    user_id = uuid4()
    content_id = uuid4()

    with (
        patch(
            "app.services.content_service.StreakService"
        ) as streak_cls,
        patch(
            "app.services.digest_service.DigestService"
        ) as digest_cls,
    ):
        streak_cls.return_value.increment_consumption = AsyncMock()
        digest_instance = digest_cls.return_value
        digest_instance.maybe_record_implicit_completion = AsyncMock(
            return_value=True
        )

        service = ContentService(session)
        await service.update_content_status(
            user_id=user_id,
            content_id=content_id,
            update_data=ContentStatusUpdate(status=ContentStatus.CONSUMED),
        )

        digest_instance.maybe_record_implicit_completion.assert_awaited_once_with(
            user_id, content_id
        )


@pytest.mark.asyncio
async def test_non_consumed_status_skips_implicit_completion():
    """Only CONSUMED should trigger the digest_completion hook — SEEN/UNSEEN
    must not fire it (avoids spurious inserts when a user merely scrolls past
    a card)."""
    session = AsyncMock()
    mock_status = UserContentStatus(user_id=uuid4(), content_id=uuid4())
    result = MagicMock()
    result.one.return_value = mock_status
    session.scalars.return_value = result
    session.get = AsyncMock(return_value=None)

    with patch(
        "app.services.digest_service.DigestService"
    ) as digest_cls:
        service = ContentService(session)
        await service.update_content_status(
            user_id=uuid4(),
            content_id=uuid4(),
            update_data=ContentStatusUpdate(status=ContentStatus.SEEN),
        )

        digest_cls.assert_not_called()
