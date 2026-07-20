"""Tests du collecteur Pappers (collect_pappers.py).

Couvre : parse v2 ; garde ``verifier_entreprise`` (match vs mismatch →
CollecteError) ; 3 signaux present via Pappers ; **repli gratuit** sur
recherche-entreprises.api.gouv.fr quand le token est absent OU épuisé (401) →
1 present + 2 partiel ; tout inaccessible → 3 bloque_acces (exit 0).
"""

from __future__ import annotations

from pathlib import Path

import pytest
from sqlalchemy import func, select

from app.models.media_eval import MediaEvalSignal, ModeAcces, StatutSignal
from scripts.media_eval.collect_common import CollecteError, FetchResult
from scripts.media_eval.collect_pappers import (
    collecter,
    parse_pappers,
    parse_recherche_entreprises,
    recherche_entreprises_url,
    verifier_entreprise,
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


def make_url_fetcher(mapping: dict[str, tuple[int, str]]):
    """Fetcher qui route par fragment d'URL (pappers vs recherche-entreprises)."""

    async def _fetch(url: str) -> FetchResult:
        for frag, (status, texte) in mapping.items():
            if frag in url:
                if status in (401, 403):
                    return FetchResult(
                        url, status, "", ModeAcces.BLOQUE, f"HTTP {status}"
                    )
                return FetchResult(url, status, texte, ModeAcces.LIBRE, None)
        return FetchResult(url, 404, "", ModeAcces.LIBRE, "HTTP 404")

    return _fetch


async def _count_statut(db_session, statut) -> int:
    return (
        await db_session.execute(
            select(func.count())
            .select_from(MediaEvalSignal)
            .where(MediaEvalSignal.statut == statut)
        )
    ).scalar()


class TestPur:
    def test_parse_pappers(self):
        info = parse_pappers(_read("pappers_sesi.json"))
        assert info["siren"] == "501260034"
        assert info["beneficiaires_effectifs"][0]["nom"] == "Vivendi SE"

    def test_verifier_entreprise_ok(self):
        import json

        verifier_entreprise(
            json.loads(_read("pappers_sesi.json")),
            "SOCIETE D'EXPLOITATION D'UN SERVICE D'INFORMATION",
        )  # ne lève pas

    def test_verifier_entreprise_mismatch(self):
        import json

        with pytest.raises(CollecteError, match="raison sociale"):
            verifier_entreprise(
                json.loads(_read("pappers_mismatch.json")),
                "SOCIETE D'EXPLOITATION D'UN SERVICE D'INFORMATION",
            )

    def test_recherche_entreprises_url_encode(self):
        url = recherche_entreprises_url("412916215")
        assert "recherche-entreprises.api.gouv.fr" in url
        assert "412916215" in url

    def test_parse_recherche_entreprises(self):
        info = parse_recherche_entreprises(
            _read("recherche_entreprises_sesi.json"), "412916215"
        )
        assert info is not None
        assert info["nom"] == "SESI"
        assert info["siren"] == "412916215"
        assert info["dirigeants"][0]["qualite"] == "Gerant"
        # SIREN non présent → None (aucun signal posé).
        assert (
            parse_recherche_entreprises(
                _read("recherche_entreprises_sesi.json"), "000000000"
            )
            is None
        )


class TestCollecter:
    async def test_pappers_trois_signaux_present(
        self, db_session, media_cnews, run_test, monkeypatch
    ):
        monkeypatch.setenv("PAPPERS_API_TOKEN", "tok-test")
        stats = await collecter(
            db_session,
            media_cnews,
            run_test,
            make_url_fetcher({"api.pappers.fr": (200, _read("pappers_sesi_snc.json"))}),
        )
        await db_session.commit()
        assert stats.inseres == 3
        assert await _count_statut(db_session, StatutSignal.PRESENT) == 3

    async def test_token_absent_repli_gratuit(
        self, db_session, media_cnews, run_test, monkeypatch
    ):
        """Sans token → API gratuite : 1 present + 2 partiel (au lieu de bloqué)."""
        monkeypatch.delenv("PAPPERS_API_TOKEN", raising=False)
        stats = await collecter(
            db_session,
            media_cnews,
            run_test,
            make_url_fetcher(
                {
                    "recherche-entreprises": (
                        200,
                        _read("recherche_entreprises_sesi.json"),
                    )
                }
            ),
        )
        await db_session.commit()
        assert stats.inseres == 3
        assert await _count_statut(db_session, StatutSignal.PRESENT) == 1
        assert await _count_statut(db_session, StatutSignal.PARTIEL) == 2
        assert await _count_statut(db_session, StatutSignal.BLOQUE_ACCES) == 0

    async def test_token_epuise_401_repli_gratuit(
        self, db_session, media_cnews, run_test, monkeypatch
    ):
        """Token présent mais 401 (crédit épuisé) → repli gratuit, pas bloqué."""
        monkeypatch.setenv("PAPPERS_API_TOKEN", "tok-vide")
        await collecter(
            db_session,
            media_cnews,
            run_test,
            make_url_fetcher(
                {
                    "api.pappers.fr": (401, ""),
                    "recherche-entreprises": (
                        200,
                        _read("recherche_entreprises_sesi.json"),
                    ),
                }
            ),
        )
        await db_session.commit()
        assert await _count_statut(db_session, StatutSignal.PRESENT) == 1
        assert await _count_statut(db_session, StatutSignal.PARTIEL) == 2

    async def test_tout_inaccessible_trois_bloque(
        self, db_session, media_cnews, run_test, monkeypatch
    ):
        """Ni token ni API gratuite exploitable → 3 bloque_acces (exit 0)."""
        monkeypatch.delenv("PAPPERS_API_TOKEN", raising=False)
        stats = await collecter(
            db_session,
            media_cnews,
            run_test,
            make_url_fetcher({"recherche-entreprises": (200, "<html>captcha</html>")}),
        )
        await db_session.commit()
        assert stats.bloques == 3
        assert await _count_statut(db_session, StatutSignal.BLOQUE_ACCES) == 3

    async def test_mismatch_leve(self, db_session, media_cnews, run_test, monkeypatch):
        monkeypatch.setenv("PAPPERS_API_TOKEN", "tok-test")
        with pytest.raises(CollecteError, match="raison sociale"):
            await collecter(
                db_session,
                media_cnews,
                run_test,
                make_url_fetcher(
                    {"api.pappers.fr": (200, _read("pappers_mismatch.json"))}
                ),
            )
