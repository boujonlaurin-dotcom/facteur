"""Tests pour scripts/fix_source_metadata.py.

Couvre la logique **pure** (`compute_changes`, sans DB) : diff champ par champ,
no-op idempotent, garde-fou `expected_name`, source introuvable, et l'intégrité
de la table `CORRECTIONS` elle-même (pas de doublon, pas de champ hors
`MUTABLE_FIELDS`, chaque ligne porte au moins une correction et une preuve).
"""

from __future__ import annotations

from uuid import uuid4

import pytest

from scripts.fix_source_metadata import (
    CORRECTIONS,
    MUTABLE_FIELDS,
    Correction,
    compute_changes,
)


def _corr(sid: str, **kwargs) -> Correction:
    kwargs.setdefault("expected_name", "Src")
    kwargs.setdefault("evidence", "preuve")
    return Correction(source_id=sid, **kwargs)


def _current(sid: str, *, name="Src", language=None, theme="society"):
    return {sid: {"name": name, "language": language, "theme": theme}}


def test_diff_only_reports_fields_that_actually_change():
    sid = str(uuid4())
    plan = compute_changes(
        [_corr(sid, language="fr", theme="sport")],
        _current(sid, language="en", theme="sport"),
    )
    assert len(plan.writes) == 1
    # `theme` est déjà bon -> absent du diff ; seul `language` est écrit.
    assert plan.writes[0].changes == {"language": ("en", "fr")}


def test_noop_when_already_correct_is_idempotent():
    sid = str(uuid4())
    plan = compute_changes(
        [_corr(sid, language="fr", theme="sport")],
        _current(sid, language="fr", theme="sport"),
    )
    assert plan.writes == []
    assert plan.noop == ["Src"]


def test_null_language_is_a_real_change():
    sid = str(uuid4())
    plan = compute_changes([_corr(sid, language="fr")], _current(sid, language=None))
    assert plan.writes[0].changes == {"language": (None, "fr")}


def test_rename_writes_name_field():
    sid = str(uuid4())
    plan = compute_changes(
        [_corr(sid, expected_name="Home Fil actu", name="BFMTV", language="fr")],
        _current(sid, name="Home Fil actu", language="en"),
    )
    assert plan.writes[0].changes["name"] == ("Home Fil actu", "BFMTV")


def test_expected_name_mismatch_is_refused_not_written():
    """Garde-fou : la source a été renommée depuis l'audit -> on n'écrit pas."""
    sid = str(uuid4())
    plan = compute_changes(
        [_corr(sid, expected_name="Ancien nom", language="fr")],
        _current(sid, name="Nouveau nom", language="en"),
    )
    assert plan.writes == []
    assert len(plan.renamed) == 1
    assert "Ancien nom" in plan.renamed[0]


def test_missing_source_is_reported_not_written():
    plan = compute_changes([_corr(str(uuid4()), language="fr")], {})
    assert plan.writes == []
    assert len(plan.missing) == 1


def test_desired_ignores_untouched_fields():
    c = _corr(str(uuid4()), language="fr")
    assert c.desired() == {"language": "fr"}


# --- intégrité de la table livrée -----------------------------------------


def test_corrections_table_has_no_duplicate_ids():
    ids = [c.source_id for c in CORRECTIONS]
    assert len(ids) == len(set(ids))


@pytest.mark.parametrize("corr", CORRECTIONS, ids=lambda c: c.expected_name)
def test_each_correction_is_actionable_and_documented(corr: Correction):
    desired = corr.desired()
    assert desired, f"{corr.expected_name} ne corrige aucun champ"
    assert set(desired) <= set(MUTABLE_FIELDS)
    assert corr.evidence.strip(), f"{corr.expected_name} n'a pas de preuve"


def test_table_applied_twice_is_a_noop():
    """Idempotence de bout en bout sur la vraie table : après application, un
    second run ne produit plus aucune écriture."""
    after = {
        c.source_id: {
            "name": c.name or c.expected_name,
            "language": None,
            "theme": None,
        }
        | c.desired()
        for c in CORRECTIONS
    }
    plan = compute_changes(CORRECTIONS, after)
    assert plan.writes == []
    assert plan.renamed == []
    assert plan.missing == []
    assert len(plan.noop) == len(CORRECTIONS)
