"""Tests hermétiques pour la jauge de tri (`--denominator triage`, Story 33.1).

Ni DB ni réseau : les lignes rejouent la **forme que `SQL_TRIAGE` retourne**
(une décision de tri par ligne, déjà jointe au score du digest) et on fait
tourner l'agrégation pure Python dessus.

Ce que ça garde, au-delà de l'arithmétique :

- `later` compte comme **gardé** (mettre de côté est un choix positif) ;
- le rang est celui du **slate figé** porté par la décision, jamais celui du
  digest — le slate est gelé au premier geste alors que `GET /api/essentiel`
  re-ranke à chaque requête ;
- une décision dont le score n'a pas été retrouvé tombe en bande `missing` et
  reste comptée dans le taux global (sinon on masquerait le trou).

Limite assumée, en miroir de `test_evaluate_feed_ranking.py` : `SQL_TRIAGE`
n'est pas exécuté ici. Seule sa structure est gardée.
"""

import datetime as dt

import pytest

from scripts.evaluate_feed_ranking import (
    ALL_DENOMINATOR_CHOICES,
    SQL_TRIAGE,
    TRIAGE_DENOMINATOR,
    build_triage_metrics,
    render_triage_report,
)


def _row(
    *,
    decision="keep",
    rank=1,
    theme="society",
    followed=False,
    final_score=80.0,
    pillar_scores=None,
    user="u1",
    day="2026-08-02",
    via="swipe",
    latency=1000,
    slate_size=5,
):
    return {
        "user_id": user,
        "content_id": f"c-{user}-{rank}-{day}",
        "digest_date": day,
        "decision": decision,
        "rank": rank,
        "slate_size": slate_size,
        "decided_via": via,
        "latency_ms": latency,
        "final_score": final_score,
        "pillar_scores": pillar_scores if pillar_scores is not None else {},
        "subject_label": "Sujet",
        "theme": theme,
        "topics": [],
        "entities": [],
        "is_followed_source": followed,
    }


def _keyed(rows):
    return {row["key"]: row for row in rows}


def test_taux_de_conservation_global():
    metrics = build_triage_metrics(
        rows=[
            _row(decision="keep", rank=1),
            _row(decision="pass", rank=2),
            _row(decision="pass", rank=3),
            _row(decision="pass", rank=4),
        ]
    )

    assert metrics["global"]["shown"] == 4
    assert metrics["global"]["consumed"] == 1
    assert metrics["global"]["ctr"] == pytest.approx(0.25)


def test_later_compte_comme_garde():
    """« Plus tard » est un choix positif, pas un rejet."""
    metrics = build_triage_metrics(
        rows=[_row(decision="later", rank=1), _row(decision="pass", rank=2)]
    )

    assert metrics["global"]["consumed"] == 1
    assert metrics["global"]["ctr"] == pytest.approx(0.5)


def test_par_rang_utilise_le_rang_du_slate_fige():
    metrics = build_triage_metrics(
        rows=[
            _row(decision="keep", rank=1, user="u1"),
            _row(decision="keep", rank=1, user="u2"),
            _row(decision="pass", rank=5, user="u1"),
            _row(decision="pass", rank=5, user="u2"),
        ],
        min_shown=1,
    )

    by_rank = _keyed(metrics["by_rank"])
    assert by_rank[1]["ctr"] == pytest.approx(1.0)
    assert by_rank[5]["ctr"] == pytest.approx(0.0)


def test_par_source_suivie_separe_les_deux_populations():
    """Le gradient « source suivie » est le signal le plus net mesuré à ce jour."""
    metrics = build_triage_metrics(
        rows=[
            _row(decision="keep", rank=1, followed=True),
            _row(decision="keep", rank=2, followed=True),
            _row(decision="pass", rank=3, followed=False),
            _row(decision="pass", rank=4, followed=False),
        ]
    )

    by_followed = _keyed(metrics["by_followed_source"])
    assert by_followed["suivie"]["ctr"] == pytest.approx(1.0)
    assert by_followed["non suivie"]["ctr"] == pytest.approx(0.0)


