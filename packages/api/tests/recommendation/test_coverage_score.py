"""Tests for the shared coverage_score helper."""

import math

import pytest

from app.services.recommendation.helpers.coverage_score import compute_coverage_score
from app.services.recommendation.scoring_config import ScoringWeights


def test_singleton_cluster_no_bonus():
    assert compute_coverage_score(0) == 0.0
    assert compute_coverage_score(1) == 0.0


def test_log2_progression():
    assert compute_coverage_score(2) == pytest.approx(ScoringWeights.COVERAGE_BASE)
    assert compute_coverage_score(3) == pytest.approx(
        ScoringWeights.COVERAGE_BASE * math.log2(3)
    )
    assert compute_coverage_score(4) == pytest.approx(
        ScoringWeights.COVERAGE_BASE * 2
    )


def test_capped_at_max():
    assert compute_coverage_score(6) == pytest.approx(ScoringWeights.COVERAGE_CAP)
    assert compute_coverage_score(50) == pytest.approx(ScoringWeights.COVERAGE_CAP)


def test_monotone_increasing():
    """Plus de sources → score >= ; jamais en régression."""
    values = [compute_coverage_score(n) for n in range(1, 10)]
    for prev, cur in zip(values, values[1:], strict=False):
        assert cur >= prev
