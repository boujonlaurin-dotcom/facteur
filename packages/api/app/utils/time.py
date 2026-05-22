"""Time utilities — centralize Paris-time computations.

The digest pipeline uses Europe/Paris for cron triggers and watchdog checks,
but several call sites used `date.today()` (UTC), which between 00:00 and 02:00
Paris (summer) returns yesterday's Paris date. This helper makes "today" mean
the same thing everywhere the digest pipeline reads or writes target_date.
"""

from datetime import date, datetime
from zoneinfo import ZoneInfo

PARIS_TZ = ZoneInfo("Europe/Paris")


def today_paris() -> date:
    """Return today's date in Europe/Paris.

    Use this anywhere the digest pipeline computes a `target_date`,
    so reader and batch agree on which day's digest is "today".
    """
    return datetime.now(PARIS_TZ).date()


def now_paris() -> datetime:
    """Return current datetime in Europe/Paris (timezone-aware)."""
    return datetime.now(PARIS_TZ)


def is_before_paris_time(now: datetime, hour: int, minute: int) -> bool:
    """True if `now` (Paris-time) is strictly before `hour:minute` on its own day.

    Centralizes the "skip if too early" guard used by the digest cron startup
    catchup (`main.py`) and the on-request background regen scheduler
    (`digest_service.py`). Both must refuse to generate today's digest before
    the morning batch — otherwise the pool of articles is saturated by the
    previous evening's edition and the morning's Unes aren't published yet.
    """
    return now.hour * 60 + now.minute < hour * 60 + minute
