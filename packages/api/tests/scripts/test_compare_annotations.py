"""Tests hermétiques pour `scripts/compare_annotations.py`."""

from __future__ import annotations

import math

from scripts.compare_annotations import (
    aggregate,
    cohen_kappa,
    match_spans,
    score_perspective,
)


# ---------------------------------------------------------------------------
# match_spans
# ---------------------------------------------------------------------------


def test_match_spans_one_to_one_by_overlap():
    gold = [{"start": 0, "end": 10}, {"start": 20, "end": 30}]
    pred = [{"start": 2, "end": 8}, {"start": 25, "end": 35}]
    pairs, fn, fp = match_spans(gold, pred)
    assert len(pairs) == 2
    assert fn == [] and fp == []


def test_match_spans_unmatched_become_fn_fp():
    gold = [{"start": 0, "end": 5}]
    pred = [{"start": 10, "end": 15}]
    pairs, fn, fp = match_spans(gold, pred)
    assert pairs == []
    assert fn == gold
    assert fp == pred


def test_match_spans_picks_bigger_overlap():
    gold = [{"start": 0, "end": 10}]
    pred = [{"start": 0, "end": 3}, {"start": 0, "end": 9}]
    pairs, fn, fp = match_spans(gold, pred)
    assert len(pairs) == 1
    # Le span pred (0,9) gagne (overlap=9) vs (0,3) (overlap=3)
    assert pairs[0][1]["end"] == 9
    assert fp == [{"start": 0, "end": 3}]


# ---------------------------------------------------------------------------
# cohen_kappa
# ---------------------------------------------------------------------------


def test_kappa_perfect_agreement():
    pairs = [("a", "a"), ("b", "b"), ("a", "a")]
    assert cohen_kappa(pairs) == 1.0


def test_kappa_complete_disagreement():
    # Deux annotateurs jamais d'accord, mais distribution = même
    pairs = [("a", "b"), ("b", "a"), ("a", "b"), ("b", "a")]
    # p_obs=0, p_exp=0.5 → κ=-1
    assert cohen_kappa(pairs) == -1.0


def test_kappa_chance_level():
    # Annotateurs d'accord exactement au niveau du hasard → κ proche de 0
    pairs = [("a", "a"), ("a", "b"), ("b", "a"), ("b", "b")]
    kappa = cohen_kappa(pairs)
    assert abs(kappa) < 1e-9


def test_kappa_empty_pairs():
    assert cohen_kappa([]) == 0.0


# ---------------------------------------------------------------------------
# score_perspective sans spaCy
# ---------------------------------------------------------------------------


def test_score_perspective_perfect_match():
    title = "Trump écrase Massie : la mainmise"
    spans = [
        {"start": 6, "end": 12, "text": "écrase",
         "category": "editorial_angle", "weight": 1.0},
        {"start": 25, "end": 33, "text": "mainmise",
         "category": "framing_noun", "weight": 1.0},
    ]
    gold = {"target_spans": spans, "exclude_spans": []}
    pred = {"target_spans": spans, "exclude_spans": []}
    s = score_perspective(title, gold, pred, svc=None)
    assert len(s["tp_span"]) == 2
    assert s["fp_span"] == [] and s["fn_span"] == []
    assert s["disagreement_score"] == 0
    # 2 matchs avec weight=1.0 chacun
    assert all(a == b for a, b in s["weight_diffs"])


def test_score_perspective_weight_disagreement_yields_mae():
    title = "écrase"  # 6 chars
    gold = {
        "target_spans": [
            {"start": 0, "end": 6, "text": "écrase",
             "category": "editorial_angle", "weight": 1.0},
        ],
        "exclude_spans": [],
    }
    pred = {
        "target_spans": [
            {"start": 0, "end": 6, "text": "écrase",
             "category": "editorial_angle", "weight": 0.5},
        ],
        "exclude_spans": [],
    }
    s = score_perspective(title, gold, pred, svc=None)
    # Span matché mais weight différent
    assert s["weight_diffs"] == [(1.0, 0.5)]
    # Span identique → pas de désaccord span-level
    assert s["fp_span"] == [] and s["fn_span"] == []


def test_score_perspective_fp_and_fn():
    title = "Trump écrase Massie : la mainmise"
    gold = {
        "target_spans": [
            {"start": 6, "end": 12, "text": "écrase",
             "category": "editorial_angle", "weight": 1.0},
        ],
        "exclude_spans": [],
    }
    pred = {
        "target_spans": [
            {"start": 25, "end": 33, "text": "mainmise",
             "category": "framing_noun", "weight": 1.0},
        ],
        "exclude_spans": [],
    }
    s = score_perspective(title, gold, pred, svc=None)
    assert s["fn_span"] == [(6, 12)]
    assert s["fp_span"] == [(25, 33)]
    assert s["disagreement_score"] == 2


# ---------------------------------------------------------------------------
# aggregate
# ---------------------------------------------------------------------------


def test_aggregate_combines_scores():
    title = "Trump écrase Massie"
    spans = [
        {"start": 6, "end": 12, "text": "écrase",
         "category": "editorial_angle", "weight": 1.0},
    ]
    gold = {"target_spans": spans, "exclude_spans": []}
    pred = {"target_spans": spans, "exclude_spans": []}

    scores = [
        score_perspective(title, gold, pred, svc=None),
        score_perspective(title, gold, pred, svc=None),
    ]
    m = aggregate(scores)
    assert m["n_perspectives"] == 2
    assert m["span"]["precision"] == 1.0
    assert m["span"]["recall"] == 1.0
    assert m["span"]["f1"] == 1.0
    assert m["weight_agreement"]["n"] == 2
    assert m["weight_agreement"]["mae"] == 0.0


def test_aggregate_weight_mae():
    title = "écrase"
    gold = {
        "target_spans": [
            {"start": 0, "end": 6, "text": "écrase",
             "category": "editorial_angle", "weight": 1.0},
        ],
        "exclude_spans": [],
    }
    pred = {
        "target_spans": [
            {"start": 0, "end": 6, "text": "écrase",
             "category": "editorial_angle", "weight": 0.25},
        ],
        "exclude_spans": [],
    }
    scores = [score_perspective(title, gold, pred, svc=None)]
    m = aggregate(scores)
    assert math.isclose(m["weight_agreement"]["mae"], 0.75)
