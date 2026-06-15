"""Tests pour scripts/build_source_eval_prompt.py.

Couvre : le prompt embarque le texte de la rubrique verbatim + les contextes
sources + demande les bons champs JSON (4 justifs + sources_consulted), NE demande
PAS `reliability_score` (dérivé), inclut la consigne web 3-4 ; batched() découpe ;
load_targets lit la clé `targets`.
"""

from __future__ import annotations

import json

import pytest

from scripts.build_source_eval_prompt import (
    REQUIRED_FIELDS,
    _spec_block,
    batched,
    build_prompt,
    load_targets,
    render_source_context,
)

RUBRIC = "## 2. reliability_score dérivé\nMARQUEUR_RUBRIQUE_UNIQUE\nblabla"

TARGET = {
    "source_id": "abc-123",
    "name": "BFMTV",
    "url": "https://www.bfmtv.com",
    "feed_url": "https://www.bfmtv.com/rss/",
    "type": "article",
    "theme": "society",
    "n_content": 42,
    "recent_titles": ["Titre A", "Titre B"],
    "current": {
        "bias_stance": "unknown",
        "reliability_score": "unknown",
        "score_independence": None,
        "score_rigor": None,
        "score_ux": None,
    },
}


def test_spec_excludes_reliability_score():
    spec = _spec_block()
    assert '"reliability_score"' not in spec
    assert "NE renvoie PAS `reliability_score`" in spec
    assert "reliability_score" not in REQUIRED_FIELDS


def test_required_fields_include_rationales_and_sources():
    for f in (
        "bias_rationale",
        "independence_rationale",
        "rigor_rationale",
        "ux_rationale",
        "sources_consulted",
    ):
        assert f in REQUIRED_FIELDS


def test_render_source_context_has_identity():
    ctx = render_source_context(TARGET)
    assert "abc-123" in ctx
    assert "BFMTV" in ctx
    assert "https://www.bfmtv.com/rss/" in ctx
    assert "Titre A" in ctx


def test_build_prompt_embeds_rubric_and_context_and_spec():
    prompt = build_prompt(RUBRIC, [TARGET], batch_index=3)
    # rubrique verbatim
    assert "MARQUEUR_RUBRIQUE_UNIQUE" in prompt
    # contexte source
    assert "abc-123" in prompt
    assert "https://www.bfmtv.com/rss/" in prompt
    # champs JSON demandés
    assert "bias_rationale" in prompt
    assert "sources_consulted" in prompt
    # reliability NON demandé en sortie
    assert "NE renvoie PAS `reliability_score`" in prompt
    # consigne web mainstream
    assert "3-4 requêtes" in prompt
    # index de lot reporté
    assert "lot 3" in prompt


def test_batched_splits_and_keeps_all():
    items = [{"i": i} for i in range(23)]
    batches = batched(items, 10)
    assert [len(b) for b in batches] == [10, 10, 3]
    assert sum(len(b) for b in batches) == 23


def test_batched_rejects_zero_size():
    with pytest.raises(ValueError):
        batched([{"i": 1}], 0)


def test_load_targets_reads_targets_key(tmp_path):
    p = tmp_path / "targets.json"
    p.write_text(json.dumps({"targets": [TARGET], "gold": []}))
    assert load_targets(p) == [TARGET]
