"""Tests hermétiques pour `scripts/evaluate_feed_ranking.py`.

Ni DB ni réseau : le toy `toy_feed_ranking_rows.json` rejoue la **forme des
lignes que la requête SQL retourne** (un slot livré par ligne, déjà aplati), et
on fait tourner l'agrégation pure Python dessus.

Couvre :
- les **3 dénominateurs**, dont le cas limite leave-one-out (un digest à un seul
  article consommé ne contribue rien : l'article se conditionnerait lui-même) ;
- `editorial_v3` : slots `actu` **et** `extra`, rang de sujet, libellé de sujet ;
- `pillar_scores` absent ⇒ bande `missing` (les extras, jamais scorés, et tout
  l'historique antérieur à la persistance forward-only) ;
- `flat_v1` / `topics_v1` parsent toujours (pas de régression legacy) ;
- l'histogramme `format_version`, garde-fou contre un futur changement de format
  qui rendrait la jauge muette en silence — le défaut d'origine ;
- `render_report` / `render_compare` produisent du markdown non vide.

Limite assumée : la requête SQL elle-même n'est pas exécutée ici (elle exige la
prod). Elle a été validée contre la DB de prod à l'écriture de la PR ; le test
`test_sql_reads_the_three_formats` ne garde que sa **structure**, pas son
résultat.
"""

import datetime as dt
import json
from pathlib import Path

import pytest

from scripts.evaluate_feed_ranking import (
    DENOMINATORS,
    SQL,
    build_metrics,
    consumed_counts_by_digest,
    is_counted,
    render_compare,
    render_report,
)

FIXTURE = Path(__file__).parent / "fixtures" / "toy_feed_ranking_rows.json"


def _rows() -> list[dict]:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def _metrics(denominator: str = "engaged-loo", **kwargs) -> dict:
    return build_metrics(
        rows=_rows(), denominator=denominator, min_shown=1, top=25, **kwargs
    )


def _keyed(rows: list[dict]) -> dict:
    return {row["key"]: row for row in rows}


# ---------------------------------------------------------------------------
# Dénominateurs
# ---------------------------------------------------------------------------


def test_consumed_counts_by_digest():
    """Seuls les digests ayant au moins un consommé apparaissent."""
    assert consumed_counts_by_digest(_rows()) == {"D1": 2, "D2": 1, "D4": 1}


def test_denominator_all_counts_every_delivered_slot():
    metrics = _metrics("all")
    assert metrics["global"]["shown"] == 11
    assert metrics["global"]["consumed"] == 4
    assert metrics["rows_skipped"] == 0


def test_denominator_engaged_drops_digests_without_any_consumption():
    """D3 (aucun consommé) et D5 sortent ; D1+D2+D4 restent entiers."""
    metrics = _metrics("engaged")
    assert metrics["global"]["shown"] == 8
    assert metrics["global"]["consumed"] == 4


def test_denominator_loo_excludes_the_lone_consumed_article():
    """Cas limite : dans D2 et D4 le seul consommé est son propre conditionneur.

    Il est donc retiré du dénominateur — c'est exactement ce que le
    leave-one-out dé-circularise. Restent D1 (4 slots, 2 consommés) + D2 (1
    slot, 0) + D4 (1 slot, 0).
    """
    metrics = _metrics("engaged-loo")
    assert metrics["global"]["shown"] == 6
    assert metrics["global"]["consumed"] == 2
    assert metrics["rows_skipped"] == 5


def test_loo_edge_case_single_consumed_digest_contributes_nothing_consumed():
    rows = [
        {"digest_id": "X", "status": "consumed"},
        {"digest_id": "X", "status": None},
    ]
    counts = consumed_counts_by_digest(rows)
    assert (
        is_counted(rows[0], denominator="engaged-loo", consumed_by_digest=counts)
        is False
    )
    assert (
        is_counted(rows[1], denominator="engaged-loo", consumed_by_digest=counts)
        is True
    )


def test_the_three_denominators_are_always_published_side_by_side():
    """Publier le seul dénominateur retenu masquerait la dilution mesurée."""
    metrics = _metrics("engaged-loo")
    assert set(metrics["denominators"]) == set(DENOMINATORS)
    assert metrics["denominators"]["all"]["shown"] == 11
    assert metrics["denominators"]["engaged"]["shown"] == 8
    assert metrics["denominators"]["engaged-loo"]["shown"] == 6
    # Invariants de construction : `engaged` ne retire que des non-consommés
    # (donc gonfle le CTR) et le LOO ne retire ensuite que des consommés (donc
    # le redescend). C'est cet encadrement qui rend la dilution lisible ; en
    # prod l'écart `all` -> `engaged` est d'un facteur ~15.
    assert (
        metrics["denominators"]["all"]["ctr"]
        <= metrics["denominators"]["engaged"]["ctr"]
    )
    assert (
        metrics["denominators"]["engaged-loo"]["ctr"]
        <= metrics["denominators"]["engaged"]["ctr"]
    )


def test_unknown_denominator_is_rejected():
    with pytest.raises(ValueError):
        build_metrics(rows=_rows(), denominator="engaged-somehow")


# ---------------------------------------------------------------------------
# editorial_v3 : rang de sujet, slot, libellé
# ---------------------------------------------------------------------------


