"""Tests du collecteur pages types (collect_pages_types.py).

Zéro réseau : un ``fetcher`` fixture-driven lit des HTML/XML figés. Couvre :
découverte footer+sitemap → détection présente ; épuisement → absent_verifie
avec sources_consultees ; soft-404 et DOM cassé non significatifs (jamais
d'exception) ; home bloquée → bloque_acces par signal ; idempotence.
"""

from __future__ import annotations

from pathlib import Path

from sqlalchemy import func, select

from app.models.media_eval import (
    MediaEvalSignal,
    MediaEvalSnapshot,
    ModeAcces,
    StatutSignal,
    TypePage,
)
from scripts.media_eval.collect_common import FetchResult
from scripts.media_eval.collect_pages_types import (
    a_marqueurs_type,
    classifier_url,
    collecter,
    extraire_texte_principal,
    page_significative,
    parse_liens_footer,
    parse_sitemap,
    ratio_liens_articles,
    ressemble_a_home,
)

HTML = Path(__file__).resolve().parents[1] / "fixtures" / "media_eval" / "html"
FOUND = "page_significative.html"


def _read(name: str) -> str:
    return (HTML / name).read_text()


def _extraire(html: str) -> str:
    return extraire_texte_principal(html)


def make_fetcher(mapping: dict[str, tuple[int, str | None]]):
    """Fetcher fixture-driven ; défaut = 404 dur (page absente)."""

    async def _fetch(url: str) -> FetchResult:
        status, name = mapping.get(url, (404, None))
        text = _read(name) if name else ""
        if status == 403:
            return FetchResult(url, 403, "", ModeAcces.BLOQUE, "HTTP 403")
        mode = ModeAcces.LIBRE
        err = None if status == 200 else f"HTTP {status}"
        return FetchResult(url, status, text, mode, err)

    return _fetch


def _reporterre_mapping() -> dict[str, tuple[int, str | None]]:
    base = "https://reporterre.net"
    return {
        f"{base}/": (200, "reporterre_home.html"),
        f"{base}/sitemap.xml": (200, "reporterre_sitemap.xml"),
        # Chaque page porte les marqueurs lexicaux de son type (substance).
        f"{base}/mentions-legales": (200, "mentions_legales_ok.html"),
        f"{base}/spip.php?page=charte": (200, "charte_ok.html"),
        f"{base}/nous-soutenir": (200, "dons_ok.html"),
        f"{base}/spip.php?rubrique=qui-sommes-nous": (200, FOUND),
        # soft-404 (200 mais contenu « page introuvable ») et DOM cassé :
        f"{base}/manifeste": (200, "page_404_soft.html"),
        f"{base}/publicite": (200, "dom_casse.html"),
    }


def _cnews_mapping() -> dict[str, tuple[int, str | None]]:
    """Reproduit le piège cnews.fr : soft-404 (home servie) + flux taggés."""
    base = "https://cnews.fr"
    return {
        f"{base}/": (200, "cnews_home_riche.html"),
        f"{base}/sitemap.xml": (404, None),
        f"{base}/mentions-legales": (200, "cnews_mentions_legales.html"),
        # /charte et /ligne-editoriale renvoient la home → soft-404 silencieux.
        f"{base}/charte": (200, "cnews_home_riche.html"),
        f"{base}/ligne-editoriale": (200, "cnews_home_riche.html"),
        # /dons et /publicite sont des fils d'articles taggés, pas institutionnels.
        f"{base}/dons": (200, "cnews_flux_dons.html"),
        f"{base}/publicite": (200, "cnews_flux_publicite.html"),
    }


async def _count(db_session, model) -> int:
    return (await db_session.execute(select(func.count()).select_from(model))).scalar()


async def _statuts(db_session) -> dict[str, int]:
    rows = await db_session.execute(
        select(MediaEvalSignal.statut, func.count()).group_by(MediaEvalSignal.statut)
    )
    return {(s.value if hasattr(s, "value") else s): n for s, n in rows.all()}


