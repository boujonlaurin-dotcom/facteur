"""Tests pour scripts/apply_source_descriptions.py (apply description-only).

Couvre : compute_changes écrit un diff ; no-op idempotent si description
identique ; source introuvable listée ; _load_descriptions rejette em-dash et
description vide. Tout est pur (pas de DB).
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from scripts.apply_source_descriptions import (
    _load_descriptions,
    compute_changes,
)

SID = "11111111-1111-1111-1111-111111111111"
SID2 = "22222222-2222-2222-2222-222222222222"


def test_compute_writes_when_description_differs():
    items = [{"source_id": SID, "description": "Une description complète et factuelle."}]
    current = {SID: {"name": "Le Monde", "description": "court"}}
    writes, missing = compute_changes(items, current)
    assert len(writes) == 1
    assert writes[0].old == "court"
    assert writes[0].new == "Une description complète et factuelle."
    assert missing == []


def test_compute_idempotent_noop_when_identical():
    same = "Description identique."
    items = [{"source_id": SID, "description": same}]
    current = {SID: {"name": "X", "description": same}}
    writes, missing = compute_changes(items, current)
    assert writes == []
    assert missing == []


def test_compute_reports_missing_source():
    items = [{"source_id": SID2, "description": "peu importe"}]
    writes, missing = compute_changes(items, {})
    assert writes == []
    assert missing == [SID2]


def test_load_descriptions_rejects_em_dash(tmp_path: Path):
    p = tmp_path / "d.json"
    p.write_text(
        json.dumps({"descriptions": [{"source_id": SID, "description": "a — b"}]})
    )
    with pytest.raises(ValueError, match="tiret cadratin"):
        _load_descriptions(p)


def test_load_descriptions_rejects_empty(tmp_path: Path):
    p = tmp_path / "d.json"
    p.write_text(json.dumps({"descriptions": [{"source_id": SID, "description": "  "}]}))
    with pytest.raises(ValueError, match="vide"):
        _load_descriptions(p)


def test_load_descriptions_accepts_evaluations_key(tmp_path: Path):
    p = tmp_path / "d.json"
    p.write_text(
        json.dumps({"evaluations": [{"source_id": SID, "description": "ok valable"}]})
    )
    items = _load_descriptions(p)
    assert items == [{"source_id": SID, "description": "ok valable"}]
