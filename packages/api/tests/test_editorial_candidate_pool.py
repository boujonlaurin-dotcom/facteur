"""Tests de la politique du pool de clustering éditorial.

Ce module est le point unique qui décide *quels articles le regroupement
« Actus du jour » a le droit de voir*. Les deux appelants (batch et on-demand)
doivent en dépendre, sinon un même sujet n'affiche pas le même nombre de médias
selon l'origine du digest.

Cf. `docs/maintenance/maintenance-clustering-corpus-complet.md`.
"""

import datetime
from unittest.mock import AsyncMock, MagicMock, Mock
from uuid import uuid4

import pytest

from app.services.editorial.candidate_pool import (
    EDITORIAL_CLUSTERING_MAX_ARTICLES,
    EDITORIAL_CLUSTERING_MIN_POOL,
    EDITORIAL_CLUSTERING_WINDOW_HOURS,
    build_editorial_pool_stmt,
    drop_unclusterable,
    fetch_editorial_pool,
)


def _compiled(stmt) -> str:
    """SQL compilé, sur une seule ligne — le compilateur insère des sauts de ligne
    avant FROM/WHERE, qui casseraient une recherche de sous-chaîne."""
    sql = str(stmt.compile(compile_kwargs={"literal_binds": False})).lower()
    return " ".join(sql.split())


def _content(title):
    return Mock(id=uuid4(), source_id=uuid4(), title=title)


class TestPoolStatement:
    def test_window_is_bounded_on_both_sides(self):
        """La borne haute écarte les articles post-datés.

        19 articles portaient une date RSS future ; le pool étant trié par
        récence décroissante, ils remontaient systématiquement en tête.
        """
        now = datetime.datetime.now(datetime.UTC)
        stmt = build_editorial_pool_stmt(
            "pour_vous", now - datetime.timedelta(hours=24), now
        )
        sql = _compiled(stmt)
        assert "contents.published_at >=" in sql
        assert "contents.published_at <=" in sql

    def test_pour_vous_filters_ads(self):
        """`pour_vous` ne passe pas par le filtre bonne-nouvelle : filtre pub explicite.

        Sans lui, les articles `is_ad=True` entraient dans le clustering du chemin
        on-demand, qui ne l'appliquait pas — divergence avec le chemin batch.
        """
        now = datetime.datetime.now(datetime.UTC)
        # `is_good_news` figure dans la liste des colonnes du SELECT : c'est la
        # clause WHERE qu'il faut inspecter, pas la requête entière.
        where = _compiled(
            build_editorial_pool_stmt(
                "pour_vous", now - datetime.timedelta(hours=24), now
            )
        ).split(" where ", 1)[1]
        assert "contents.is_ad = false" in where
        assert "is_good_news" not in where

    def test_serein_filters_good_news(self):
        now = datetime.datetime.now(datetime.UTC)
        sql = _compiled(
            build_editorial_pool_stmt("serein", now - datetime.timedelta(hours=24), now)
        )
        assert "contents.is_good_news = true" in sql

    def test_statement_carries_no_limit(self):
        """La borne appartient à l'appelant : le module ne plafonne pas en douce."""
        now = datetime.datetime.now(datetime.UTC)
        sql = _compiled(
            build_editorial_pool_stmt(
                "pour_vous", now - datetime.timedelta(hours=24), now
            )
        )
        assert "limit" not in sql


