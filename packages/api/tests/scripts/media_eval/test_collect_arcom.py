"""Tests du collecteur ARCOM (collect_arcom.py).

Couvre : **auto-désactivation** presse en ligne (0 signal) ; audiovisuel →
sanction dans la fenêtre = C1/sanction_arcom present (avec publie_at), sanction
hors fenêtre exclue, autre média filtré ; recherche bloquée → bloque_acces.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

from sqlalchemy import func, select

from app.models.media_eval import MediaEvalSignal, ModeAcces, StatutSignal
from scripts.media_eval.collect_arcom import (
    collecter,
    concerne_media,
    parse_arcom_decisions,
    recherche_url,
)
from scripts.media_eval.collect_common import FetchResult

HTML = Path(__file__).resolve().parents[1] / "fixtures" / "media_eval" / "html"


def _read(name: str) -> str:
    return (HTML / name).read_text()


def make_fetcher(status: int, name: str | None):
    async def _fetch(url: str) -> FetchResult:
        if status == 403:
            return FetchResult(url, 403, "", ModeAcces.BLOQUE, "HTTP 403")
        text = _read(name) if name else ""
        return FetchResult(url, status, text, ModeAcces.LIBRE, None)

    return _fetch


async def _count(db_session) -> int:
    return (
        await db_session.execute(select(func.count()).select_from(MediaEvalSignal))
    ).scalar()


class TestParsePur:
    def test_parse_decisions(self):
        decisions = parse_arcom_decisions(_read("arcom_recherche_cnews.html"))
        assert len(decisions) == 3
        cnews = [d for d in decisions if concerne_media(d, "CNEWS")]
        assert len(cnews) == 2
        assert cnews[0]["publie_at"] == date(2025, 11, 12)


class TestCollecter:
    async def test_na_structurel_presse(self, db_session, media_reporterre, run_test):
        stats = await collecter(
            db_session,
            media_reporterre,
            run_test,
            make_fetcher(200, "arcom_recherche_cnews.html"),
        )
        await db_session.commit()
        # Presse en ligne → aucun signal (absence neutre).
        assert stats.inseres == 0
        assert await _count(db_session) == 0

    async def test_audiovisuel_sanction_dans_fenetre(
        self, db_session, media_cnews, run_test
    ):
        stats = await collecter(
            db_session,
            media_cnews,
            run_test,
            make_fetcher(200, "arcom_recherche_cnews.html"),
        )
        await db_session.commit()
        # Seule la sanction 2025-11-12 est dans la fenêtre (2023-05-10 exclue,
        # Europe 1 filtrée) → 1 present.
        assert stats.inseres == 1
        signal = (await db_session.execute(select(MediaEvalSignal))).scalar_one()
        assert signal.type_signal == "sanction_arcom"
        assert signal.statut == StatutSignal.PRESENT
        assert signal.valeur["publie_at"] == "2025-11-12"

    async def test_bloque(self, db_session, media_cnews, run_test):
        stats = await collecter(
            db_session, media_cnews, run_test, make_fetcher(403, None)
        )
        await db_session.commit()
        assert stats.bloques == 1
        signal = (await db_session.execute(select(MediaEvalSignal))).scalar_one()
        assert signal.statut == StatutSignal.BLOQUE_ACCES

    def test_recherche_url(self):
        assert "arcom.fr" in recherche_url("CNEWS")
