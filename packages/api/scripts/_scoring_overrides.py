"""Contexte de sweep partagé pour les harnais de tuning du scoring.

Généralisation directe du `_threshold_override` de `evaluate_veille_curation.py`
(qui ne patchait que `VEILLE_RELEVANCE_THRESHOLD`) : `weights_override(**kwargs)`
patche N attributs de `ScoringWeights` le temps d'un `with`, puis restaure.

Pourquoi ça marche : les ~212 lectures de constantes en prod sont toutes de la
forme `ScoringWeights.X` **évaluée à l'appel**, jamais liée à l'avance — un
`setattr` runtime les atteint donc toutes... **sauf** celles copiées au
chargement d'un module (argument par défaut de `def`). Celles-là sont dans
`NON_PATCHABLE_AT_RUNTIME` et un sweep qui les cible **échoue bruyamment** plutôt
que de mentir par un no-op silencieux.

Miroir runtime de la surcharge d'environnement `SCORING_OVERRIDES`
(`scoring_config.py`) : même cible (`ScoringWeights`), même invariant piliers.
L'env sert le tuning/rollback *déployé* ; ce contexte sert le sweep *offline*.
"""

from __future__ import annotations

import copy
from contextlib import contextmanager

from app.services.recommendation.scoring_config import (
    ScoringWeights,
    is_overridable_scoring_key,
    pillar_weights_sum_ok,
)

# Constantes liées à une valeur **au chargement du module** (argument par défaut
# d'un `def`), donc invisibles à un `setattr` runtime : `decayed_subtopic_weight`
# (`workers/scheduler.py`) fige `decay=ScoringWeights.SUBTOPIC_DECAY` à l'import.
# Un sweep qui les cible serait un no-op silencieux → on lève.
#
# Tenu synchrone avec le code par
# `tests/scripts/test_scoring_overrides.py::test_no_new_module_bound_defaults`
# (grep AST des signatures `def … = ScoringWeights.X`). Si ce test rougit, soit
# refactorer le call site pour lire la constante à l'appel, soit ajouter le nom
# ici en connaissance de cause.
NON_PATCHABLE_AT_RUNTIME = frozenset({"SUBTOPIC_DECAY"})


def _assert_pillars_sum_to_one() -> None:
    if not pillar_weights_sum_ok(ScoringWeights.PILLAR_WEIGHTS):
        total = sum(ScoringWeights.PILLAR_WEIGHTS.values())
        raise ValueError(
            f"PILLAR_WEIGHTS doit sommer à 1.0 (reçu {total}) — override invalide."
        )


@contextmanager
def weights_override(**overrides: object):
    """Patche temporairement des attributs de `ScoringWeights`.

    - Clé inconnue (ou privée `_…`) → `ValueError` (faute de frappe = échec dur).
    - Clé dans `NON_PATCHABLE_AT_RUNTIME` → `ValueError` (le patch serait inerte).
    - `PILLAR_WEIGHTS` (dict mutable de classe) : deep-copié avant, restauré
      après, et l'invariant `sum == 1.0` est réasserté une fois tous les patchs
      posés.
    - Restauration garantie en `finally`, même si l'invariant échoue.
    """
    if not overrides:
        yield
        return

    unknown = [name for name in overrides if not is_overridable_scoring_key(name)]
    if unknown:
        raise ValueError(
            f"weights_override : constante(s) inconnue(s) de ScoringWeights {unknown}"
        )

    blocked = [name for name in overrides if name in NON_PATCHABLE_AT_RUNTIME]
    if blocked:
        raise ValueError(
            f"weights_override : {blocked} est liée au chargement du module "
            "(argument par défaut) — un setattr runtime serait un no-op silencieux. "
            "Refactorer le call site pour lire la constante à l'appel, ou promouvoir "
            "la valeur dans scoring_config.py."
        )

    originals: dict[str, object] = {}
    try:
        for name, value in overrides.items():
            current = getattr(ScoringWeights, name)
            originals[name] = (
                copy.deepcopy(current) if isinstance(current, dict) else current
            )
            setattr(ScoringWeights, name, value)
        _assert_pillars_sum_to_one()
        yield
    finally:
        for name, value in originals.items():
            setattr(ScoringWeights, name, value)
