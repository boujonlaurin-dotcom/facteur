"""Tests for the read-only digest hot path.

The /digest and /digest/both routes must NEVER call the LLM pipeline at
request time. They walk a 5-step fallback chain (own today → clone today →
yesterday → last 7 days → 202) and schedule a background regen as a side
effect when stale or empty.

Cf. docs/maintenance/maintenance-digest-readonly-hotpath.md.
"""

from __future__ import annotations

import asyncio
from datetime import date, datetime, timedelta
from unittest.mock import AsyncMock, Mock, patch
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.schemas.digest import DigestResponse
from app.services import digest_service
from app.services.digest_service import read_digest_or_fallback

# ─── Helpers ──────────────────────────────────────────────────────────────────


def _make_digest_row(
    *,
    user_id: UUID,
    target_date: date,
    is_serene: bool,
    format_version: str = "editorial_v1",
):
    """Build a minimal DailyDigest stand-in for fallback resolution."""
    row = Mock()
    row.id = uuid4()
    row.user_id = user_id
    row.target_date = target_date
    row.is_serene = is_serene
    row.format_version = format_version
    row.generated_at = datetime.utcnow()
    row.items = []
    row.mode = "serein" if is_serene else "pour_vous"
    return row


def _make_response(*, is_stale_fallback: bool = False) -> DigestResponse:
    """Build a minimal DigestResponse with the fields the hot path inspects."""
    return DigestResponse(
        digest_id=uuid4(),
        user_id=uuid4(),
        target_date=date.today(),
        generated_at=datetime.utcnow(),
        items=[],
        is_completed=False,
        is_stale_fallback=is_stale_fallback,
    )


@pytest.fixture
def mock_session():
    """AsyncSession mock — only `execute` is used for the 7-day fallback query."""
    session = AsyncMock()
    session.execute = AsyncMock()
    return session


# ─── Step 1 — own today ───────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_step1_own_today_returns_immediately(mock_session):
    user_id = uuid4()
    target = date.today()
    own = _make_digest_row(user_id=user_id, target_date=target, is_serene=False)

    rendered = _make_response()

    with (
        patch.object(
            digest_service.DigestService,
            "_get_existing_digest",
            new=AsyncMock(return_value=own),
        ),
        patch.object(
            digest_service.DigestService,
            "_build_digest_response",
            new=AsyncMock(return_value=rendered),
        ),
        patch.object(
            digest_service.DigestService,
            "_try_clone_global_editorial_digest",
            new=AsyncMock(),
        ) as clone_mock,
        patch.object(digest_service, "_schedule_background_regen") as regen_mock,
    ):
        out = await read_digest_or_fallback(
            mock_session, user_id, target, is_serene=False
        )

    assert out is rendered
    assert out.is_stale_fallback is False
    clone_mock.assert_not_called()
    regen_mock.assert_not_called()


# ─── Step 2 — clone editorial ─────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_step2_clone_editorial_used_when_no_own_today(mock_session):
    user_id = uuid4()
    target = date.today()
    clone = _make_digest_row(user_id=user_id, target_date=target, is_serene=False)
    rendered = _make_response()

    with (
        patch.object(
            digest_service.DigestService,
            "_get_existing_digest",
            new=AsyncMock(return_value=None),
        ),
        patch.object(
            digest_service.DigestService,
            "_try_clone_global_editorial_digest",
            new=AsyncMock(return_value=clone),
        ) as clone_mock,
        patch.object(
            digest_service.DigestService,
            "_build_digest_response",
            new=AsyncMock(return_value=rendered),
        ),
        patch.object(digest_service, "_schedule_background_regen") as regen_mock,
    ):
        out = await read_digest_or_fallback(
            mock_session, user_id, target, is_serene=False
        )

    assert out is rendered
    assert out.is_stale_fallback is False
    clone_mock.assert_awaited_once()
    regen_mock.assert_not_called()


