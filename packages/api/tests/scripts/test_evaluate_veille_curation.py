"""Tests hermétiques pour `scripts/evaluate_veille_curation.py`.

Pas de réseau ni de DB (le harness reconstruit le `ScoringContext` via un stub
de session) : on rejoue la **vraie** porte (`feed_filter._score_block` /
`_matched_axes`) sur un toy à confusion connue.

Couvre :
- **anti-drift** : le harness importe et appelle les **vrais** symboles de la
  porte (un fork de `_score_block`/`_matched_axes` casserait l'identité) ;
- `policy_flags` (laisser-passer / floor / floor+seuil) ;
- `classify_accept_path` / `classify_reject_reason` ;
- toy passthrough : un off_angle source-seul survit au cap → **FP Bloc A
  `source_only`** (la fuite) ;
- toy gate-all : le floor tue ce FP (FP=0) et le mot-entier écarte le
  off_angle « agentic » (pas d'axe keyword) ;
- toy gate-all : un relevant sans mot-clé littéral devient **FN
  `floor_source_only`** (coût en rappel mesuré) ;
- prédicat Bloc B en mot-entier : « agentic » n'est jamais candidat ;
- couverture d'axe (keyword-only / source-only).
"""

from pathlib import Path

from app.services.veille import feed_filter
from scripts import evaluate_veille_curation as ev
from scripts.evaluate_veille_curation import (
    classify_accept_path,
    classify_reject_reason,
    evaluate_config,
    evaluate_dataset,
    load_dataset,
    policy_flags,
)

FIXTURE = Path(__file__).parent / "fixtures" / "toy_veille_curation.json"


def _toy_configs():
    return load_dataset(FIXTURE)


def _by_id(results):
    return {r.article_id: r for r in results}


# ---------------------------------------------------------------------------
# Anti-drift : le harness appelle les VRAIS symboles de la porte
# ---------------------------------------------------------------------------


def test_harness_uses_real_gate_symbols():
    """Si la porte est forkée (copie locale), ces identités cassent."""
    assert ev._score_block is feed_filter._score_block
    assert ev._matched_axes is feed_filter._matched_axes


# ---------------------------------------------------------------------------
# policy_flags
# ---------------------------------------------------------------------------


def test_policy_flags():
    assert policy_flags("passthrough") == (False, False)
    assert policy_flags("floor") == (True, False)
    assert policy_flags("floor_threshold") == (True, True)


# ---------------------------------------------------------------------------
# Attribution
# ---------------------------------------------------------------------------


def test_classify_accept_path():
    assert classify_accept_path(["topic", "keyword", "source"]) == "topic+keyword"
    assert classify_accept_path(["topic", "source"]) == "topic"
    assert classify_accept_path(["keyword"]) == "keyword"
    assert classify_accept_path(["source"]) == "source_only"
    assert classify_accept_path([]) == "source_only"


def test_classify_reject_reason():
    common = {"apply_floor": True, "apply_threshold": True, "threshold": 48.0}
    # axes ⊆ {source} + floor actif → source-seul écarté
    assert (
        classify_reject_reason(["source"], 60.0, floor_active=True, **common)
        == "floor_source_only"
    )
    # axe topic mais score sous le seuil → below_threshold
    assert (
        classify_reject_reason(["topic"], 30.0, floor_active=True, **common)
        == "below_threshold"
    )
    # a passé floor + seuil mais pas dans le set gardé → cap de diversité
    assert (
        classify_reject_reason(["topic"], 60.0, floor_active=True, **common)
        == "diversity_capped"
    )


# ---------------------------------------------------------------------------
# Toy passthrough : la fuite (FP Bloc A source_only)
# ---------------------------------------------------------------------------


def test_toy_passthrough_leaks_source_only_block_a_fp():
    metrics = evaluate_dataset(_toy_configs(), "passthrough")
    assert metrics["fp_by_block"].get("A") == 1
    assert metrics["fp_by_path"].get("source_only") == 1
    assert metrics["micro"]["fp"] == 1


def test_toy_passthrough_keeps_off_source_off_angle():
    """`off_source` (source-seul off_angle) est gardé en laisser-passer."""
    _score, results = evaluate_config(_toy_configs()[0], apply_floor=False, apply_threshold=False)
    by_id = _by_id(results)
    assert by_id["off_source"].kept is True
    assert by_id["off_source"].accept_path == "source_only"


# ---------------------------------------------------------------------------
# Toy gate-all : le floor tue la fuite, le mot-entier écarte « agentic »
# ---------------------------------------------------------------------------


def test_toy_floor_kills_source_only_fp():
    metrics = evaluate_dataset(_toy_configs(), "floor_threshold")
    assert metrics["micro"]["fp"] == 0
    assert metrics["fp_by_block"] == {}
    assert metrics["fp_by_path"] == {}


def test_toy_word_boundary_prunes_agentic_off_angle():
    """`off_substr` (« agentic ») : mot-entier ⇒ pas d'axe keyword ⇒ source-seul
    ⇒ floor-pruned. En sous-chaîne il aurait survécu au floor (régression Pb 3).
    """
    _score, results = evaluate_config(_toy_configs()[0], apply_floor=True, apply_threshold=True)
    by_id = _by_id(results)
    off_substr = by_id["off_substr"]
    assert "keyword" not in off_substr.axes
    assert off_substr.kept is False
    assert off_substr.reject_reason == "floor_source_only"


def test_toy_keyword_absent_relevant_is_floor_fn():
    """`para` (relevant sans mot-clé littéral) → FN `floor_source_only` : c'est
    le coût en rappel mesuré du gate-all."""
    metrics = evaluate_dataset(_toy_configs(), "floor_threshold")
    assert metrics["fn_by_reason"].get("floor_source_only") == 1
    _score, results = evaluate_config(_toy_configs()[0], apply_floor=True, apply_threshold=True)
    para = _by_id(results)["para"]
    assert para.gold_relevant is True
    assert para.kept is False
    assert para.reject_reason == "floor_source_only"


# ---------------------------------------------------------------------------
# Prédicat Bloc B en mot-entier : « agentic » n'est jamais candidat
# ---------------------------------------------------------------------------


def test_toy_block_b_prefilter_is_word_boundary():
    """`ext_off` (« agentic patterns », source externe) : ni topic ai ni mot-clé
    en mot-entier ⇒ jamais ramené par le prédicat Bloc B → `not_a_candidate`."""
    _score, results = evaluate_config(_toy_configs()[0], apply_floor=True, apply_threshold=True)
    ext_off = _by_id(results)["ext_off"]
    assert ext_off.block is None
    assert ext_off.kept is False
    assert ext_off.reject_reason == "not_a_candidate"


def test_toy_block_b_topic_candidate_survives():
    """`ext_on` (topic ai, source externe) entre dans le Bloc B et passe."""
    _score, results = evaluate_config(_toy_configs()[0], apply_floor=True, apply_threshold=True)
    ext_on = _by_id(results)["ext_on"]
    assert ext_on.block == "B"
    assert ext_on.kept is True


# ---------------------------------------------------------------------------
# Couverture d'axe
# ---------------------------------------------------------------------------


def test_toy_axis_coverage():
    """4 relevant : on_topic + ext_on (topic), on_kw (keyword-only),
    para (source-only)."""
    metrics = evaluate_dataset(_toy_configs(), "floor_threshold")
    cov = metrics["axis_coverage"]
    assert cov["n_relevant"] == 4
    assert cov["n_relevant_topic"] == 2
    assert cov["n_relevant_keyword_only"] == 1
    assert cov["n_relevant_source_only"] == 1
