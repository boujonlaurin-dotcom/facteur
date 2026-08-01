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
    build_editorial_pool_stmt,
    clustering_window_hours,
    clustering_window_ladder,
    drop_unclusterable,
    fetch_editorial_pool,
    finalize_pool,
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

        result = await fetch_editorial_pool(session, "pour_vous")

        assert len(result) == 2400
        assert session.execute.await_count == 1

    @pytest.mark.asyncio
    async def test_thin_pool_refetches_on_fallback_window(self):
        session = _session([_content("a")] * 10, [_content("b")] * 300)

        result = await fetch_editorial_pool(session, "pour_vous")

        assert len(result) == 300
        assert session.execute.await_count == 2

    @pytest.mark.asyncio
    async def test_floor_is_measured_after_filtering(self):
        """Le plancher porte sur ce qui ira au clustering, pas sur le brut.

        250 lignes dont 250 bulletins, c'est un pool vide : il faut descendre
        l'échelle, pas s'arrêter en croyant le plancher atteint.
        """
        bulletins = [_content("JOURNAL DE 8H du jeudi 30 juillet 2026")] * 250
        real = [_content(f"Sujet {i}") for i in range(300)]
        session = _session(bulletins, real)

        result = await fetch_editorial_pool(session, "pour_vous")

        assert len(result) == 300
        assert session.execute.await_count == 2

    @pytest.mark.asyncio
    async def test_query_is_capped_for_memory_safety_not_for_selection(self):
        """La borne doit valoir MAX_ARTICLES, pas un top-N déguisé.

        Assertion sur la valeur réellement liée à la requête : une version qui
        se contentait de chercher la constante dans le SQL après l'y avoir
        substituée elle-même passait avec un `.limit(200)` réintroduit.
        """
        session = _session([_content("a")] * 250)

        await fetch_editorial_pool(session, "pour_vous")

        params = session.execute.await_args_list[0].args[0].compile().params
        limits = [v for k, v in params.items() if k.startswith("param")]
        assert limits == [EDITORIAL_CLUSTERING_MAX_ARTICLES]
        assert EDITORIAL_CLUSTERING_MAX_ARTICLES > 10 * EDITORIAL_CLUSTERING_MIN_POOL

    @pytest.mark.asyncio
    async def test_windows_come_from_the_module_not_the_caller(self):
        """L'échelle appartient au module, pas à l'appelant.

        Elle a d'abord été câblée sur le `hours_lookback` de chaque appelant :
        48 h côté batch, **168 h** côté on-demand (`select_for_user`). Les deux
        chemins se seraient élargis différemment dans le seul cas dégradé où ce
        module existe pour garantir qu'ils voient le même corpus.
        """
        now = datetime.datetime(2026, 7, 31, 5, 0, tzinfo=datetime.UTC)
        session = _session(*([[_content("a")] * 5] * len(clustering_window_ladder())))

        await fetch_editorial_pool(session, "pour_vous", now=now)

        cutoffs = [
            call.args[0].compile().params["published_at_1"]
            for call in session.execute.await_args_list
        ]
        assert [round((now - c).total_seconds() / 3600) for c in cutoffs] == list(
            clustering_window_ladder()
        )

    @pytest.mark.asyncio
    async def test_sparse_mode_walks_down_to_the_widest_window(self):
        """« Bonnes Nouvelles » n'a jamais 200 articles — mesuré : 13/24 h, 33/48 h, 145/168 h.

        S'arrêter au deuxième barreau amputerait le mode de 77 % de sa matière.
        L'échelle doit descendre jusqu'au bout plutôt que de rendre un pool
        maigre, ce qui restitue son comportement historique (fenêtre 168 h).
        """
        session = _session(
            [_content("a")] * 13, [_content("b")] * 33, [_content("c")] * 145
        )

        result = await fetch_editorial_pool(session, "serein")

        assert len(result) == 145
        assert session.execute.await_count == len(clustering_window_ladder())


class TestOnDemandCallerUsesTheSharedPolicy:
    """`digest_selector._fetch_editorial_global_pool` — chemin on-demand.

    Il n'avait aucun test à son niveau, alors que c'est lui qui sert un
    utilisateur en cache miss et que c'est lui qui avait divergé du batch
    (pas de filtre pub, fenêtre pilotée par le `hours_lookback` de l'appelant).
    """

    @pytest.mark.asyncio
    async def test_applies_window_ad_filter_and_bulletin_drop(self):
        from app.services.digest_selector import DigestSelector

        keep = _content("Trêve à Gaza : accord sur le désarmement du Hamas")
        rows = [keep, _content("JOURNAL DE 8H du jeudi 30 juillet 2026")]

        selector = DigestSelector(_session(rows, rows, rows))
        pool = await selector._fetch_editorial_global_pool(mode="pour_vous")

        assert [c.id for c in pool] == [keep.id]
        where = _compiled(selector.session.execute.await_args_list[0].args[0]).split(
            " where ", 1
        )[1]
        assert "contents.is_ad = false" in where
        assert "contents.published_at <=" in where


class TestFinalizePool:
    def test_filters_once_and_reports_what_it_dropped(self):
        keep = _content("Trêve à Gaza : accord sur le désarmement du Hamas")
        drop = _content("JOURNAL DE 8H du jeudi 30 juillet 2026")

        assert finalize_pool([keep, drop], "pour_vous", "test_event") == [keep]


class TestWindows:
    def test_window_is_daily(self):
        """« Actus du jour » est un produit quotidien : un sujet se définit dans la journée.

        Une fenêtre plus large laisse les articles de la veille se raccrocher à
        ceux du jour (observé sur les bulletins radio, clusters à cheval sur 3 jours).
        """
        assert clustering_window_hours() == 24

    def test_ladder_is_ascending(self):
        """Sinon « ré-élargir » rétrécirait le pool. Trié à la lecture du YAML."""
        ladder = clustering_window_ladder()
        assert list(ladder) == sorted(ladder)
        assert ladder[0] == clustering_window_hours()

    def test_former_cap_is_now_a_floor(self):
        """Le 200 historique plafonnait le pool ; il ne sert plus qu'à détecter un pool maigre."""
        assert EDITORIAL_CLUSTERING_MIN_POOL == 200
        assert EDITORIAL_CLUSTERING_MAX_ARTICLES > 10 * EDITORIAL_CLUSTERING_MIN_POOL