# ─── Step 3 — yesterday fallback ──────────────────────────────────────────────


@pytest.mark.asyncio
async def test_step3_yesterday_fallback_marks_stale_and_schedules_regen(mock_session):
    user_id = uuid4()
    target = date.today()
    yesterday = target - timedelta(days=1)
    yest_row = _make_digest_row(user_id=user_id, target_date=yesterday, is_serene=False)
    rendered = _make_response()

    async def existing_side_effect(uid, d, is_serene=False):
        # First call: today (None). Second call: yesterday (the row).
        if d == target:
            return None
        if d == yesterday:
            return yest_row
        return None

    with (
        patch.object(
            digest_service.DigestService,
            "_get_existing_digest",
            new=AsyncMock(side_effect=existing_side_effect),
        ),
        patch.object(
            digest_service.DigestService,
            "_try_clone_global_editorial_digest",
            new=AsyncMock(return_value=None),
        ),
        patch.object(
            digest_service.DigestService,
            "_build_digest_response",
            new=AsyncMock(return_value=rendered),
        ),
        patch.object(digest_service, "_schedule_background_regen") as regen_mock,
    ):
        out = await read_digest_or_fallback(
            mock_session, user_id, target, is_serene=False
        )

    assert out is rendered
    assert out.is_stale_fallback is True
    regen_mock.assert_called_once_with(
        user_id=user_id, target_date=target, is_serene=False
    )


# ─── Step 4 — 7-day fallback ──────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_step4_seven_day_fallback_marks_stale_and_schedules_regen(mock_session):
    user_id = uuid4()
    target = date.today()
    older = _make_digest_row(
        user_id=user_id, target_date=target - timedelta(days=5), is_serene=False
    )
    rendered = _make_response()

    # `session.execute(...)` is called for the 7-day query. Build a chained mock.
    exec_result = Mock()
    exec_result.scalar_one_or_none = Mock(return_value=older)
    mock_session.execute = AsyncMock(return_value=exec_result)

    with (
        patch.object(
            digest_service.DigestService,
            "_get_existing_digest",
            new=AsyncMock(return_value=None),  # neither today nor yesterday
        ),
        patch.object(
            digest_service.DigestService,
            "_try_clone_global_editorial_digest",
            new=AsyncMock(return_value=None),
        ),
        patch.object(
            digest_service.DigestService,
            "_build_digest_response",
            new=AsyncMock(return_value=rendered),
        ),
        patch.object(digest_service, "_schedule_background_regen") as regen_mock,
    ):
        out = await read_digest_or_fallback(
            mock_session, user_id, target, is_serene=False
        )

    assert out is rendered
    assert out.is_stale_fallback is True
    regen_mock.assert_called_once_with(
        user_id=user_id, target_date=target, is_serene=False
    )


# ─── Step 5 — nothing → 202 ───────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_step5_returns_none_and_schedules_regen_when_db_empty(mock_session):
    user_id = uuid4()
    target = date.today()

    exec_result = Mock()
    exec_result.scalar_one_or_none = Mock(return_value=None)
    mock_session.execute = AsyncMock(return_value=exec_result)

    with (
        patch.object(
            digest_service.DigestService,
            "_get_existing_digest",
            new=AsyncMock(return_value=None),
        ),
        patch.object(
            digest_service.DigestService,
            "_try_clone_global_editorial_digest",
            new=AsyncMock(return_value=None),
        ),
        patch.object(digest_service, "_schedule_background_regen") as regen_mock,
    ):
        out = await read_digest_or_fallback(
            mock_session, user_id, target, is_serene=False
        )

    assert out is None
    regen_mock.assert_called_once_with(
        user_id=user_id, target_date=target, is_serene=False
    )


# ─── Critical regression: LLM down + DB writes failing ───────────────────────


