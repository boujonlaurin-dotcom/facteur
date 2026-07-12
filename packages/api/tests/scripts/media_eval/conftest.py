"""Fixtures partagées des tests media_eval."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest_asyncio

from app.models.media_eval import MediaEvalRun

RUN_ID = "run-test"


@pytest_asyncio.fixture
async def media_eval_run(db_session) -> MediaEvalRun:
    """Satisfait la FK `run_id` : les fixtures signaux/évaluations pointent
    toutes vers `run-test` (cf. RUN_ID des test_ingest_*.py et
    tests/scripts/fixtures/media_eval/*.json)."""
    run = MediaEvalRun(
        run_id=RUN_ID, version_methodo="v0", date_reference=datetime.now(UTC).date()
    )
    db_session.add(run)
    await db_session.commit()
    return run
