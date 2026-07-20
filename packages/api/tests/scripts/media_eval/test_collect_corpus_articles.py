"""Tests du collecteur de corpus d'articles (collect_corpus_articles.py).

Fonctions pures (str → structures) testées sur fixtures HTML, zéro réseau :
détection d'URL d'article, rubrique, date, extraction de titre, pré-métriques
mécaniques. Plus un bout-en-bout DB avec fetcher injecté (fixtures figées).
"""

from __future__ import annotations

from datetime import date

from sqlalchemy import select

from app.models.media_eval import MediaEvalCorpusArticle, ModeAcces
from scripts.media_eval.collect_common import FetchResult
from scripts.media_eval.collect_corpus_articles import (
    collecter_corpus,
    date_depuis_html,
    date_depuis_url,
    est_url_article,
    extraire_titre,
    extraire_urls_articles,
    pre_metriques_article,
    rubrique_depuis_url,
)


class TestEstUrlArticle:
    def test_url_datee_est_article(self):
        assert est_url_article("https://cnews.fr/politique/2026-07-01/titre-123456")

    def test_id_numerique_long(self):
        assert est_url_article("https://cnews.fr/article/1234567")

    def test_page_de_service_ecartee(self):
        # Segment de service même avec un id → pas un article.
        assert not est_url_article("https://cnews.fr/tag/2026/immigration")
        assert not est_url_article("https://cnews.fr/video/2026/07/x-123456")

    def test_sans_marqueur_date_rejete(self):
        assert not est_url_article("https://cnews.fr/politique/dossier")


class TestRubriqueEtDate:
    def test_rubrique_premier_segment(self):
        assert rubrique_depuis_url("https://cnews.fr/politique/2026/07/x") == "politique"

    def test_rubrique_saute_annee(self):
        # /2026/... → prendre le segment parlant suivant.
        assert (
            rubrique_depuis_url("https://cnews.fr/2026/07/01/international-x")
            == "international-x"
        )

    def test_date_depuis_url_complete(self):
        assert date_depuis_url("https://cnews.fr/a/2026/07/01/x") == date(2026, 7, 1)

    def test_date_depuis_url_tirets(self):
        # Pattern CNEWS : /AAAA-MM-JJ/.
        assert (
            date_depuis_url("https://cnews.fr/france/2026-07-18/x-123456")
            == date(2026, 7, 18)
        )

    def test_date_depuis_url_annee_seule(self):
        assert date_depuis_url("https://cnews.fr/a/2026/x-123456") == date(2026, 1, 1)

    def test_date_absente(self):
        assert date_depuis_url("https://cnews.fr/a/x-123456") is None


class TestExtractionHtml:
    def test_titre_h1_prioritaire(self):
        html = "<html><head><title>Titre onglet</title></head><body><h1>Le vrai titre</h1></body></html>"
        assert extraire_titre(html) == "Le vrai titre"

    def test_titre_repli_title(self):
        assert extraire_titre("<html><head><title>Onglet</title></head></html>") == "Onglet"

    def test_date_html_meta(self):
        html = '<meta property="article:published_time" content="2026-05-04T10:00:00Z">'
        assert date_depuis_html(html) == date(2026, 5, 4)

    def test_date_html_time(self):
        assert date_depuis_html('<time datetime="2026-05-04">4 mai</time>') == date(2026, 5, 4)


class TestPreMetriques:
    def test_signature_et_label_opinion(self):
        html = (
            '<article><meta name="author" content="Jean Dupont">'
            '<a href="https://ext.com/source">source</a>'
            "<p>corps</p></article>"
        )
        m = pre_metriques_article(
            "https://cnews.fr/tribune/2026/07/x-123456", html, "corps de l'article"
        )
        assert m["a_signature_html"] is True
        assert m["label_opinion"] == "tribune"
        assert m["liens_sortants"] == 1
        assert m["longueur_texte"] == len("corps de l'article")

    def test_liens_sortants_ignore_liens_internes_absolus(self):
        # Un lien interne absolu (même domaine, www. toléré) n'est pas « sortant ».
        html = (
            "<article>"
            '<a href="https://www.cnews.fr/france/2026-07-01/autre-111111">interne</a>'
            '<a href="https://ext.com/source">externe</a>'
            "<p>corps</p></article>"
        )
        m = pre_metriques_article(
            "https://cnews.fr/actu/2026/07/x-123456", html, "corps"
        )
        assert m["liens_sortants"] == 1

    def test_mention_redaction_sans_label(self):
        html = "<article><p>texte</p></article>"
        m = pre_metriques_article(
            "https://cnews.fr/actu/2026/07/x-123456",
            html,
            "Article rédigé par La Rédaction avec AFP.",
        )
        assert m["mention_redaction_ou_agence"] is True
        assert m["label_opinion"] is None


