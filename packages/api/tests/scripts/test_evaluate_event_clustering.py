"""Tests hermétiques pour `scripts/evaluate_event_clustering.py`.

Pas de réseau ni de DB : le harness importe les fonctions pures de la porte
(`PerspectiveService._topical_signals`, `_is_topically_coherent`) et les
rejoue sur un toy pool aux TP/FP/FN connus.

Couvre :
- `gate_pair` (défaut) == porte réelle `_is_topically_coherent` (anti-drift) ;
- `classify_accept_path` / `classify_reject_reason` concordent avec la décision ;
- agrégation pairwise sur le toy pool (TP/FP/FN connus, FP planté →
  `weak_double_signal`, FN → `jaccard_below_floor`) ;
- exclusion NOISE des positifs ;
- sweep du floor (le FP planté disparaît à 0.15 sans coût de rappel) ;
- format `render_compare`.
"""

import json
from itertools import product
from pathlib import Path

from app.services.perspective_service import PerspectiveService
from scripts.evaluate_event_clustering import (
    classify_accept_path,
    classify_reject_reason,
    evaluate_dataset,
    gate_pair,
    render_compare,
    sweep,
)

FIXTURE = Path(__file__).parent / "fixtures" / "toy_event_dataset.json"


def _toy() -> dict:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Anti-drift : gate_pair (défaut) doit reproduire la porte réelle
# ---------------------------------------------------------------------------


def _signal_grid():
    jaccards = [0.0, 0.05, 0.08, 0.10, 0.1429, 0.15, 0.29, 0.30, 0.50]
    topics = [None, 0, 1, 2]
    entities = [None, 0, 1, 2]
    for j, t, e in product(jaccards, topics, entities):
        yield {"title_jaccard": j, "shared_topics": t, "shared_entities": e}


def test_gate_pair_matches_real_gate():
    """gate_pair() avec les params par défaut == _is_topically_coherent()."""
    for signals in _signal_grid():
        assert gate_pair(signals) == PerspectiveService._is_topically_coherent(
            signals
        ), signals


def test_classify_accept_path_agrees_with_decision():
    """accept_path non-None ⟺ porte accepte ; reject_reason non-None ⟺ rejette."""
    for signals in _signal_grid():
        is_ok, _ = PerspectiveService._is_topically_coherent(signals)
        assert (classify_accept_path(signals) is not None) == is_ok, signals
        assert (classify_reject_reason(signals) is None) == is_ok, signals


def test_classify_accept_path_buckets():
    """Les 3 chemins d'acceptation sont bien discriminés."""
    # strong jaccard
    assert (
        classify_accept_path(
            {"title_jaccard": 0.5, "shared_topics": 0, "shared_entities": 0}
        )
        == "strong_jaccard"
    )
    # 2 entités discriminantes (pas de floor requis)
    assert (
        classify_accept_path(
            {"title_jaccard": 0.0, "shared_topics": 0, "shared_entities": 2}
        )
        == "double_entity"
    )
    # weak double signal (la fuite) — Jaccard ≥ floor (0.15 > 0.12 calibré Iter 1)
    assert (
        classify_accept_path(
            {"title_jaccard": 0.15, "shared_topics": 1, "shared_entities": 1}
        )
        == "weak_double_signal"
    )
    # rejeté
    assert (
        classify_accept_path(
            {"title_jaccard": 0.0, "shared_topics": 1, "shared_entities": 1}
        )
        is None
    )


def test_classify_reject_reason_buckets():
    # signaux incomplets (Layer 2/3) + jaccard faible
    assert (
        classify_reject_reason(
            {"title_jaccard": 0.0, "shared_topics": None, "shared_entities": None}
        )
        == "low_jaccard"
    )
    # full signals mais jaccard sous le floor (le gap des paraphrases)
    assert (
        classify_reject_reason(
            {"title_jaccard": 0.0, "shared_topics": 2, "shared_entities": 1}
        )
        == "jaccard_below_floor"
    )
    # jaccard ≥ floor mais aucun topic partagé (0.15 > 0.12 calibré Iter 1)
    assert (
        classify_reject_reason(
            {"title_jaccard": 0.15, "shared_topics": 0, "shared_entities": 1}
        )
        == "no_shared_topic"
    )
    # jaccard ≥ floor, topic partagé, mais aucune entité partagée
    assert (
        classify_reject_reason(
            {"title_jaccard": 0.15, "shared_topics": 1, "shared_entities": 0}
        )
        == "no_shared_entity"
    )


# ---------------------------------------------------------------------------
# gate_pair paramétrable (sweep)
# ---------------------------------------------------------------------------


def test_gate_pair_higher_floor_rejects_weak_double_signal():
    """Un weak double signal à Jaccard 0.1429 est accepté à 0.08, rejeté à 0.15."""
    signals = {"title_jaccard": 0.1429, "shared_topics": 1, "shared_entities": 1}
    assert gate_pair(signals, floor=0.08)[0] is True
    assert gate_pair(signals, floor=0.15)[0] is False


