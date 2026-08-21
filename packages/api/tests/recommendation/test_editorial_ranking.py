"""Tests du helper de classement par importance éditoriale et score mixte.

Cf. bug-actus-du-jour-ranking.md (Partie C) et
bug-curation-essentiel-personnalisation.md (PR 4).
"""

from datetime import UTC, datetime, timedelta

from app.services.recommendation.helpers.editorial_ranking import (
    editorial_importance,
    importance_raw_cap,
    mixed_subject_score,
    normalized_importance,
    normalized_perso,
    polarization_bonus,
    recency_bonus,
)
from app.services.recommendation.scoring_config import ScoringWeights


class TestRecencyBonus:
    def test_none_is_zero(self):
        assert recency_bonus(None) == 0.0

    def test_very_recent(self):
        now = datetime.now(UTC) - timedelta(hours=1)
        assert recency_bonus(now) == ScoringWeights.RECENT_VERY_BONUS

    def test_today(self):
        ts = datetime.now(UTC) - timedelta(hours=30)
        assert recency_bonus(ts) == ScoringWeights.RECENT_DAY_BONUS

    def test_naive_datetime_treated_as_utc(self):
        naive = datetime.now() - timedelta(hours=1)  # noqa: DTZ005
        assert recency_bonus(naive) == ScoringWeights.RECENT_VERY_BONUS

    def test_old_is_zero(self):
        ts = datetime.now(UTC) - timedelta(days=10)
        assert recency_bonus(ts) == 0.0


class TestPolarizationBonus:
    def test_high(self):
        assert polarization_bonus("high") == ScoringWeights.POLARIZATION_HIGH_BONUS

    def test_medium(self):
        assert polarization_bonus("medium") == ScoringWeights.POLARIZATION_MEDIUM_BONUS

    def test_low_and_none_are_zero(self):
        assert polarization_bonus("low") == 0.0
        assert polarization_bonus("none") == 0.0
        assert polarization_bonus(None) == 0.0

    def test_case_insensitive(self):
        assert polarization_bonus("HIGH") == ScoringWeights.POLARIZATION_HIGH_BONUS


class TestRecencyBonusFrozenNow:
    def test_now_freezes_the_reference(self):
        """`now` explicite → rejeu déterministe (dry-run sur snapshots)."""
        now = datetime(2026, 8, 1, 12, 0, tzinfo=UTC)
        published = now - timedelta(hours=3)
        assert recency_bonus(published, now=now) == ScoringWeights.RECENT_VERY_BONUS
        # Même article, référence 40h plus tard → palier < 48h.
        later = now + timedelta(hours=40)
        assert recency_bonus(published, now=later) == ScoringWeights.RECENT_DAY_BONUS


class TestNormalizedImportance:
    def test_bounded_0_100(self):
        now = datetime(2026, 8, 1, 12, 0, tzinfo=UTC)
        # Maximum simultané : cap couverture + très récent + polarisé high.
        top = normalized_importance(10, now - timedelta(hours=1), "high", now=now)
        assert top == 100.0
        # Minimum : solo, vieux, sans polarisation.
        floor = normalized_importance(1, now - timedelta(days=30), None, now=now)
        assert floor == 0.0

    def test_cap_is_derived_from_weights_at_call_time(self, monkeypatch):
        """Le cap suit les poids : monkeypatcher COVERAGE_CAP le déplace."""
        base_cap = importance_raw_cap()
        monkeypatch.setattr(ScoringWeights, "COVERAGE_CAP", 60.0)
        assert importance_raw_cap() == base_cap + 30.0

    def test_matches_raw_over_cap(self):
        now = datetime(2026, 8, 1, 12, 0, tzinfo=UTC)
        published = now - timedelta(hours=30)
        raw = editorial_importance(3, published, "medium", now=now)
        expected = 100.0 * raw / importance_raw_cap()
        assert normalized_importance(3, published, "medium", now=now) == expected


class TestNormalizedPerso:
    def test_none_falls_back_to_neutral(self):
        assert normalized_perso(None) == 0.0
        assert normalized_perso(None, neutral=42.0) == 42.0

    def test_negative_engine_score_is_clamped(self):
        """Le PenaltyPass peut produire du négatif — jamais propagé au mélange."""
        assert normalized_perso(-80.0) == 0.0

    def test_above_100_is_clamped(self):
        assert normalized_perso(140.0) == 100.0


class TestMixedSubjectScore:
    def test_weighted_blend(self):
        w = ScoringWeights.SUBJECT_PERSO_WEIGHT
        assert mixed_subject_score(100.0, 0.0) == (1.0 - w) * 100.0
        assert mixed_subject_score(0.0, 100.0) == w * 100.0

    def test_weight_read_at_call_time(self, monkeypatch):
        """Même mécanique que SCORING_OVERRIDES : le poids n'est jamais copié."""
        monkeypatch.setattr(ScoringWeights, "SUBJECT_PERSO_WEIGHT", 0.0)
        assert mixed_subject_score(80.0, 100.0) == 80.0
        monkeypatch.setattr(ScoringWeights, "SUBJECT_PERSO_WEIGHT", 1.0)
        assert mixed_subject_score(80.0, 100.0) == 100.0
