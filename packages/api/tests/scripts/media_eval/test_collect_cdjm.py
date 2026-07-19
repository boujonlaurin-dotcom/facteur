"""Tests du collecteur CDJM (collect_cdjm.py).

Couvre : adhésion absente (média non membre) ; avis fondé dans la fenêtre →
C1/avis_cdjm avec publie_at ; avis fondé hors fenêtre exclu ; registre
inaccessible → bloque_acces ; idempotence.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

from sqlalchemy import func, select

from app.models.media_eval import MediaEvalSignal, ModeAcces, StatutSignal
from scripts.media_eval.collect_cdjm import (
    URL_AVIS_INDEX,
    URL_MEMBRES,
    collecter,
    media_est_membre,
    parse_avis_detail,
    parse_avis_index,
    parse_membres,
)
from scripts.media_eval.collect_common import FetchResult

HTML = Path(__file__).resolve().parents[1] / "fixtures" / "media_eval" / "html"


def _read(name: str) -> str:
    return (HTML / name).read_text()


def make_fetcher(mapping: dict[str, tuple[int, str | None]]):
    async def _fetch(url: str) -> FetchResult:
        status, name = mapping.get(url, (404, None))
        if status == 403:
            return FetchResult(url, 403, "", ModeAcces.BLOQUE, "HTTP 403")
        text = _read(name) if name else ""
        return FetchResult(
            url,
            status,
            text,
            ModeAcces.LIBRE,
            None if status == 200 else f"HTTP {status}",
        )

    return _fetch


def _cnews_mapping() -> dict[str, tuple[int, str | None]]:
    return {
        URL_MEMBRES: (200, "cdjm_membres.html"),
        URL_AVIS_INDEX: (200, "cdjm_avis_index.html"),
        "https://cdjm.org/avis/26-014-cnews-bandeau-errone/": (
            200,
            "cdjm_avis_detail.html",
        ),
        "https://cdjm.org/avis/24-101-cnews-invite/": (
            200,
            "cdjm_avis_detail_ancien.html",
        ),
    }


async def _count(db_session) -> int:
    return (
        await db_session.execute(select(func.count()).select_from(MediaEvalSignal))
    ).scalar()


class TestParsePur:
    def test_parse_membres(self):
        membres = parse_membres(_read("cdjm_membres.html"))
        assert "Reporterre" in membres
        assert media_est_membre("Reporterre", membres)
        assert not media_est_membre("CNEWS", membres)

    def test_parse_avis_index(self):
        avis = parse_avis_index(_read("cdjm_avis_index.html"))
        assert len(avis) == 3
        assert all(a["url"].startswith("https://cdjm.org/avis/") for a in avis)

    def test_parse_avis_detail(self):
        detail = parse_avis_detail(_read("cdjm_avis_detail.html"))
        assert detail["publie_at"] == date(2026, 2, 3)
        assert detail["fonde"] is True
        assert "CNEWS" in detail["media"]


class TestCollecter:
    async def test_adhesion_absente_et_avis_dans_fenetre(
        self, db_session, media_cnews, run_test
    ):
        stats = await collecter(
            db_session, media_cnews, run_test, make_fetcher(_cnews_mapping())
        )
        await db_session.commit()
        # 1 adhesion absent_verifie (C8) + 1 avis present (C1, dans la fenêtre).
        # L'avis 24-101 (2024-03-15) est hors fenêtre → exclu.
        assert stats.inseres == 2
        avis = (
            (
                await db_session.execute(
                    select(MediaEvalSignal).where(
                        MediaEvalSignal.type_signal == "avis_cdjm"
                    )
                )
            )
            .scalars()
            .all()
        )
        assert len(avis) == 1
        assert avis[0].statut == StatutSignal.PRESENT
        assert avis[0].valeur["publie_at"] == "2026-02-03"  # obligatoire pour C1

        adhesion = (
            await db_session.execute(
                select(MediaEvalSignal).where(
                    MediaEvalSignal.type_signal == "adhesion_cdjm"
                )
            )
        ).scalar_one()
        assert adhesion.statut == StatutSignal.ABSENT_VERIFIE

    async def test_registre_bloque(self, db_session, media_cnews, run_test):
        mapping = {URL_MEMBRES: (403, None), URL_AVIS_INDEX: (403, None)}
        stats = await collecter(
            db_session, media_cnews, run_test, make_fetcher(mapping)
        )
        await db_session.commit()
        assert stats.bloques == 2  # adhesion + avis index bloqués
        n_bloque = (
            await db_session.execute(
                select(func.count())
                .select_from(MediaEvalSignal)
                .where(MediaEvalSignal.statut == StatutSignal.BLOQUE_ACCES)
            )
        ).scalar()
        assert n_bloque == 2

    async def test_idempotence(self, db_session, media_cnews, run_test):
        fetcher = make_fetcher(_cnews_mapping())
        await collecter(db_session, media_cnews, run_test, fetcher)
        await db_session.commit()
        n1 = await _count(db_session)
        stats2 = await collecter(db_session, media_cnews, run_test, fetcher)
        await db_session.commit()
        assert stats2.inseres == 0
        assert await _count(db_session) == n1