def test_gate_pair_require_double_entity_disables_weak_branch():
    signals = {"title_jaccard": 0.1429, "shared_topics": 1, "shared_entities": 1}
    assert gate_pair(signals, require_double_entity=True)[0] is False
    # mais 2 entités partagées passent toujours
    strong = {"title_jaccard": 0.0, "shared_topics": 0, "shared_entities": 2}
    assert gate_pair(strong, require_double_entity=True)[0] is True


# ---------------------------------------------------------------------------
# Agrégation pairwise sur le toy pool (TP/FP/FN connus)
# ---------------------------------------------------------------------------


def test_evaluate_toy_pool_known_confusion():
    """5 articles : iran(3) + nba(1) + NOISE(1).

    20 paires ordonnées → TP=2 (T1↔T2 fort Jaccard), FP=4 (Trump/NOISE via
    weak_double_signal), FN=4 (paraphrase T4 ↔ T1/T2, Jaccard sous le floor),
    TN=10.
    """
    metrics = evaluate_dataset(_toy())
    micro = metrics["micro"]
    assert metrics["n_pairs"] == 20
    assert micro["tp"] == 2
    assert micro["fp"] == 4
    assert micro["fn"] == 4
    assert micro["tn"] == 10
    assert round(micro["precision"], 3) == 0.333
    assert round(micro["recall"], 3) == 0.333


def test_evaluate_toy_pool_fp_leak_is_weak_double_signal():
    """La fuite : tous les FP passent par `weak_double_signal`."""
    metrics = evaluate_dataset(_toy())
    assert metrics["fp_by_accept_path"] == {"weak_double_signal": 4}


def test_evaluate_toy_pool_fn_is_paraphrase_gap():
    """Le gap : tous les FN sont des paraphrases sous le floor de Jaccard."""
    metrics = evaluate_dataset(_toy())
    assert metrics["fn_by_reason"] == {"jaccard_below_floor": 4}


def test_evaluate_toy_pool_full_signal_coverage():
    """Tous les articles portent topics+entities → 100% full_signals."""
    metrics = evaluate_dataset(_toy())
    assert metrics["signal_coverage"]["full_signals_ratio"] == 1.0


def test_evaluate_toy_pool_contamination():
    """Contamination moyenne = (0.5 + 0.5 + 1.0)/3 ; pire offender = le NOISE seed."""
    metrics = evaluate_dataset(_toy())
    contam = metrics["contamination"]
    assert round(contam["mean"], 3) == 0.667
    assert contam["n_seeds"] == 3
    assert contam["worst"][0][1] == 1.0  # le seed NOISE admet 100% d'off-event


def test_noise_never_counts_as_positive():
    """Si TOUT est NOISE, aucun positif gold : TP=FN=0, et chaque paire admise
    devient un FP (les 2 fort-Jaccard + les 4 weak = 6 acceptations)."""
    ds = _toy()
    for a in ds["pools"][0]["articles"]:
        a["event_id"] = "NOISE"
    metrics = evaluate_dataset(ds)
    assert metrics["micro"]["tp"] == 0
    assert metrics["micro"]["fn"] == 0
    assert metrics["micro"]["fp"] == 6  # 2 (T1↔T2 fort) + 4 (Trump/NOISE weak)


# ---------------------------------------------------------------------------
# Sweep
# ---------------------------------------------------------------------------


def test_sweep_floor_kills_planted_fp_without_recall_cost():
    """À floor=0.15, les 4 FP plantés disparaissent ; le rappel ne bouge pas
    (les FN sont des paraphrases à Jaccard 0, insensibles au floor)."""
    rows = sweep(_toy(), [0.08, 0.15])
    by_setting = {r["setting"]: r for r in rows}
    base = by_setting["floor=0.08"]
    tuned = by_setting["floor=0.15"]
    assert base["fp"] == 4
    assert tuned["fp"] == 0
    assert tuned["precision"] == 1.0
    # rappel inchangé : le floor ne touche pas les FN (paraphrases)
    assert tuned["recall"] == base["recall"]


def test_sweep_includes_require_double_entity_variant():
    rows = sweep(_toy(), [0.08])
    settings = {r["setting"] for r in rows}
    assert "require_entities>=2" in settings
    variant = next(r for r in rows if r["setting"] == "require_entities>=2")
    assert variant["fp"] == 0  # weak branch off → FP plantés rejetés


# ---------------------------------------------------------------------------
# render_compare
# ---------------------------------------------------------------------------


def test_render_compare_delta():
    baseline = {
        "n_pairs": 20,
        "micro": {"precision": 0.333, "recall": 0.333, "f1": 0.333, "fp": 4, "fn": 4},
        "contamination": {"mean": 0.667},
    }
    after = {
        "n_pairs": 20,
        "micro": {"precision": 1.0, "recall": 0.333, "f1": 0.5, "fp": 0, "fn": 4},
        "contamination": {"mean": 0.0},
    }
    report = render_compare(baseline, after)
    assert "+0.667" in report  # Δ précision = 1.0 - 0.333
    assert "-4" in report  # Δ FP
    assert "contamination" in report
