"""Cadence des cibles d'alerte — le devis de bruit qui remplace le gate (30.3)."""

from datetime import UTC, datetime, timedelta

from app.services.alert_cadence import (
    cadence_per_week,
    cadence_phrase,
    expected_alerts_phrase,
    is_noisy,
)

NOW = datetime(2026, 7, 26, 12, 0, tzinfo=UTC)
MONTH = NOW - timedelta(days=30)


def test_cadence_per_week_uses_the_full_window_by_default():
    assert cadence_per_week(30, MONTH, NOW) == 7.0


def test_fresh_target_is_not_underestimated_by_the_clamp():
    """3 articles en 2 jours = quotidien, pas « une fois par mois ».

    Sans le clamp sur l'âge réel, la fenêtre de 30 j diluerait le volume et le
    devis de bruit promettrait le calme à l'utilisateur.
    """
    assert cadence_per_week(3, NOW - timedelta(days=2), NOW) > 7.0


def test_noisy_starts_above_three_per_week():
    assert is_noisy(12, MONTH, NOW) is False  # 2,8 / semaine
    assert is_noisy(14, MONTH, NOW) is True  # 3,3 / semaine


def test_cadence_phrase_adapts_its_unit_to_the_rhythm():
    assert cadence_phrase(0, MONTH, NOW) == "Publie rarement"
    assert cadence_phrase(1, MONTH, NOW) == "Publie environ une fois par mois"
    assert cadence_phrase(4, MONTH, NOW) == "Publie environ une fois par semaine"
    assert cadence_phrase(10, MONTH, NOW) == "Publie environ 2 fois par semaine"
    assert cadence_phrase(30, MONTH, NOW) == "Publie environ une fois par jour"
    assert cadence_phrase(150, MONTH, NOW) == "Publie environ 5 fois par jour"


def test_expected_alerts_phrase_is_the_honest_quote():
    # 12 articles / 30 j ≈ 2,8 / semaine.
    assert expected_alerts_phrase(12, MONTH, NOW) == "Environ 3 alertes par semaine"
    # 150 articles / 30 j = 5 / jour.
    assert expected_alerts_phrase(150, MONTH, NOW) == "Environ 5 alertes par jour"
