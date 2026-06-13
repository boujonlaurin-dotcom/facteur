"""Tests hermétiques pour `scripts/evaluate_title_annotations.py`.

Vérifie les fonctions pures (fusion de spans, agrégation, catégorisation
d'erreurs, mode --compare) puis exécute un smoke test bout-en-bout avec
un `FakeNlp` injecté et un toy dataset.
"""

import json
from pathlib import Path

from scripts.evaluate_title_annotations import (
    aggregate,
    evaluate_dataset,
    fuse_spans,
    render_compare,
    score_article,
    spans_overlap,
)
from tests.fixtures.fake_spacy import (
    FakeDoc,
    FakeEnt,
    FakeNlp,
    FakeToken,
    service_with_nlp,
)


# ---------------------------------------------------------------------------
# Span helpers
# ---------------------------------------------------------------------------


def test_fuse_spans_merges_contiguous():
    """Spans contigus (gap ≤ 1) sont fusionnés en un seul intervalle."""
    spans = [{"start": 0, "end": 4}, {"start": 5, "end": 10}]
    assert fuse_spans(spans, gap=1) == [(0, 10)]


def test_fuse_spans_respects_gap_threshold():
    """Spans séparés par > gap chars restent distincts."""
    spans = [{"start": 0, "end": 4}, {"start": 8, "end": 10}]
    assert fuse_spans(spans, gap=1) == [(0, 4), (8, 10)]


def test_fuse_spans_empty():
    assert fuse_spans([]) == []


def test_spans_overlap_basic():
    assert spans_overlap((0, 5), (3, 7)) is True
    assert spans_overlap((0, 5), (5, 7)) is False  # touching but non-overlapping
    assert spans_overlap((0, 5), (10, 12)) is False


# ---------------------------------------------------------------------------
# score_article (pure : pas de spaCy)
# ---------------------------------------------------------------------------


def _alt_tokens_for_donald_trump_paris():
    """Tokens fabriqués manuellement pour 'Donald Trump reçoit Macron à Paris'."""
    return [
        {"start": 0, "end": 6, "text": "Donald", "lemma": "donald", "pos": "PROPN"},
        {"start": 7, "end": 12, "text": "Trump", "lemma": "trump", "pos": "PROPN"},
        {"start": 13, "end": 19, "text": "reçoit", "lemma": "recevoir", "pos": "VERB"},
        {"start": 20, "end": 26, "text": "Macron", "lemma": "macron", "pos": "PROPN"},
        {"start": 29, "end": 34, "text": "Paris", "lemma": "paris", "pos": "PROPN"},
    ]


def test_score_article_perfect_match():
    """Pred = gold ⟹ TP rempli, pas de FP/FN."""
    tokens = _alt_tokens_for_donald_trump_paris()
    pred = [{"start": 29, "end": 34, "text": "Paris", "bias": "left"}]
    target = [{"start": 29, "end": 34, "text": "Paris", "category": "fact"}]

    score = score_article(
        svc=None,
        cluster_key="c",
        article_id="a",
        alt_title="Donald Trump reçoit Macron à Paris",
        alt_tokens=tokens,
        pred_spans=pred,
        target_spans=target,
        exclude_spans=[],
    )

    assert score.tp_lemmas == {"paris"}
    assert score.fp_lemmas == set()
    assert score.fn_lemmas == set()
    assert score.tp_spans == [(29, 34)]
    assert score.fp_spans == []
    assert score.fn_spans == []


def test_score_article_zero_recall_when_no_prediction():
    """Pred vide, gold non-vide ⟹ R = 0 et tous les FN tagués par catégorie."""
    tokens = _alt_tokens_for_donald_trump_paris()
    target = [{"start": 29, "end": 34, "text": "Paris", "category": "fact"}]

    score = score_article(
        svc=None, cluster_key="c", article_id="a",
        alt_title="t", alt_tokens=tokens,
        pred_spans=[], target_spans=target, exclude_spans=[],
    )

    assert score.tp_lemmas == set()
    assert score.fn_lemmas == {"paris"}
    assert "FN_fact" in score.fn_by_category
    assert score.fn_by_category["FN_fact"][0][1] == "paris"


