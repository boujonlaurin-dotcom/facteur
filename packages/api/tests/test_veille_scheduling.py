"""Tests pour `compute_next_scheduled_at` (Story 18.1).

Fonction pure, pas de DB. Couvre :
- weekly / biweekly / monthly, jamais livré + déjà livré.
- DST Paris (passage heure d'été) : l'heure locale 7:00 reste 7:00.
- Validation des entrées (frequency / day_of_week / delivery_hour).
"""

from datetime import UTC, datetime
from zoneinfo import ZoneInfo

import pytest

from app.models.veille import VeilleFrequency
from app.services.veille.scheduling import compute_next_scheduled_at

PARIS = ZoneInfo("Europe/Paris")


def _utc(year: int, month: int, day: int, hour: int = 0, minute: int = 0) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=UTC)


def _paris(year: int, month: int, day: int, hour: int = 0) -> datetime:
    return datetime(year, month, day, hour, tzinfo=PARIS)


class TestWeeklyNeverDelivered:
    def test_today_before_delivery_hour(self):
        # Lundi 2026-05-04 06:00 UTC = 08:00 Paris (avant 7? Non, après).
        # Tirons un cas net : Lundi 2026-05-04 03:00 Paris, livre à 07:00 Lundi.
        now = _paris(2026, 5, 4, 3)  # lundi 03:00 Paris
        result = compute_next_scheduled_at(
            VeilleFrequency.WEEKLY,
            day_of_week=0,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=None,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2026, 5, 4, 7)

    def test_today_after_delivery_hour(self):
        # Lundi 2026-05-04 09:00 Paris : la livraison de 7h est passée → semaine prochaine.
        now = _paris(2026, 5, 4, 9)
        result = compute_next_scheduled_at(
            VeilleFrequency.WEEKLY,
            day_of_week=0,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=None,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2026, 5, 11, 7)

    def test_not_on_day_of_week(self):
        # Mercredi 2026-05-06, on veut le prochain lundi (= 2026-05-11).
        now = _paris(2026, 5, 6, 10)
        result = compute_next_scheduled_at(
            VeilleFrequency.WEEKLY,
            day_of_week=0,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=None,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2026, 5, 11, 7)


class TestWeeklyAlreadyDelivered:
    def test_plus_seven_days(self):
        # Livré lundi 2026-05-04 07:00 Paris → prochain lundi 2026-05-11 07:00.
        last = _paris(2026, 5, 4, 7)
        now = _paris(2026, 5, 4, 8)
        result = compute_next_scheduled_at(
            VeilleFrequency.WEEKLY,
            day_of_week=0,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=last,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2026, 5, 11, 7)

    def test_skip_if_now_past_candidate(self):
        # Livré lundi 2026-05-04, mais le scanner a 1 mois de retard
        # (now = 2026-06-08 = lundi). Le prochain doit être ≥ now.
        last = _paris(2026, 5, 4, 7)
        now = _paris(2026, 6, 8, 9)  # lundi 09:00, après 7:00
        result = compute_next_scheduled_at(
            VeilleFrequency.WEEKLY,
            day_of_week=0,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=last,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2026, 6, 15, 7)


class TestBiweekly:
    def test_plus_fourteen_days(self):
        last = _paris(2026, 5, 4, 7)
        now = _paris(2026, 5, 4, 8)
        result = compute_next_scheduled_at(
            VeilleFrequency.BIWEEKLY,
            day_of_week=0,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=last,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2026, 5, 18, 7)


class TestMonthly:
    def test_never_delivered_before_first(self):
        # 2026-05-01 03:00 Paris (avant 7h le 1er) → tire le 1er à 7h.
        now = _paris(2026, 5, 1, 3)
        result = compute_next_scheduled_at(
            VeilleFrequency.MONTHLY,
            day_of_week=None,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=None,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2026, 5, 1, 7)

    def test_never_delivered_after_first(self):
        # 2026-05-15 → tire le 1er juin à 7h.
        now = _paris(2026, 5, 15, 12)
        result = compute_next_scheduled_at(
            VeilleFrequency.MONTHLY,
            day_of_week=None,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=None,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2026, 6, 1, 7)

    def test_already_delivered(self):
        last = _paris(2026, 5, 1, 7)
        now = _paris(2026, 5, 2, 10)
        result = compute_next_scheduled_at(
            VeilleFrequency.MONTHLY,
            day_of_week=None,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=last,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2026, 6, 1, 7)

    def test_year_rollover(self):
        # Livré 2026-12-01 → prochain 2027-01-01.
        last = _paris(2026, 12, 1, 7)
        now = _paris(2026, 12, 1, 8)
        result = compute_next_scheduled_at(
            VeilleFrequency.MONTHLY,
            day_of_week=None,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=last,
            now=now,
        )
        assert result.astimezone(PARIS) == _paris(2027, 1, 1, 7)


class TestDST:
    def test_paris_spring_forward_keeps_local_seven(self):
        # Le 30 mars 2025 le passage à l'heure d'été : 02:00 → 03:00.
        # On veut que la livraison hebdo à 07:00 Paris reste 07:00 Paris,
        # même si l'offset UTC change (UTC+1 → UTC+2).
        last = _paris(2025, 3, 24, 7)  # lundi 24 mars (UTC+1)
        now = _paris(2025, 3, 24, 8)
        result = compute_next_scheduled_at(
            VeilleFrequency.WEEKLY,
            day_of_week=0,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=last,
            now=now,
        )
        # Lundi 31 mars à 07:00 Paris = 05:00 UTC (UTC+2 en été).
        assert result.astimezone(PARIS) == _paris(2025, 3, 31, 7)
        assert result == _utc(2025, 3, 31, 5)


class TestValidation:
    def test_invalid_frequency_raises(self):
        with pytest.raises(ValueError, match="Fréquence inconnue"):
            compute_next_scheduled_at(
                "yearly",
                day_of_week=0,
                delivery_hour=7,
                timezone="Europe/Paris",
                last_delivered_at=None,
                now=_paris(2026, 5, 1),
            )

    def test_missing_dow_for_weekly_raises(self):
        with pytest.raises(ValueError, match="day_of_week"):
            compute_next_scheduled_at(
                VeilleFrequency.WEEKLY,
                day_of_week=None,
                delivery_hour=7,
                timezone="Europe/Paris",
                last_delivered_at=None,
                now=_paris(2026, 5, 1),
            )

    def test_invalid_dow_raises(self):
        with pytest.raises(ValueError, match="day_of_week"):
            compute_next_scheduled_at(
                VeilleFrequency.WEEKLY,
                day_of_week=9,
                delivery_hour=7,
                timezone="Europe/Paris",
                last_delivered_at=None,
                now=_paris(2026, 5, 1),
            )

    def test_invalid_hour_raises(self):
        with pytest.raises(ValueError, match="delivery_hour"):
            compute_next_scheduled_at(
                VeilleFrequency.WEEKLY,
                day_of_week=0,
                delivery_hour=25,
                timezone="Europe/Paris",
                last_delivered_at=None,
                now=_paris(2026, 5, 1),
            )

    def test_monthly_ignores_dow(self):
        # Pas d'erreur même si day_of_week=None pour monthly.
        result = compute_next_scheduled_at(
            VeilleFrequency.MONTHLY,
            day_of_week=None,
            delivery_hour=7,
            timezone="Europe/Paris",
            last_delivered_at=None,
            now=_paris(2026, 5, 15, 12),
        )
        assert result.astimezone(PARIS) == _paris(2026, 6, 1, 7)
