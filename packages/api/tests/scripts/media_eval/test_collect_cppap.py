"""Tests du collecteur CPPAP (collect_cppap.py) — open data (D5).

Couvre : titre trouvé → present + numero_cppap ; recherche vide →
absent_verifie ; dataset inaccessible → bloque_acces ; réponse non-JSON →
bloque_acces (jamais d'exception).
"""

from __future__ import annotations

from pathlib import Path

from sqlalchemy import select

from app.models.media_eval import MediaEvalSignal, ModeAcces, StatutSignal
from scripts.media_eval.collect_common import FetchResult
from scripts.media_eval.collect_cppap import (
    chercher_titre,
    collecter,
    cppap_url,
    parse_cppap_records,
)

API = Path(__file__).resolve().parents[1] / "fixtures" / "media_eval" / "api"


def _read(name: str) -> str:
    return (API / name).read_text()


def make_fetcher(status: int, texte: str):
    async def _fetch(url: str) -> FetchResult:
        if status == 403:
            return FetchResult(url, 403, "", ModeAcces.BLOQUE, "HTTP 403")
        return FetchResult(url, status, texte, ModeAcces.LIBRE, None)

    return _fetch


class TestParsePur:
    def test_parse_records(self):
        records = parse_cppap_records(_read("cppap_records.json"))
        assert len(records) == 1
        assert records[0]["numero_cppap"] == "0426 W 92142"

    def test_chercher_titre(self):
        records = parse_cppap_records(_read("cppap_records.json"))
        assert chercher_titre("CNEWS", records) is not None
        assert chercher_titre("Reporterre", records) is None

    def test_parse_empty(self):
        assert parse_cppap_records(_read("cppap_empty.json")) == []

    def test_parse_records_v2(self):
        """Forme Explore v2.1 : ``results`` à plat, champ ``ndeg_cppap``."""
        records = parse_cppap_records(_read("cppap_records_v2.json"))
        assert len(records) == 1
        assert records[0]["titre"] == "CNEWS"
        assert records[0]["numero_cppap"] == "0426 W 92142"
        assert chercher_titre("CNEWS", records) is not None


class TestCollecter:
    async def test_present(self, db_session, media_cnews, run_test):
        stats = await collecter(
            db_session,
            media_cnews,
            run_test,
            make_fetcher(200, _read("cppap_records.json")),
        )
        await db_session.commit()
        assert stats.inseres == 1
        signal = (await db_session.execute(select(MediaEvalSignal))).scalar_one()
        assert signal.statut == StatutSignal.PRESENT
        assert signal.valeur["numero_cppap"] == "0426 W 92142"

    async def test_absent(self, db_session, media_reporterre, run_test):
        stats = await collecter(
            db_session,
            media_reporterre,
            run_test,
            make_fetcher(200, _read("cppap_empty.json")),
        )
        await db_session.commit()
        assert stats.inseres == 1
        signal = (await db_session.execute(select(MediaEvalSignal))).scalar_one()
        assert signal.statut == StatutSignal.ABSENT_VERIFIE

    async def test_bloque_reponse_non_json(self, db_session, media_cnews, run_test):
        stats = await collecter(
            db_session, media_cnews, run_test, make_fetcher(200, "<html>captcha</html>")
        )
        await db_session.commit()
        assert stats.bloques == 1
        signal = (await db_session.execute(select(MediaEvalSignal))).scalar_one()
        assert signal.statut == StatutSignal.BLOQUE_ACCES

    def test_cppap_url_encode(self):
        url = cppap_url("Le Monde")
        assert "liste-des-publications-de-presse" in url
        assert "%20" in url  # espace encodé dans la phrase entre guillemets
