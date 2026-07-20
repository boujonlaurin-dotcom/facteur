"""Tests DB de create_run.py — création, idempotence, refus de mutation.

``date_reference`` pilote la fraîcheur : sa mutation silencieuse casserait la
rejouabilité, donc ``upsert_run`` la refuse (``RunConflit``).
"""

from __future__ import annotations

from datetime import date

import pytest
from sqlalchemy import func, select

from app.models.media_eval import MediaEvalRun
from scripts.media_eval.create_run import RunConflit, upsert_run


async def _count(db_session) -> int:
    return (
        await db_session.execute(select(func.count()).select_from(MediaEvalRun))
    ).scalar()


async def _upsert(db_session, **kw):
    base = {
        "run_id": "run-x",
        "date_reference": date(2026, 7, 10),
        "libelle": "Pilote",
        "medias": ["cnews.fr"],
        "criteres": ["C1", "C5"],
    }
    base.update(kw)
    return await upsert_run(db_session, **base)


class TestUpsertRun:
    async def test_creation(self, db_session):
        action, _ = await _upsert(db_session)
        await db_session.commit()
        assert action == "cree"
        assert await _count(db_session) == 1
        run = (
            await db_session.execute(
                select(MediaEvalRun).where(MediaEvalRun.run_id == "run-x")
            )
        ).scalar_one()
        assert run.date_reference == date(2026, 7, 10)
        assert run.perimetre == {"medias": ["cnews.fr"], "criteres": ["C1", "C5"]}

    async def test_idempotence(self, db_session):
        await _upsert(db_session)
        await db_session.commit()
        action, _ = await _upsert(db_session)
        await db_session.commit()
        assert action == "inchange"
        assert await _count(db_session) == 1

    async def test_maj_libelle_et_perimetre(self, db_session):
        await _upsert(db_session)
        await db_session.commit()
        action, _ = await _upsert(
            db_session, libelle="Pilote v2", medias=["reporterre.net"]
        )
        await db_session.commit()
        assert action == "maj"
        run = (
            await db_session.execute(
                select(MediaEvalRun).where(MediaEvalRun.run_id == "run-x")
            )
        ).scalar_one()
        assert run.libelle == "Pilote v2"
        assert run.perimetre["medias"] == ["reporterre.net"]

    async def test_refus_changement_date_reference(self, db_session):
        await _upsert(db_session)
        await db_session.commit()
        with pytest.raises(RunConflit, match="date_reference"):
            await _upsert(db_session, date_reference=date(2026, 7, 11))