class TestParsePur:
    def test_parse_liens_footer_ignore_mailto_ancre(self):
        liens = parse_liens_footer(_read("reporterre_home.html"))
        hrefs = [h for h, _ in liens]
        assert "/mentions-legales" in hrefs
        assert not any(h.startswith(("mailto:", "#")) for h in hrefs)

    def test_parse_sitemap(self):
        urls = parse_sitemap(_read("reporterre_sitemap.xml"))
        assert "https://reporterre.net/mentions-legales" in urls
        assert len(urls) == 7

    def test_classifier_url(self):
        assert classifier_url("/mentions-legales") == TypePage.MENTIONS_LEGALES
        assert classifier_url("/spip.php?page=charte") == TypePage.CHARTE
        assert classifier_url("/nous-soutenir") == TypePage.DONS_FINANCEMENT
        assert classifier_url("/article/quelconque") is None

    def test_page_significative(self):
        assert page_significative(_read(FOUND), 200) is True
        assert page_significative(_read("page_404_soft.html"), 200) is False
        assert page_significative(_read("dom_casse.html"), 200) is False
        assert page_significative(_read(FOUND), 404) is False

    def test_page_significative_soft_404_comme_home(self):
        """Une page qui renvoie la home (même texte principal) est écartée."""
        home = _read("cnews_home_riche.html")
        assert page_significative(home, 200, home_texte="") is True  # sans réf
        assert (
            page_significative(
                home,
                200,
                type_page=TypePage.CHARTE,
                home_texte=_extraire(home),
            )
            is False
        )

    def test_page_significative_marqueurs_type(self):
        """Sans marqueur lexical du type, la page n'est pas significative."""
        # Le flux « /publicite » porte le mot « régie » mais reste un fil
        # d'articles datés → écarté par la pénalité anti-flux.
        assert (
            page_significative(
                _read("cnews_flux_publicite.html"), 200, type_page=TypePage.REGIE_PUB
            )
            is False
        )
        # La vraie page de mentions porte capital / RCS / SIREN → retenue.
        assert (
            page_significative(
                _read("cnews_mentions_legales.html"),
                200,
                type_page=TypePage.MENTIONS_LEGALES,
            )
            is True
        )

    def test_ressemble_a_home(self):
        home = _extraire(_read("cnews_home_riche.html"))
        assert ressemble_a_home(_extraire(_read("cnews_home_riche.html")), home) is True
        assert (
            ressemble_a_home(_extraire(_read("mentions_legales_ok.html")), home)
            is False
        )
        assert ressemble_a_home("texte", None) is False

    def test_ratio_liens_articles(self):
        assert ratio_liens_articles(_read("cnews_flux_dons.html")) > 0.5
        assert ratio_liens_articles(_read("mentions_legales_ok.html")) <= 0.5

    def test_a_marqueurs_type_flux_penalise(self):
        # Marqueur « faire un don » présent, mais fil d'articles datés → écarté.
        html = _read("cnews_flux_dons.html")
        texte = _extraire(html)
        assert "faire un don" in texte.lower()
        assert a_marqueurs_type(texte, html, TypePage.DONS_FINANCEMENT) is False
        # Une vraie page de dons (peu de liens) est retenue.
        dons = _read("dons_ok.html")
        assert (
            a_marqueurs_type(_extraire(dons), dons, TypePage.DONS_FINANCEMENT) is True
        )


class TestCollecterNominal:
    async def test_detection_et_absence(self, db_session, media_reporterre, run_test):
        stats = await collecter(
            db_session, media_reporterre, run_test, make_fetcher(_reporterre_mapping())
        )
        await db_session.commit()
        # 3 present (mentions, charte, dons) + 2 absent (ligne édito, régie).
        assert stats.inseres == 5
        statuts = await _statuts(db_session)
        assert statuts.get("present") == 3
        assert statuts.get("absent_verifie") == 2

        # Les absents portent la preuve de recherche.
        absents = (
            (
                await db_session.execute(
                    select(MediaEvalSignal).where(
                        MediaEvalSignal.statut == StatutSignal.ABSENT_VERIFIE
                    )
                )
            )
            .scalars()
            .all()
        )
        assert all(a.sources_consultees for a in absents)

    async def test_snapshots_dedupes(self, db_session, media_reporterre, run_test):
        await collecter(
            db_session, media_reporterre, run_test, make_fetcher(_reporterre_mapping())
        )
        await db_session.commit()
        # home + mentions + charte + dons + a_propos = 5 (ours absent).
        assert await _count(db_session, MediaEvalSnapshot) == 5


class TestBloqueEtRobustesse:
    async def test_home_bloquee_bloque_acces(
        self, db_session, media_reporterre, run_test
    ):
        mapping = {"https://reporterre.net/": (403, None)}
        stats = await collecter(
            db_session, media_reporterre, run_test, make_fetcher(mapping)
        )
        await db_session.commit()
        # 1 bloque_acces par signal attendu (5), aucune exception.
        assert stats.bloques == 5
        statuts = await _statuts(db_session)
        assert statuts.get("bloque_acces") == 5

    async def test_idempotence(self, db_session, media_reporterre, run_test):
        fetcher = make_fetcher(_reporterre_mapping())
        await collecter(db_session, media_reporterre, run_test, fetcher)
        await db_session.commit()
        n1 = await _count(db_session, MediaEvalSignal)
        stats2 = await collecter(db_session, media_reporterre, run_test, fetcher)
        await db_session.commit()
        assert stats2.inseres == 0 and stats2.snapshots == 0
        assert await _count(db_session, MediaEvalSignal) == n1


class TestCnewsSoftFourCentEtFlux:
    """Non-régression du diagnostic cnews.fr (hand-off pilote-2026-07b).

    /charte + /ligne-editoriale renvoient la home (soft-404) et /dons +
    /publicite sont des fils d'articles taggés : aucun ne doit produire un
    ``present`` — seule la vraie page de mentions légales est retenue.
    """

    async def _signaux(self, db_session):
        rows = await db_session.execute(
            select(
                MediaEvalSignal.critere,
                MediaEvalSignal.type_signal,
                MediaEvalSignal.statut,
            )
        )
        return {
            (c, t): (s.value if hasattr(s, "value") else s) for c, t, s in rows.all()
        }

    async def test_aucun_present_hors_mentions(self, db_session, media_cnews, run_test):
        stats = await collecter(
            db_session, media_cnews, run_test, make_fetcher(_cnews_mapping())
        )
        await db_session.commit()
        statuts = await _statuts(db_session)
        # Seule la page de mentions est réelle : 1 present, 4 absent_verifie.
        assert statuts.get("present") == 1
        assert statuts.get("absent_verifie") == 4
        assert statuts.get("bloque_acces") is None
        assert stats.snapshots == 2  # home + mentions légales uniquement

        sig = await self._signaux(db_session)
        # Les faux positifs du run initial sont désormais des absences vérifiées.
        assert sig[("C8", "charte_deontologique")] == "absent_verifie"
        assert sig[("C11", "ligne_editoriale_publiee")] == "absent_verifie"
        assert sig[("C7", "regie_pub_identifiee")] == "absent_verifie"
        assert sig[("C5", "transparence_financement")] == "absent_verifie"
        assert sig[("C5", "mentions_legales")] == "present"
