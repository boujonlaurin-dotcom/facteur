"""Tests du helper de classement par importance éditoriale.

Cf. bug-actus-du-jour-ranking.md (Partie C).
"""

from datetime import UTC, datetime, timedelta

from app.services.recommendation.helpers.editorial_ranking import (
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
