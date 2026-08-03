"""Tests pour l'outillage de tuning du scoring (lot reco PR-2).

Couvre les deux surfaces de surcharge de `ScoringWeights` :

- **Sweep runtime** (`scripts/_scoring_overrides.py::weights_override`) :
  patch/restore, restauration sur exception, invariant piliers, garde
  `NON_PATCHABLE_AT_RUNTIME`, clé inconnue, deep-copy de `PILLAR_WEIGHTS`.
- **Surcharge d'environnement** (`scoring_config.py::_apply_env_scoring_overrides`
  + `scoring_algo_version`) : application, coercition de type, hash de version.
- **Garde anti-drift AST** : la liste des constantes liées en argument par
  défaut de `def` n'a pas grandi sans qu'on mette `NON_PATCHABLE_AT_RUNTIME` à
  jour (sinon un sweep les patcherait dans le vide).
"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest

from app.services.recommendation import scoring_config as sc
from app.services.recommendation.scoring_config import (
    ScoringWeights,
    scoring_algo_version,
)
from scripts._scoring_overrides import (
    NON_PATCHABLE_AT_RUNTIME,
    weights_override,
)

APP_ROOT = Path(__file__).resolve().parents[2] / "app"


# ---------------------------------------------------------------------------
# weights_override — sweep runtime
# ---------------------------------------------------------------------------


def test_patches_then_restores():
    original = ScoringWeights.THEME_MATCH
    with weights_override(THEME_MATCH=999.0):
        assert ScoringWeights.THEME_MATCH == 999.0
    assert original == ScoringWeights.THEME_MATCH


def test_restores_on_exception():
    original = ScoringWeights.THEME_MATCH
    with pytest.raises(RuntimeError), weights_override(THEME_MATCH=999.0):
        raise RuntimeError("boom")
    assert original == ScoringWeights.THEME_MATCH


def test_empty_override_is_noop():
    original = ScoringWeights.THEME_MATCH
    with weights_override():
        assert original == ScoringWeights.THEME_MATCH
    assert original == ScoringWeights.THEME_MATCH


def test_unknown_constant_raises():
    with (
        pytest.raises(ValueError, match="inconnue"),
        weights_override(NOT_A_REAL_CONSTANT=1.0),
    ):
        pass


def test_private_attr_rejected():
    with (
        pytest.raises(ValueError, match="inconnue"),
        weights_override(_ACTIVE_OVERRIDES={}),
    ):
        pass


def test_non_patchable_constant_raises_loudly():
    # SUBTOPIC_DECAY est figé en argument par défaut de `decayed_subtopic_weight`
    # au chargement du module : un setattr runtime serait un no-op silencieux.
    with (
        pytest.raises(ValueError, match="no-op silencieux"),
        weights_override(SUBTOPIC_DECAY=0.5),
    ):
        pass


def test_pillar_weights_deep_copied_and_restored():
    original = dict(ScoringWeights.PILLAR_WEIGHTS)
    new = {"pertinence": 0.5, "source": 0.2, "fraicheur": 0.2, "qualite": 0.1}
    with weights_override(PILLAR_WEIGHTS=new):
        assert new == ScoringWeights.PILLAR_WEIGHTS
        # Muter le dict actif ne doit pas contaminer la copie de restauration.
        ScoringWeights.PILLAR_WEIGHTS["pertinence"] = 0.99
    assert original == ScoringWeights.PILLAR_WEIGHTS


def test_pillar_weights_sum_invariant_enforced():
    original = dict(ScoringWeights.PILLAR_WEIGHTS)
    bad = {"pertinence": 0.9, "source": 0.9, "fraicheur": 0.0, "qualite": 0.0}
    with (
        pytest.raises(ValueError, match="sommer à 1.0"),
        weights_override(PILLAR_WEIGHTS=bad),
    ):
        pass
    # Restauration garantie malgré l'échec d'invariant.
    assert original == ScoringWeights.PILLAR_WEIGHTS


def test_multiple_constants_at_once():
    o_theme, o_trusted = ScoringWeights.THEME_MATCH, ScoringWeights.TRUSTED_SOURCE
    with weights_override(THEME_MATCH=1.0, TRUSTED_SOURCE=2.0):
        assert ScoringWeights.THEME_MATCH == 1.0
        assert ScoringWeights.TRUSTED_SOURCE == 2.0
    assert o_theme == ScoringWeights.THEME_MATCH
    assert o_trusted == ScoringWeights.TRUSTED_SOURCE


# ---------------------------------------------------------------------------
# SCORING_OVERRIDES — surcharge d'environnement + version
# ---------------------------------------------------------------------------


@pytest.fixture
def restore_scoring_state():
    """Snapshot/restore de l'état global patché par l'env override."""
    snapshot_active = dict(sc._ACTIVE_OVERRIDES)
    snapshot_theme = ScoringWeights.THEME_MATCH
    snapshot_pillars = dict(ScoringWeights.PILLAR_WEIGHTS)
    yield
    sc._ACTIVE_OVERRIDES.clear()
    sc._ACTIVE_OVERRIDES.update(snapshot_active)
    ScoringWeights.THEME_MATCH = snapshot_theme
    ScoringWeights.PILLAR_WEIGHTS = snapshot_pillars


def test_algo_version_plain_without_overrides():
    # Suite lancée sans SCORING_OVERRIDES : version nue, pas de suffixe.
    if not sc._ACTIVE_OVERRIDES:
        assert scoring_algo_version() == ScoringWeights.SCORING_VERSION


def test_env_override_applies_and_stamps_version(monkeypatch, restore_scoring_state):
    monkeypatch.setenv("SCORING_OVERRIDES", '{"THEME_MATCH": 42}')
    sc._ACTIVE_OVERRIDES.clear()
    sc._apply_env_scoring_overrides()

    # int JSON coercé vers float (type de la constante).
    assert ScoringWeights.THEME_MATCH == 42.0
    assert isinstance(ScoringWeights.THEME_MATCH, float)
    assert sc._ACTIVE_OVERRIDES == {"THEME_MATCH": 42.0}

    version = scoring_algo_version()
    assert version.startswith(f"{ScoringWeights.SCORING_VERSION}+ovr.")
    # Déterministe : même config → même hash.
    assert version == scoring_algo_version()


def test_env_override_unknown_key_warns_and_skips(monkeypatch, restore_scoring_state):
    monkeypatch.setenv("SCORING_OVERRIDES", '{"NOPE": 1, "THEME_MATCH": 7}')
    sc._ACTIVE_OVERRIDES.clear()
    sc._apply_env_scoring_overrides()
    assert "NOPE" not in sc._ACTIVE_OVERRIDES
    assert sc._ACTIVE_OVERRIDES == {"THEME_MATCH": 7.0}


def test_env_override_invalid_json_applies_nothing(monkeypatch, restore_scoring_state):
    original = ScoringWeights.THEME_MATCH
    monkeypatch.setenv("SCORING_OVERRIDES", "{not json")
    sc._ACTIVE_OVERRIDES.clear()
    sc._apply_env_scoring_overrides()
    assert sc._ACTIVE_OVERRIDES == {}
    assert original == ScoringWeights.THEME_MATCH


def test_env_override_pillar_bad_sum_rejected(monkeypatch, restore_scoring_state):
    original = dict(ScoringWeights.PILLAR_WEIGHTS)
    monkeypatch.setenv(
        "SCORING_OVERRIDES",
        '{"PILLAR_WEIGHTS": {"pertinence": 0.9, "source": 0.9, '
        '"fraicheur": 0.0, "qualite": 0.0}}',
    )
    sc._ACTIVE_OVERRIDES.clear()
    sc._apply_env_scoring_overrides()
    assert "PILLAR_WEIGHTS" not in sc._ACTIVE_OVERRIDES
    assert original == ScoringWeights.PILLAR_WEIGHTS


# ---------------------------------------------------------------------------
# Garde anti-drift : arguments par défaut liés à `ScoringWeights.X`
# ---------------------------------------------------------------------------


def _module_bound_default_constants() -> set[str]:
    """Grep AST : constantes `ScoringWeights.X` liées en **argument par défaut**
    d'un `def` (donc figées au chargement du module, invisibles au sweep runtime).
    """
    found: set[str] = set()
    for path in APP_ROOT.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            defaults = list(node.args.defaults) + [
                d for d in node.args.kw_defaults if d is not None
            ]
            for default in defaults:
                if (
                    isinstance(default, ast.Attribute)
                    and isinstance(default.value, ast.Name)
                    and default.value.id == "ScoringWeights"
                ):
                    found.add(default.attr)
    return found


def test_no_new_module_bound_defaults():
    """Si cette liste grandit, un sweep sur la nouvelle constante serait un
    no-op silencieux : soit refactorer le call site (lire à l'appel), soit
    ajouter le nom à `NON_PATCHABLE_AT_RUNTIME` en connaissance de cause.
    """
    assert _module_bound_default_constants() == set(NON_PATCHABLE_AT_RUNTIME)
