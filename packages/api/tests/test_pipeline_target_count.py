"""Contrat env-var pour le passage 5 → 10 sujets.

Les hyper-paramètres `target_subject_count` et `_SUBJECT_BUFFER` sont
maintenant lus depuis les variables d'environnement
`EDITORIAL_TARGET_SUBJECT_COUNT` / `EDITORIAL_SUBJECT_BUFFER`. Le defaut est
10 / 4 ; un override `=5` ramène au comportement antérieur pour rollback safe.
"""

from __future__ import annotations

from unittest.mock import patch

from app.services.editorial.pipeline import (
    _DEFAULT_SUBJECT_BUFFER,
    _DEFAULT_TARGET_SUBJECT_COUNT,
    _read_subject_buffer,
    _read_target_subject_count,
)


def test_default_target_subject_count_is_ten():
    assert _DEFAULT_TARGET_SUBJECT_COUNT == 10


def test_default_subject_buffer_is_four():
    assert _DEFAULT_SUBJECT_BUFFER == 4


def test_target_count_uses_default_when_env_unset():
    with patch.dict("os.environ", {}, clear=False):
        # On retire la variable si elle existe au cas où.
        import os

        os.environ.pop("EDITORIAL_TARGET_SUBJECT_COUNT", None)
        assert _read_target_subject_count() == 10


def test_target_count_honors_env_override():
    with patch.dict(
        "os.environ", {"EDITORIAL_TARGET_SUBJECT_COUNT": "5"}, clear=False
    ):
        assert _read_target_subject_count() == 5


def test_target_count_invalid_env_falls_back_to_default():
    with patch.dict(
        "os.environ", {"EDITORIAL_TARGET_SUBJECT_COUNT": "not-a-number"},
        clear=False,
    ):
        assert _read_target_subject_count() == 10


def test_target_count_floor_is_one():
    """Even with EDITORIAL_TARGET_SUBJECT_COUNT=0 we must keep >=1 subject."""
    with patch.dict(
        "os.environ", {"EDITORIAL_TARGET_SUBJECT_COUNT": "0"}, clear=False
    ):
        assert _read_target_subject_count() >= 1


def test_subject_buffer_uses_default_when_env_unset():
    import os

    os.environ.pop("EDITORIAL_SUBJECT_BUFFER", None)
    assert _read_subject_buffer() == 4


def test_subject_buffer_honors_env_override():
    with patch.dict("os.environ", {"EDITORIAL_SUBJECT_BUFFER": "3"}, clear=False):
        assert _read_subject_buffer() == 3


def test_subject_buffer_invalid_env_falls_back_to_default():
    with patch.dict(
        "os.environ", {"EDITORIAL_SUBJECT_BUFFER": "abc"}, clear=False
    ):
        assert _read_subject_buffer() == 4


def test_subject_buffer_floor_is_zero():
    with patch.dict("os.environ", {"EDITORIAL_SUBJECT_BUFFER": "-5"}, clear=False):
        assert _read_subject_buffer() == 0


def test_oversample_count_with_a_la_une_at_default():
    """Quand À la Une est sélectionnée, on demande (target-1) + buffer topics."""
    target = _read_target_subject_count()  # 10
    buffer = _read_subject_buffer()  # 4
    remaining = target - 1
    oversample = remaining + buffer
    assert oversample == 13


def test_oversample_count_legacy_5_rollback():
    """Avec rollback EDITORIAL_TARGET_SUBJECT_COUNT=5 + buffer=2,
    l'oversample doit redescendre à 6 (= ancien comportement)."""
    with patch.dict(
        "os.environ",
        {
            "EDITORIAL_TARGET_SUBJECT_COUNT": "5",
            "EDITORIAL_SUBJECT_BUFFER": "2",
        },
        clear=False,
    ):
        target = _read_target_subject_count()
        buffer = _read_subject_buffer()
        assert target == 5
        assert buffer == 2
        assert (target - 1) + buffer == 6