def test_decision_sans_score_tombe_en_bande_missing_mais_reste_comptee():
    """Un trou de score ne doit pas disparaître du taux global."""
    metrics = build_triage_metrics(
        rows=[
            _row(decision="keep", rank=1, final_score=None),
            _row(decision="pass", rank=2, final_score=42.0),
        ]
    )

    assert metrics["decisions_with_score"] == 1
    assert metrics["global"]["shown"] == 2
    assert "missing" in _keyed(metrics["by_score_band"])


def test_pillar_scores_absents_tombent_en_missing():
    metrics = build_triage_metrics(rows=[_row(decision="keep", rank=1)])

    for pillar_rows in metrics["by_pillar_band"].values():
        assert "missing" in _keyed(pillar_rows)


def test_latence_mediane_et_repartition_des_gestes():
    """`latency_ms` est là pour détecter le tri distrait, risque assumé de la V0."""
    metrics = build_triage_metrics(
        rows=[
            _row(decision="keep", rank=1, latency=100, via="swipe"),
            _row(decision="pass", rank=2, latency=500, via="swipe"),
            _row(decision="pass", rank=3, latency=900, via="button"),
        ]
    )

    assert metrics["median_latency_ms"] == 500
    by_via = _keyed(metrics["by_decided_via"])
    assert by_via["swipe"]["shown"] == 2
    assert by_via["button"]["shown"] == 1


def test_compte_les_users_et_les_jours():
    metrics = build_triage_metrics(
        rows=[
            _row(user="u1", day="2026-08-01", rank=1),
            _row(user="u1", day="2026-08-02", rank=1),
            _row(user="u2", day="2026-08-02", rank=1),
        ]
    )

    assert metrics["users_counted"] == 2
    assert metrics["days_counted"] == 2


def test_decisions_par_type_sont_publiees():
    metrics = build_triage_metrics(
        rows=[
            _row(decision="keep", rank=1),
            _row(decision="later", rank=2),
            _row(decision="pass", rank=3),
            _row(decision="pass", rank=4),
        ]
    )

    counts = {entry["key"]: entry["count"] for entry in metrics["decisions_by_kind"]}
    assert counts == {"keep": 1, "later": 1, "pass": 2}


def test_triage_est_un_choix_de_denominateur_mais_pas_un_denominateur_ctr():
    """Il ne doit pas polluer le tableau « les 3 dénominateurs côte à côte »."""
    from scripts.evaluate_feed_ranking import DENOMINATORS

    assert TRIAGE_DENOMINATOR in ALL_DENOMINATOR_CHOICES
    assert TRIAGE_DENOMINATOR not in DENOMINATORS


def test_sql_triage_lit_la_table_de_tri_et_le_rang_de_la_decision():
    assert "essentiel_triage_decisions" in SQL_TRIAGE
    # Le rang vient de la décision, pas du digest.
    assert "etd.rank" in SQL_TRIAGE
    assert "etd.slate_size" in SQL_TRIAGE
    # Source suivie : le gradient à confirmer.
    assert "user_sources" in SQL_TRIAGE
    # Dédup avant le join, sinon un article présent dans 2 slots dupliquerait
    # la décision et gonflerait le dénominateur.
    assert "DISTINCT ON" in SQL_TRIAGE


def test_le_rapport_est_du_markdown_non_vide():
    metrics = build_triage_metrics(
        rows=[_row(decision="keep", rank=1), _row(decision="pass", rank=2)],
        min_shown=1,
    )
    report = render_triage_report(
        metrics,
        since=dt.datetime(2026, 7, 20, tzinfo=dt.UTC),
        until=dt.datetime(2026, 8, 2, tzinfo=dt.UTC),
        tag="v0",
        row_limit_hit=False,
    )

    assert report.startswith("# Jauge de tri")
    assert "taux de conservation" in report
    assert "rang" in report
    # Le rapport doit dire ce qu'il n'est pas : un CTR.
    assert "ne mesure **pas** un CTR" in report