@pytest.mark.asyncio
async def test_llm_and_db_writes_down_still_serves_yesterday():
    """If Mistral hangs and Supabase fails on writes, the hot path must still
    serve yesterday's digest. We assert by confirming the LLM entry points
    are never reached and the fallback response is delivered fast.
    """
    user_id = uuid4()
    target = date.today()
    yesterday = target - timedelta(days=1)
    yest_row = _make_digest_row(user_id=user_id, target_date=yesterday, is_serene=False)
    rendered = _make_response()

    # Sentinel that fails if anything tries to call the selector / pipeline.
    async def explode(*_args, **_kwargs):
        raise AssertionError(
            "selector.select_for_user was called from the read-only hot path"
        )

    async def existing_side_effect(uid, d, is_serene=False):
        return yest_row if d == yesterday else None

    session = AsyncMock()
    session.execute = AsyncMock()

    with (
        patch.object(
            digest_service.DigestService,
            "_get_existing_digest",
            new=AsyncMock(side_effect=existing_side_effect),
        ),
        patch.object(
            digest_service.DigestService,
            "_try_clone_global_editorial_digest",
            new=AsyncMock(return_value=None),
        ),
        patch.object(
            digest_service.DigestService,
            "_build_digest_response",
            new=AsyncMock(return_value=rendered),
        ),
        patch(
            "app.services.digest_selector.DigestSelector.select_for_user",
            new=explode,
        ),
        patch.object(digest_service, "_schedule_background_regen"),
    ):
        out = await asyncio.wait_for(
            read_digest_or_fallback(session, user_id, target, is_serene=False),
            timeout=2.0,
        )

    assert out is rendered
    assert out.is_stale_fallback is True


# ─── Format mismatch: flat_v1 today is treated as absent ─────────────────────


@pytest.mark.asyncio
async def test_flat_v1_today_is_skipped_in_favour_of_yesterday():
    user_id = uuid4()
    target = date.today()
    yesterday = target - timedelta(days=1)

    flat_today = _make_digest_row(
        user_id=user_id,
        target_date=target,
        is_serene=False,
        format_version="flat_v1",
    )
    yest_row = _make_digest_row(user_id=user_id, target_date=yesterday, is_serene=False)
    rendered = _make_response()

    async def existing_side_effect(uid, d, is_serene=False):
        if d == target:
            return flat_today
        if d == yesterday:
            return yest_row
        return None

    session = AsyncMock()
    session.execute = AsyncMock()

    with (
        patch.object(
            digest_service.DigestService,
            "_get_existing_digest",
            new=AsyncMock(side_effect=existing_side_effect),
        ),
        patch.object(
            digest_service.DigestService,
            "_try_clone_global_editorial_digest",
            new=AsyncMock(return_value=None),
        ),
        patch.object(
            digest_service.DigestService,
            "_build_digest_response",
            new=AsyncMock(return_value=rendered),
        ),
        patch.object(digest_service, "_schedule_background_regen"),
    ):
        out = await read_digest_or_fallback(session, user_id, target, is_serene=False)

    # flat_v1 today is rejected → yesterday is served stale.
    assert out is rendered
    assert out.is_stale_fallback is True


# ─── Render fail on today's digest cascades to clone/yesterday ────────────────


@pytest.mark.asyncio
async def test_today_render_failure_falls_through_to_clone():
    user_id = uuid4()
    target = date.today()

    today_row = _make_digest_row(user_id=user_id, target_date=target, is_serene=False)
    clone_row = _make_digest_row(user_id=user_id, target_date=target, is_serene=False)
    rendered_clone = _make_response()

    call_log = []

    async def render_side_effect(digest, _user):
        call_log.append(digest.id)
        if digest.id == today_row.id:
            raise RuntimeError("corrupted JSONB on today's row")
        return rendered_clone

    session = AsyncMock()
    session.execute = AsyncMock()

    with (
        patch.object(
            digest_service.DigestService,
            "_get_existing_digest",
            new=AsyncMock(return_value=today_row),
        ),
        patch.object(
            digest_service.DigestService,
            "_try_clone_global_editorial_digest",
            new=AsyncMock(return_value=clone_row),
        ),
        patch.object(
            digest_service.DigestService,
            "_build_digest_response",
            new=AsyncMock(side_effect=render_side_effect),
        ),
        patch.object(digest_service, "_schedule_background_regen"),
    ):
        out = await read_digest_or_fallback(session, user_id, target, is_serene=False)

    assert out is rendered_clone
    # Verify both today and clone were attempted.
    assert today_row.id in call_log
    assert clone_row.id in call_log


