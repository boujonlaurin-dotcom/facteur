"""Epic 30 — « lu jusqu'au bout » : contrat de données et compteur journalier.

Trois choses à protéger :

1. `completed_at` est **first-write-wins** — relire un article ne doit jamais
   déplacer l'horodatage, sinon le compteur du jour se farme en rouvrant.
2. Complétion et transition CONSUMED ne voyagent **jamais** dans la même
   requête : l'upsert protège CONSUMED par un `ON CONFLICT ... WHERE status !=
   'consumed'` qui ignorerait l'update entier, donc `completed_at` serait perdu
   silencieusement.
3. La journée du compteur suit la frontière **07h30 Europe/Paris** (celle des
   éditions), pas minuit.

Pas de DB requise : on inspecte le SQL compilé de l'upsert.
"""

from datetime import datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4
from zoneinfo import ZoneInfo

import pytest
from pydantic import ValidationError
from sqlalchemy.dialects import postgresql

from app.models.content import UserContentStatus
from app.models.enums import CompletionSource, ContentStatus
from app.schemas.content import ContentStatusUpdate
from app.services.content_service import ContentService
from app.utils.time import PARIS_TZ, editorial_day, editorial_day_bounds


def _captured_sql(session_mock) -> str:
    stmt = session_mock.scalars.call_args.args[0]
    return str(stmt.compile(dialect=postgresql.dialect())).lower()


def _session_with_row() -> AsyncMock:
    session = AsyncMock()
    result = MagicMock()
    result.one_or_none.return_value = UserContentStatus(
        user_id=uuid4(), content_id=uuid4()
    )
    session.scalars.return_value = result
    return session


# ──────────────────────────────────────────────────────────────
# 1. Upsert
# ──────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_completed_uses_coalesce_so_first_write_wins():
    session = _session_with_row()

    await ContentService(session).update_content_status(
        user_id=uuid4(),
        content_id=uuid4(),
        update_data=ContentStatusUpdate(
            completed=True, completion_source=CompletionSource.WEB
        ),
    )

    sql = _captured_sql(session)
    assert "on conflict" in sql
    # Re-reading must not move the stamp: the conflict set reads the existing
    # column rather than overwriting it with the new parameter.
    assert "coalesce(user_content_status.completed_at" in sql
    assert "coalesce(user_content_status.completion_source" in sql


@pytest.mark.asyncio
async def test_completion_source_defaults_to_in_app():
    session = _session_with_row()

    await ContentService(session).update_content_status(
        user_id=uuid4(),
        content_id=uuid4(),
        update_data=ContentStatusUpdate(completed=True),
    )

    params = session.scalars.call_args.args[0].compile(
        dialect=postgresql.dialect()
    ).params
    assert CompletionSource.IN_APP in params.values()


@pytest.mark.asyncio
async def test_completion_absent_does_not_touch_completed_columns():
    """Un update ordinaire (progression seule) ne doit rien écrire de complétion."""
    session = _session_with_row()

    await ContentService(session).update_content_status(
        user_id=uuid4(),
        content_id=uuid4(),
        update_data=ContentStatusUpdate(reading_progress=42),
    )

    # Le RETURNING renvoie toute la ligne : on n'inspecte que la clause SET.
    conflict_set = _captured_sql(session).split("do update set")[1].split("returning")[0]
    assert "completed_at" not in conflict_set
    assert "completion_source" not in conflict_set


@pytest.mark.asyncio
async def test_completion_does_not_trigger_consumed_side_effects():
    """`completed` est orthogonal à `status` : aucun effet de bord de transition.

    C'est ce qui garantit que la reco, les poids d'intérêt et la complétion
    implicite du digest restent strictement inchangés.
    """
    session = _session_with_row()

    _, transitioned = await ContentService(session).update_content_status(
        user_id=uuid4(),
        content_id=uuid4(),
        update_data=ContentStatusUpdate(completed=True),
    )

    assert transitioned is False


# ──────────────────────────────────────────────────────────────
# 2. Séparation des requêtes
# ──────────────────────────────────────────────────────────────


def test_completed_with_consumed_is_rejected():
    """Les combiner ferait perdre `completed_at` sans bruit — on rejette."""
    with pytest.raises(ValidationError):
        ContentStatusUpdate(completed=True, status=ContentStatus.CONSUMED)


def test_completed_with_seen_is_allowed():
    """Seul CONSUMED porte la garde d'idempotence : SEEN reste combinable."""
    assert ContentStatusUpdate(completed=True, status=ContentStatus.SEEN).completed


# ──────────────────────────────────────────────────────────────
# 3. Frontière de jour éditoriale
# ──────────────────────────────────────────────────────────────


def _paris(y, m, d, h, mi) -> datetime:
    return datetime(y, m, d, h, mi, tzinfo=PARIS_TZ)


@pytest.mark.parametrize(
    ("moment", "expected_day"),
    [
        # Avant 07h30 : encore l'édition de la veille.
        (_paris(2026, 7, 24, 0, 30), 23),
        (_paris(2026, 7, 24, 7, 29), 23),
        # À partir de 07h30 : édition du jour.
        (_paris(2026, 7, 24, 7, 30), 24),
        (_paris(2026, 7, 24, 23, 59), 24),
    ],
)
def test_editorial_day_flips_at_730_paris(moment, expected_day):
    assert editorial_day(moment).day == expected_day


def test_editorial_day_normalizes_other_timezones():
    """01h00 UTC le 24 = 03h00 Paris le 24 → toujours l'édition du 23."""
    utc_moment = datetime(2026, 7, 24, 1, 0, tzinfo=ZoneInfo("UTC"))
    assert editorial_day(utc_moment).day == 23


def test_editorial_day_bounds_span_exactly_one_day():
    start, end = editorial_day_bounds(_paris(2026, 7, 24, 12, 0))
    assert (start.hour, start.minute) == (7, 30)
    assert (end - start).days == 1
    assert start.tzinfo is not None and end.tzinfo is not None


def test_editorial_day_bounds_contain_a_late_night_read():
    """Une lecture à 01h du matin tombe dans la journée éditoriale précédente."""
    late = _paris(2026, 7, 25, 1, 0)
    start, end = editorial_day_bounds(late)
    assert start <= late < end
    assert start.day == 24