class TestExtraireUrlsArticles:
    def test_home_puis_sitemap_dedup(self):
        base = "https://cnews.fr"
        home = (
            "<html><body>"
            '<a href="/politique/2026/07/a-111111">A</a>'
            '<a href="/tag/immigration">tag</a>'
            '<a href="https://autre.fr/2026/07/x-999999">externe</a>'
            "</body></html>"
        )
        sitemap = [
            "https://cnews.fr/politique/2026/07/a-111111",  # doublon home
            "https://cnews.fr/eco/2026/07/b-222222",
        ]
        urls = extraire_urls_articles(base, home, sitemap)
        assert urls == [
            "https://cnews.fr/politique/2026/07/a-111111",
            "https://cnews.fr/eco/2026/07/b-222222",
        ]

    def test_www_tolere_et_sitemap_filtre_domaine(self):
        # Site canonique www. : les liens absolus www.cnews.fr sont retenus
        # (media.domaine en DB est sans www) ; une URL étrangère du sitemap est
        # écartée par le même filtre domaine que la home.
        base = "https://cnews.fr"
        home = (
            "<html><body>"
            '<a href="https://www.cnews.fr/france/2026-07-18/a-111111">A</a>'
            "</body></html>"
        )
        sitemap = ["https://autre.fr/2026/07/x-999999"]
        assert extraire_urls_articles(base, home, sitemap) == [
            "https://www.cnews.fr/france/2026-07-18/a-111111",
        ]


# --------------------------------------------------------------------------- #
# Bout-en-bout DB — fetcher injecté (aucun réseau).
# --------------------------------------------------------------------------- #
def _article_html(titre: str) -> str:
    return (
        f"<html><head><title>{titre}</title></head><body><main>"
        f"<h1>{titre}</h1><p>{'contenu ' * 60}</p>"
        '<a href="https://source.example/x">src</a></main></body></html>'
    )


class TestCollecterCorpusDB:
    async def test_snapshot_et_dedup(self, db_session, media_cnews, run_test):
        pages = {
            "https://cnews.fr/": (
                "<html><body>"
                '<a href="/politique/2026/07/a-111111">A</a>'
                '<a href="/eco/2026/07/b-222222">B</a>'
                "</body></html>"
            ),
            "https://cnews.fr/sitemap.xml": "",  # pas de sitemap
            "https://cnews.fr/politique/2026/07/a-111111": _article_html("Titre A"),
            "https://cnews.fr/eco/2026/07/b-222222": _article_html("Titre B"),
        }

        async def fake_fetch(url: str) -> FetchResult:
            if url == "https://cnews.fr/sitemap.xml":
                return FetchResult(url, 404, "", ModeAcces.LIBRE, "HTTP 404")
            return FetchResult(url, 200, pages.get(url, ""), ModeAcces.LIBRE)

        stats = await collecter_corpus(
            db_session, media_cnews, run_test, fake_fetch, max_articles=40
        )
        assert stats.inseres == 2
        await db_session.commit()

        # Ré-exécution : idempotence (déjà présents → doublons, pas de ré-insert).
        stats2 = await collecter_corpus(
            db_session, media_cnews, run_test, fake_fetch, max_articles=40
        )
        assert stats2.inseres == 0
        assert stats2.doublons == 2

        rows = (
            await db_session.execute(
                select(MediaEvalCorpusArticle).where(
                    MediaEvalCorpusArticle.media_id == media_cnews.id
                )
            )
        ).scalars().all()
        assert {a.rubrique for a in rows} == {"politique", "eco"}
        assert all(a.texte and a.pre_metriques is not None for a in rows)

    async def test_home_bloquee_corpus_vide(self, db_session, media_cnews, run_test):
        async def fake_fetch(url: str) -> FetchResult:
            return FetchResult(url, 403, "", ModeAcces.BLOQUE, "HTTP 403")

        stats = await collecter_corpus(
            db_session, media_cnews, run_test, fake_fetch, max_articles=40
        )
        assert stats.inseres == 0
