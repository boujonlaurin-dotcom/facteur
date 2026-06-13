"""Tests for the shared diversify helper."""

from app.services.recommendation.helpers.diversification import diversify


def test_empty_input():
    assert diversify([], key_fn=lambda x: x) == []


def test_strict_dedup_one_per_key():
    items = [("a", 1), ("a", 2), ("b", 3), ("c", 4), ("a", 5)]
    out = diversify(items, key_fn=lambda x: x[0], target_size=None, max_per_key=1)
    assert out == [("a", 1), ("b", 3), ("c", 4)]


def test_souple_fallback_when_target_not_met():
    """Si on n'a pas assez de clés distinctes, on rajoute des doublons par
    ordre original pour atteindre la cible."""
    items = [("a", 1), ("a", 2), ("a", 3), ("b", 4)]
    out = diversify(
        items, key_fn=lambda x: x[0], target_size=3, max_per_key=1, fallback_ok=True
    )
    assert out == [("a", 1), ("b", 4), ("a", 2)]


def test_strict_no_fallback():
    items = [("a", 1), ("a", 2), ("b", 3)]
    out = diversify(
        items,
        key_fn=lambda x: x[0],
        target_size=5,
        max_per_key=1,
        fallback_ok=False,
    )
    assert out == [("a", 1), ("b", 3)]


def test_max_per_key_n():
    items = [("a", 1), ("a", 2), ("a", 3), ("b", 4)]
    out = diversify(items, key_fn=lambda x: x[0], max_per_key=2)
    assert out == [("a", 1), ("a", 2), ("b", 4)]


def test_none_keys_pass_through():
    """Une clé None signifie 'pas de groupement' — l'élément n'est pas compté."""
    items = [("a", 1), (None, 2), (None, 3), ("a", 4)]
    out = diversify(items, key_fn=lambda x: x[0], max_per_key=1)
    assert out == [("a", 1), (None, 2), (None, 3)]


def test_preserves_input_order():
    items = list(range(10))
    out = diversify(items, key_fn=lambda x: x % 3, max_per_key=1)
    assert out == [0, 1, 2]
