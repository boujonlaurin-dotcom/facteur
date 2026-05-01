"""Prochain `next_scheduled_at` d'une veille — fonction pure (no DB, no I/O).

Cadences :
- weekly / biweekly : prochain `day_of_week` à `delivery_hour` (heure locale).
- monthly           : le 1er du mois à `delivery_hour` (`day_of_week` ignoré).

Les datetimes d'entrée doivent être timezone-aware ; le retour est UTC.
"""

from __future__ import annotations

from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

from app.models.veille import VeilleFrequency


def compute_next_scheduled_at(
    frequency: VeilleFrequency | str,
    day_of_week: int | None,
    delivery_hour: int,
    timezone: str,
    last_delivered_at: datetime | None,
    now: datetime,
) -> datetime:
    """Calcule le prochain horaire de livraison d'une veille (UTC).

    Args:
        frequency: 'weekly' | 'biweekly' | 'monthly'.
        day_of_week: 0–6 (lundi=0). Requis pour weekly/biweekly, ignoré pour monthly.
        delivery_hour: 0–23 (heure locale dans `timezone`).
        timezone: ex. 'Europe/Paris'. Utilisé pour le calcul jour/heure.
        last_delivered_at: datetime aware de la dernière livraison réussie,
            ou None si jamais livrée.
        now: datetime aware (référence "maintenant").

    Returns:
        datetime aware en UTC du prochain horaire de livraison.

    Raises:
        ValueError: si la fréquence est inconnue, ou si day_of_week est requis
            mais absent (weekly/biweekly), ou si delivery_hour hors [0,23].
    """
    if not 0 <= delivery_hour <= 23:
        raise ValueError(f"delivery_hour hors [0,23]: {delivery_hour}")

    freq = frequency.value if isinstance(frequency, VeilleFrequency) else str(frequency)
    tz = ZoneInfo(timezone)

    # On travaille en heure locale, on retourne en UTC.
    now_local = now.astimezone(tz)
    last_local = last_delivered_at.astimezone(tz) if last_delivered_at else None

    if freq == VeilleFrequency.MONTHLY.value:
        target_local = _next_monthly(now_local, last_local, delivery_hour, tz)
    elif freq in (
        VeilleFrequency.WEEKLY.value,
        VeilleFrequency.BIWEEKLY.value,
    ):
        if day_of_week is None or not 0 <= day_of_week <= 6:
            raise ValueError(f"day_of_week (0–6) requis pour {freq}: {day_of_week!r}")
        step_days = 7 if freq == VeilleFrequency.WEEKLY.value else 14
        target_local = _next_weekly_or_biweekly(
            now_local, last_local, day_of_week, delivery_hour, step_days, tz
        )
    else:
        raise ValueError(f"Fréquence inconnue: {freq!r}")

    return target_local.astimezone(UTC)


def _next_weekly_or_biweekly(
    now_local: datetime,
    last_local: datetime | None,
    day_of_week: int,
    delivery_hour: int,
    step_days: int,
    tz: ZoneInfo,
) -> datetime:
    """Prochaine occurrence weekly ou biweekly en heure locale."""
    if last_local is None:
        # Jamais livré : prochain `day_of_week` à `delivery_hour` ≥ now.
        candidate = _snap_to_dow(now_local.date(), day_of_week, delivery_hour, tz)
        if candidate <= now_local:
            candidate = candidate + timedelta(days=7)
        return candidate

    # Déjà livré : last + step, snappé au day_of_week à delivery_hour, et
    # au moins après now_local (en cas de retard du job).
    candidate_date = (last_local + timedelta(days=step_days)).date()
    candidate = _snap_to_dow(candidate_date, day_of_week, delivery_hour, tz)
    while candidate <= now_local:
        candidate = candidate + timedelta(days=step_days)
    return candidate


def _next_monthly(
    now_local: datetime,
    last_local: datetime | None,
    delivery_hour: int,
    tz: ZoneInfo,
) -> datetime:
    """Prochain 1er du mois à `delivery_hour` en heure locale."""
    base = last_local or now_local
    year, month = base.year, base.month
    if last_local is None:
        # Si on n'a jamais livré et qu'on est avant le 1er à delivery_hour
        # ce mois-ci, on tire ce mois-ci ; sinon on passe au mois suivant.
        candidate = datetime.combine(
            base.date().replace(day=1), time(hour=delivery_hour), tzinfo=tz
        )
        if candidate > now_local:
            return candidate

    # Avancer au mois suivant.
    if month == 12:
        year, month = year + 1, 1
    else:
        month += 1
    candidate = datetime.combine(
        base.date().replace(year=year, month=month, day=1),
        time(hour=delivery_hour),
        tzinfo=tz,
    )
    while candidate <= now_local:
        if month == 12:
            year, month = year + 1, 1
        else:
            month += 1
        candidate = datetime.combine(
            base.date().replace(year=year, month=month, day=1),
            time(hour=delivery_hour),
            tzinfo=tz,
        )
    return candidate


def _snap_to_dow(
    base_date,
    target_dow: int,
    hour: int,
    tz: ZoneInfo,
) -> datetime:
    """Retourne le datetime aware au prochain `target_dow` ≥ `base_date` à `hour`."""
    current_dow = base_date.weekday()
    delta = (target_dow - current_dow) % 7
    target = base_date + timedelta(days=delta)
    return datetime.combine(target, time(hour=hour), tzinfo=tz)
