"""Time utilities — centralize Paris-time computations.

The digest pipeline uses Europe/Paris for cron triggers and watchdog checks,
but several call sites used `date.today()` (UTC), which between 00:00 and 02:00
Paris (summer) returns yesterday's Paris date. This helper makes "today" mean
the same thing everywhere the digest pipeline reads or writes target_date.
"""

from datetime import date, datetime, timedelta
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


def week_start_paris(day: date | None = None) -> date:
    """Return the Monday of `day`'s ISO week, `today_paris()` by default.

    La règle « la semaine commence lundi, en heure de Paris » était recopiée
    à trois endroits (`streak_service` ×2, `digest_service`) : sur un
    `date.today()` UTC, le reset hebdomadaire basculait une à deux heures trop
    tôt le lundi matin côté lecteur. Une seule définition évite que le prochain
    correctif de fuseau ait à les retrouver toutes.
    """
    day = day or today_paris()
    return day - timedelta(days=day.weekday())


# Editorial day boundary: the "tournée" flips at 07h30 Paris, not at midnight.
# Mirror of `TourneeProgressService.dayKey` (mobile). Kept in one place so the
# daily reading goal, the closure streak and the implicit digest completion all
# agree on what "today" means for the reader.
EDITORIAL_DAY_START_HOUR = 7
EDITORIAL_DAY_START_MINUTE = 30


def editorial_day(now: datetime | None = None) -> date:
    """Return the editorial day (07h30 Europe/Paris boundary) for `now`.

    Before 07h30 Paris the reader is still on yesterday's edition, so the day
    key stays on the previous date. Use this — never `date.today()` — anywhere
    a counter or a streak must line up with what the user sees as "today's
    edition".
    """
    moment = now.astimezone(PARIS_TZ) if now is not None else datetime.now(PARIS_TZ)
    if is_before_paris_time(
        moment, EDITORIAL_DAY_START_HOUR, EDITORIAL_DAY_START_MINUTE
    ):
        return moment.date() - timedelta(days=1)
    return moment.date()


def editorial_day_bounds(now: datetime | None = None) -> tuple[datetime, datetime]:
    """Return the [start, end) datetimes framing the current editorial day.

    Both bounds are timezone-aware (Europe/Paris) so they can be compared
    directly against `timestamptz` columns.
    """
    day = editorial_day(now)
    start = datetime(
        day.year,
        day.month,
        day.day,
        EDITORIAL_DAY_START_HOUR,
        EDITORIAL_DAY_START_MINUTE,
        tzinfo=PARIS_TZ,
    )
    return start, start + timedelta(days=1)


def is_before_paris_time(now: datetime, hour: int, minute: int) -> bool:
    """True if `now` (Paris-time) is strictly before `hour:minute` on its own day.

    Centralizes the "skip if too early" guard used by the digest cron startup
    catchup (`main.py`) and the on-request background regen scheduler
    (`digest_service.py`). Both must refuse to generate today's digest before
    the morning batch — otherwise the pool of articles is saturated by the
    previous evening's edition and the morning's Unes aren't published yet.
    """
    return now.hour * 60 + now.minute < hour * 60 + minute
