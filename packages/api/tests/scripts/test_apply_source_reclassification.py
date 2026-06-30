"""Tests pour scripts/apply_source_reclassification.py.

Couvre (logique **pure**, sans DB) : parsing CSV `|`-séparé ; fusion **additive**
de `secondary_themes` (jamais d'effacement sans --allow-shrink) ; retrait du
thème primaire des secondary ; thème primaire inchangé si `proposed_theme` vide ;
no-op idempotent ; rejet des slugs hors taxonomie ; source introuvable.
"""

from __future__ import annotations

from uuid import uuid4

from scripts.apply_source_reclassification import (
    Proposal,
    _merge_secondary,
    _split_themes,
    compute_changes,
    load_proposals,
)


def test_split_themes_pipe_dedup_and_trim():
    assert _split_themes("science|environment") == ["science", "environment"]
    assert _split_themes(" science | science |tech") == ["science", "tech"]
    assert _split_themes("") == []
    assert _split_themes(None) == []


def test_merge_secondary_additive_and_strips_primary():
    # additif : conserve l'existant + ajoute, retire le primaire, trié.
    out = _merge_secondary(["politics"], ["science"], "society", allow_shrink=False)
    assert out == ["politics", "science"]
    # le thème primaire ne doit jamais figurer dans les secondary.
    out = _merge_secondary(["society"], ["science"], "society", allow_shrink=False)
    assert out == ["science"]


def test_merge_secondary_allow_shrink_forces_proposed():
    out = _merge_secondary(
        ["politics", "economy"], ["science"], "society", allow_shrink=True
    )
    assert out == ["science"]


def _current(sid, *, theme="society", secondary=None, name="Src"):
    return {sid: {"name": name, "theme": theme, "secondary_themes": secondary}}


def test_compute_additive_change_keeps_primary():
    sid = str(uuid4())
    props = [
        Proposal(
            sid, "Fouloscopie", proposed_theme="society", proposed_secondary=["science"]
        )
    ]
    res = compute_changes(props, _current(sid, theme="society", secondary=None))
    assert len(res.writes) == 1
    w = res.writes[0]
    assert w.new["theme"] == "society"
    assert w.new["secondary_themes"] == ["science"]
    assert w.old["secondary_themes"] == []


def test_compute_preserves_existing_secondary():
    sid = str(uuid4())
    props = [Proposal(sid, "X", proposed_theme=None, proposed_secondary=["politics"])]
    res = compute_changes(props, _current(sid, theme="society", secondary=["economy"]))
    assert res.writes[0].new["secondary_themes"] == ["economy", "politics"]
    # proposed_theme vide -> primaire inchangé
    assert res.writes[0].new["theme"] == "society"


def test_compute_noop_when_already_present():
    sid = str(uuid4())
    props = [
        Proposal(sid, "X", proposed_theme="society", proposed_secondary=["science"])
    ]
    res = compute_changes(props, _current(sid, theme="society", secondary=["science"]))
    assert res.writes == []  # idempotent


def test_compute_rejects_invalid_theme():
    sid = str(uuid4())
    props = [Proposal(sid, "Bad", proposed_theme=None, proposed_secondary=["sciencx"])]
    res = compute_changes(props, _current(sid))
    assert res.writes == []
    assert len(res.invalid_theme) == 1


def test_compute_skips_missing_source():
    props = [
        Proposal(
            str(uuid4()), "Ghost", proposed_theme=None, proposed_secondary=["science"]
        )
    ]
    res = compute_changes(props, {})
    assert res.writes == []
    assert len(res.skipped_missing) == 1


def test_load_proposals_parses_csv(tmp_path):
    csv = tmp_path / "r.csv"
    csv.write_text(
        "source_id,name,current_theme,proposed_theme,proposed_secondary_themes,"
        "target_poor_theme,rationale,sources_consulted\n"
        "abc,Fouloscopie,society,society,science,science,why,http://x\n"
        ",skipme,,,,,,,\n"
    )
    props = load_proposals(csv)
    assert len(props) == 1
    assert props[0].source_id == "abc"
    assert props[0].proposed_secondary == ["science"]