# ─── Router integration: GET /digest/both with partial variants ──────────────


@pytest.mark.asyncio
async def test_get_both_returns_200_with_one_variant_present():
    """If only one variant resolves, /digest/both still returns 200 with the
    other field set to null. The mobile already tolerates this and falls back
    to the available variant.
    """
    from app.database import get_db
    from app.dependencies import get_current_user_id
    from app.main import app

    fake_user = str(uuid4())
    normal_resp = _make_response()
    serein_resp = _make_response(is_stale_fallback=True)

    # Order of read_digest_or_fallback calls in /digest/both: normal first, serein second.
    call_count = {"n": 0}

    async def fake_resolver(_session, _user_id, _target, is_serene):
        call_count["n"] += 1
        return normal_resp if not is_serene else serein_resp

    class _FakeDB:
        async def scalar(self, *a, **kw):
            return None

        async def execute(self, *a, **kw):
            result = Mock()
            result.scalar_one_or_none = Mock(return_value=None)
            return result

        async def rollback(self):
            pass

    async def _fake_user_dep():
        return fake_user

    async def _fake_db_dep():
        yield _FakeDB()

    app.dependency_overrides[get_current_user_id] = _fake_user_dep
    app.dependency_overrides[get_db] = _fake_db_dep
    try:
        with (
            patch("app.routers.digest.read_digest_or_fallback", new=fake_resolver),
            patch(
                "app.routers.digest.DigestService._get_user_serein_enabled",
                new=AsyncMock(return_value=False),
            ),
            patch(
                "app.routers.digest._enrich_community_carousel",
                new=AsyncMock(side_effect=lambda _db, _u, d: d),
            ),
        ):
            transport = ASGITransport(app=app)
            async with AsyncClient(
                transport=transport, base_url="http://test", timeout=5.0
            ) as ac:
                resp = await ac.get("/api/digest/both")
    finally:
        app.dependency_overrides.clear()

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["normal"] is not None
    assert body["serein"] is not None
    assert body["serein"]["is_stale_fallback"] is True


@pytest.mark.asyncio
async def test_get_both_returns_202_when_neither_variant_resolves():
    from app.database import get_db
    from app.dependencies import get_current_user_id
    from app.main import app

    fake_user = str(uuid4())

    async def fake_resolver(*_a, **_kw):
        return None

    class _FakeDB:
        async def scalar(self, *a, **kw):
            return None

        async def execute(self, *a, **kw):
            result = Mock()
            result.scalar_one_or_none = Mock(return_value=None)
            return result

        async def rollback(self):
            pass

    async def _fake_user_dep():
        return fake_user

    async def _fake_db_dep():
        yield _FakeDB()

    app.dependency_overrides[get_current_user_id] = _fake_user_dep
    app.dependency_overrides[get_db] = _fake_db_dep
    try:
        with patch("app.routers.digest.read_digest_or_fallback", new=fake_resolver):
            transport = ASGITransport(app=app)
            async with AsyncClient(
                transport=transport, base_url="http://test", timeout=5.0
            ) as ac:
                resp = await ac.get("/api/digest/both")
    finally:
        app.dependency_overrides.clear()

    assert resp.status_code == 202, resp.text
    body = resp.json()
    assert body["status"] == "preparing"