def test_score_article_categorizes_fp_against_exclude_spans():
    """Span prédit qui chevauche un exclude_span ⟹ FP_<category>."""
    tokens = _alt_tokens_for_donald_trump_paris()
    pred = [
        {"start": 0, "end": 6, "text": "Donald", "bias": "left"},
        {"start": 13, "end": 19, "text": "reçoit", "bias": "left"},
    ]
    target = [{"start": 29, "end": 34, "text": "Paris", "category": "fact"}]
    exclude = [
        {"start": 0, "end": 6, "text": "Donald", "category": "entity_alias"},
        {"start": 13, "end": 19, "text": "reçoit", "category": "neutral_verb"},
    ]

    score = score_article(
        svc=None, cluster_key="c", article_id="a",
        alt_title="t", alt_tokens=tokens,
        pred_spans=pred, target_spans=target, exclude_spans=exclude,
    )

    assert "FP_entity_alias" in score.fp_by_category
    assert "FP_neutral_verb" in score.fp_by_category
    assert score.fp_by_category["FP_entity_alias"][0][1] == "donald"
    assert score.fp_by_category["FP_neutral_verb"][0][1] == "recevoir"


# ---------------------------------------------------------------------------
# aggregate
# ---------------------------------------------------------------------------


def test_aggregate_top_n_lemma_counter():
    """3 articles avec FP sur 'dire' ⟹ top FP[0] == ('dire', 3)."""
    tokens = [{"start": 0, "end": 3, "text": "dit", "lemma": "dire", "pos": "VERB"}]
    pred = [{"start": 0, "end": 3, "text": "dit", "bias": "right"}]
    exclude = [{"start": 0, "end": 3, "text": "dit", "category": "neutral_verb"}]

    scores = [
        score_article(
            svc=None, cluster_key=f"c{i}", article_id=f"a{i}",
            alt_title="t", alt_tokens=tokens,
            pred_spans=pred, target_spans=[], exclude_spans=exclude,
        )
        for i in range(3)
    ]
    metrics = aggregate(scores)

    assert metrics["top_fp_lemmas"][0] == ("dire", 3)
    assert metrics["fp_categories"]["FP_neutral_verb"] == 3
    assert metrics["token"]["fp"] == 3
    assert metrics["token"]["tp"] == 0


def test_aggregate_perfect_recall_no_fp():
    tokens = [{"start": 0, "end": 5, "text": "Paris", "lemma": "paris", "pos": "PROPN"}]
    pred = [{"start": 0, "end": 5, "text": "Paris", "bias": "left"}]
    target = [{"start": 0, "end": 5, "text": "Paris", "category": "fact"}]

    score = score_article(
        svc=None, cluster_key="c", article_id="a",
        alt_title="t", alt_tokens=tokens,
        pred_spans=pred, target_spans=target, exclude_spans=[],
    )
    metrics = aggregate([score])

    assert metrics["token"]["precision"] == 1.0
    assert metrics["token"]["recall"] == 1.0
    assert metrics["token"]["f1"] == 1.0


# ---------------------------------------------------------------------------
# render_compare
# ---------------------------------------------------------------------------


def test_render_compare_delta():
    baseline = {
        "n_perspectives": 10,
        "token": {"precision": 0.5, "recall": 0.5, "f1": 0.5, "tp": 0, "fp": 0, "fn": 0},
        "span":  {"precision": 0.5, "recall": 0.5, "f1": 0.5, "tp": 0, "fp": 0, "fn": 0},
    }
    after = {
        "n_perspectives": 10,
        "token": {"precision": 0.7, "recall": 0.6, "f1": 0.65, "tp": 0, "fp": 0, "fn": 0},
        "span":  {"precision": 0.7, "recall": 0.6, "f1": 0.65, "tp": 0, "fp": 0, "fn": 0},
    }

    report = render_compare(baseline, after)

    # Le delta pour token/f1 = 0.65 - 0.5 = +0.150
    assert "+0.150" in report
    assert "token" in report
    assert "span" in report