class TestDropUnclusterable:
    def test_drops_news_bulletins(self):
        """Un bulletin partage un gabarit, pas un sujet.

        `pipeline._is_non_actu_cluster` existait déjà mais exige que *tous* les
        contenus du cluster soient des bulletins : un seul intrus sauvait un
        cluster de 19 journaux radio. On traite ici la cause.
        """
        keep = _content("Trêve à Gaza : accord sur le désarmement du Hamas")
        dropped = [
            _content("JOURNAL DE 8H du jeudi 30 juillet 2026"),
            _content("Le journal RTL de 6h du 31 juillet 2026"),
            _content("JOURNAL DE 12H30 du jeudi 30 juillet 2026"),
            _content("Revue de presse du matin"),
        ]
        assert drop_unclusterable([keep, *dropped]) == [keep]

    def test_keeps_ordinary_titles(self):
        items = [
            _content("Incendie en Gironde : le feu est contenu dans son périmètre"),
            _content("La croissance française atteint 0,2 % au deuxième trimestre"),
        ]
        assert drop_unclusterable(items) == items

    def test_tolerates_missing_or_non_string_titles(self):
        """Filtre d'exclusion, pas garde de validation : en cas de doute on garde."""
        odd = [Mock(id=uuid4(), title=None), Mock(id=uuid4(), spec=["id"])]
        assert len(drop_unclusterable(odd)) == 2

    def test_empty_pool_stays_empty(self):
        assert drop_unclusterable([]) == []


def _session(*batches):
    """Session mock rendant une liste de rows par appel successif à execute()."""

    def _res(items):
        scalars = MagicMock()
        scalars.all = MagicMock(return_value=items)
        res = MagicMock()
        res.scalars = MagicMock(return_value=scalars)
        return res

    session = Mock()
    session.execute = AsyncMock(side_effect=[_res(b) for b in batches])
    return session


class TestFetchEditorialPool:
    """La politique (fenêtre, ré-élargissement, borne) appartient au module.

    Elle vivait en double chez les deux appelants, ce qui les avait laissés
    diverger — le chemin on-demand n'appliquait pas le filtre pub.
    """

    @pytest.mark.asyncio
    async def test_full_window_in_one_query(self):
        corpus = [_content(f"Sujet {i}") for i in range(2400)]
        session = _session(corpus)

        result = await fetch_editorial_pool(session, "pour_vous", fallback_hours=48)

        assert len(result) == 2400
        assert session.execute.await_count == 1

    @pytest.mark.asyncio
    async def test_thin_pool_refetches_on_fallback_window(self):
        session = _session([_content("a")] * 10, [_content("b")] * 300)

        result = await fetch_editorial_pool(session, "pour_vous", fallback_hours=48)

        assert len(result) == 300
        assert session.execute.await_count == 2

    @pytest.mark.asyncio
    async def test_returns_rows_unfiltered(self):
        """`drop_unclusterable` appartient à l'appelant : il unionne d'abord."""
        rows = [_content("JOURNAL DE 8H du jeudi 30 juillet 2026")] * 250
        session = _session(rows)

        result = await fetch_editorial_pool(session, "pour_vous", fallback_hours=48)

        assert len(result) == 250

    @pytest.mark.asyncio
    async def test_query_is_capped_for_memory_safety(self):
        session = _session([_content("a")] * 250)

        await fetch_editorial_pool(session, "pour_vous", fallback_hours=48)

        sql = _compiled(session.execute.await_args_list[0].args[0])
        assert f"limit {EDITORIAL_CLUSTERING_MAX_ARTICLES}" in sql.replace(
            ":param_1", str(EDITORIAL_CLUSTERING_MAX_ARTICLES)
        )


class TestConstants:
    def test_window_is_daily(self):
        """« Actus du jour » est un produit quotidien : un sujet se définit dans la journée.

        Une fenêtre plus large laisse les articles de la veille se raccrocher à
        ceux du jour (observé sur les bulletins radio, clusters à cheval sur 3 jours).
        """
        assert EDITORIAL_CLUSTERING_WINDOW_HOURS == 24

    def test_former_cap_is_now_a_floor(self):
        """Le 200 historique plafonnait le pool ; il ne sert plus qu'à détecter un pool maigre."""
        assert EDITORIAL_CLUSTERING_MIN_POOL == 200
        assert EDITORIAL_CLUSTERING_MAX_ARTICLES > 10 * EDITORIAL_CLUSTERING_MIN_POOL