def test_by_subject_rank_uses_the_subject_rank():
    metrics = _metrics("all")
    ranks = _keyed(metrics["by_subject_rank"])
    # D1(r1) + D2(r1) + D3(r1) + D5(r1) — les lignes flat_v1 n'ont pas de rang
    # de sujet et n'entrent donc pas dans ce breakdown.
    assert ranks[1]["shown"] == 4
    assert ranks[1]["consumed"] == 2
    assert ranks[3]["shown"] == 1
    assert ranks[3]["consumed"] == 0


def test_by_slot_separates_actu_from_extra():
    metrics = _metrics("all")
    slots = _keyed(metrics["by_slot"])
    assert slots["actu"]["shown"] == 7
    assert slots["extra"]["shown"] == 1
    assert slots["flat"]["shown"] == 2
    assert slots["topic"]["shown"] == 1


def test_by_subject_aggregates_across_users():
    metrics = _metrics("all")
    subjects = _keyed(metrics["by_subject"])
    # « Réforme des retraites » : D1, D2, D3 — 2 consommés sur 3.
    assert subjects["Réforme des retraites"]["shown"] == 3
    assert subjects["Réforme des retraites"]["consumed"] == 2
    # « Sommet climat » : actu D1 + extra D1 + actu D2.
    assert subjects["Sommet climat"]["shown"] == 3


def test_rows_without_subject_label_are_not_bucketed_as_empty():
    metrics = _metrics("all")
    assert all(row["key"] for row in metrics["by_subject"])
    assert None not in _keyed(metrics["by_subject"])


# ---------------------------------------------------------------------------
# Bandes de score : forward-only, donc `missing` attendu
# ---------------------------------------------------------------------------


def test_missing_pillar_scores_fall_into_the_missing_band():
    metrics = _metrics("all")
    bands = _keyed(metrics["by_pillar_band"]["pertinence"])
    # D1 extra + D3 (x2) + D4 rang 2 + D5 n'ont pas de pillar_scores.
    assert bands["missing"]["shown"] == 5
    assert bands["60-80"]["shown"] == 2  # D1 r1 (74) et D2 r1 (68)


def test_missing_final_score_falls_into_the_missing_band():
    metrics = _metrics("all")
    bands = _keyed(metrics["by_score_band"])
    assert bands["missing"]["shown"] == 2  # l'extra de D1 et la ligne topics_v1
    assert bands["80-100"]["shown"] == 1


# ---------------------------------------------------------------------------
# Legacy + garde-fou format
# ---------------------------------------------------------------------------


def test_legacy_formats_still_parse():
    metrics = _metrics("all")
    formats = _keyed(metrics["format_versions"])
    assert formats["editorial_v3"]["slots"] == 8
    assert formats["editorial_v3"]["digests"] == 3
    assert formats["flat_v1"]["slots"] == 2
    assert formats["topics_v1"]["slots"] == 1


def test_flat_v1_rank_is_read_from_the_item():
    metrics = _metrics("all")
    ranks = _keyed(metrics["by_rank"])
    # rang 2 : D1 sujet 2 + son extra, D2 sujet 2, D3 sujet 2, D4 item 2.
    assert ranks[2]["shown"] == 5


def test_sql_reads_the_three_formats():
    """Garde-fou : la requête doit couvrir les 3 layouts de `daily_digest.items`.

    Le défaut d'origine de cette jauge était de n'en connaître que deux — elle
    retournait 0 ligne sur 97 % de la prod sans le dire.
    """
    for cte in ("flat_items", "topic_items", "editorial_items"):
        assert cte in SQL
    assert "'subjects'" in SQL
    assert "'extra_actu_articles'" in SQL
    assert "format_version" in SQL


# ---------------------------------------------------------------------------
# Rendu
# ---------------------------------------------------------------------------


def _render(metrics: dict) -> str:
    return render_report(
        metrics,
        since=dt.datetime(2026, 7, 1, tzinfo=dt.UTC),
        until=dt.datetime(2026, 7, 29, tzinfo=dt.UTC),
        mode=None,
        include_serene=False,
        tag="test",
        row_limit_hit=False,
    )


def test_render_report_states_the_denominator_and_the_three_columns():
    report = _render(_metrics("engaged-loo"))
    assert "Dénominateur retenu : `engaged-loo`" in report
    for name in DENOMINATORS:
        assert f"`{name}`" in report
    assert "digest_completions" in report  # le rejet est écrit, pas implicite
    assert "Forward-only" in report


def test_render_report_warns_when_row_limit_is_hit():
    metrics = _metrics("all")
    report = render_report(
        metrics,
        since=dt.datetime(2026, 7, 1, tzinfo=dt.UTC),
        until=dt.datetime(2026, 7, 29, tzinfo=dt.UTC),
        mode=None,
        include_serene=False,
        tag="test",
        row_limit_hit=True,
    )
    assert "`--row-limit` atteint" in report


def test_render_compare_flags_mismatched_denominators():
    baseline = {"metrics": _metrics("engaged-loo")}
    after = {"metrics": _metrics("all")}
    compare = render_compare(baseline, after)
    assert "ne sont pas comparables" in compare

    same = render_compare({"metrics": _metrics("all")}, {"metrics": _metrics("all")})
    assert "ne sont pas comparables" not in same
    assert "+0.0 pp" in same
