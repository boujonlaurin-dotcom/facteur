"""Tests du collecteur JTI (collect_jti.py).

Couvre : média absent de l'annuaire → absent_verifie (cas pilotes) ; média
certifié valide → present + en_cours_de_validite (déclenche le raccourci) ;
certification expirée → validité fausse ; annuaire bloqué → bloque_acces.
"""

from __future__ import annotations

from pathlib import Path

from sqlalchemy import select

from app.models.media_eval import MediaEvalSignal, ModeAcces, StatutSignal
from scripts.media_eval.collect_common import FetchResult
from scripts.media_eval.collect_jti import (
    URL_ANNUAIRE,
    chercher_media,
    collecter,
    parse_jti_directory,
)

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


class TestParsePur:
    def test_parse_directory_validite(self):
        entrees = parse_jti_directory(_read("jti_directory.html"))
        afp = chercher_media("Agence France-Presse", entrees)
        assert afp and afp["en_cours_de_validite"] is True
        expire = chercher_media("La Voix du Nord", entrees)
        assert expire and expire["en_cours_de_validite"] is False

    def test_media_absent(self):
        entrees = parse_jti_directory(_read("jti_directory.html"))
        assert chercher_media("CNEWS", entrees) is None


class TestCollecter:
    async def test_absent_verifie_cnews(self, db_session, media_cnews, run_test):
        stats = await collecter(
            db_session, media_cnews, run_test, make_fetcher(200, "jti_directory.html")
        )
        await db_session.commit()
        assert stats.inseres == 1
        signal = (await db_session.execute(select(MediaEvalSignal))).scalar_one()
        assert signal.type_signal == "certification_jti"
        assert signal.statut == StatutSignal.ABSENT_VERIFIE
        assert signal.sources_consultees == [URL_ANNUAIRE]

    async def test_bloque(self, db_session, media_cnews, run_test):
        stats = await collecter(
            db_session, media_cnews, run_test, make_fetcher(403, None)
        )
        await db_session.commit()
        assert stats.bloques == 1
        signal = (await db_session.execute(select(MediaEvalSignal))).scalar_one()
        assert signal.statut == StatutSignal.BLOQUE_ACCES