# ---------------------------------------------------------------------------
# Smoke test bout-en-bout sur toy dataset (avec FakeNlp injecté)
# ---------------------------------------------------------------------------


def _toy_fake_nlp() -> FakeNlp:
    """FakeNlp couvrant les 2 titres du toy dataset."""
    ref = FakeDoc(
        tokens=[
            FakeToken("Macron", 0, "PROPN", "Macron"),
            FakeToken("rencontre", 7, "VERB", "rencontrer"),
            FakeToken("Trump", 17, "PROPN", "Trump"),
        ],
        ents=[FakeEnt(0, 6, "PER"), FakeEnt(17, 22, "PER")],
    )
    alt = FakeDoc(
        tokens=[
            FakeToken("Donald", 0, "PROPN", "Donald"),
            FakeToken("Trump", 7, "PROPN", "Trump"),
            FakeToken("reçoit", 13, "VERB", "recevoir"),
            FakeToken("Macron", 20, "PROPN", "Macron"),
            FakeToken("à", 27, "ADP", "à", is_stop=True),
            FakeToken("Paris", 29, "PROPN", "Paris"),
        ],
        ents=[
            FakeEnt(0, 12, "PER"),  # Donald Trump
            FakeEnt(20, 26, "PER"),
            FakeEnt(29, 34, "LOC"),
        ],
    )
    return FakeNlp({
        "Macron rencontre Trump": ref,
        "Donald Trump reçoit Macron à Paris": alt,
    })


def test_evaluate_dataset_smoke_on_toy():
    """Bout-en-bout : 1 cluster, 1 perspective annotée.

    Pred (capé à 4, priorité PROPN < VERB) doit contenir Donald, Paris,
    reçoit (3 spans).
    Gold target = {Paris}, exclude = {Donald, reçoit}.
    Attendu :
      TP_token = {paris}, FP = {donald, recevoir}, FN = {}
      FP_entity_alias = 1, FP_neutral_verb = 1
    """
    fixture_path = (
        Path(__file__).parent / "fixtures" / "toy_dataset.json"
    )
    dataset = json.loads(fixture_path.read_text(encoding="utf-8"))
    svc = service_with_nlp(_toy_fake_nlp())

    scores = evaluate_dataset(dataset, svc, annotator="po_synchronous")
    metrics = aggregate(scores)

    assert metrics["n_perspectives"] == 1
    assert metrics["token"]["tp"] == 1
    assert metrics["token"]["fp"] == 2
    assert metrics["token"]["fn"] == 0
    assert metrics["fp_categories"]["FP_entity_alias"] == 1
    assert metrics["fp_categories"]["FP_neutral_verb"] == 1
    # paris doit être un TP, donc absent des top FP
    top_fp_lemmas = {lemma for lemma, _ in metrics["top_fp_lemmas"]}
    assert "paris" not in top_fp_lemmas
    assert "donald" in top_fp_lemmas
    assert "recevoir" in top_fp_lemmas


def test_evaluate_dataset_skips_unannotated_perspectives():
    """Une perspective sans annotation `po_synchronous` ne doit pas être scorée."""
    fixture_path = (
        Path(__file__).parent / "fixtures" / "toy_dataset.json"
    )
    dataset = json.loads(fixture_path.read_text(encoding="utf-8"))
    # Vide les annotations sur la seule perspective
    dataset["clusters"][0]["articles"][1]["annotations"] = {}
    svc = service_with_nlp(_toy_fake_nlp())

    scores = evaluate_dataset(dataset, svc, annotator="po_synchronous")
    assert scores == []
