"""Tests for the past-date guard in `_schedule_background_regen`.

EPIC « Lettre du jour » : le mobile peut désormais demander l'Essentiel d'un
jour passé (`target_date` < aujourd'hui). La chaîne `read_digest_or_fallback`
appelle `_schedule_background_regen` dès qu'elle sert un fallback stale ; sans
garde, ouvrir la lettre d'hier régénérerait + persisterait un digest passé à
partir du pool d'articles du jour (contenu faux + coût LLM).

La garde additive court-circuite la régen pour tout `target_date` révolu. Le
cas légitime « servir hier pour aujourd'hui » utilise `target_date == today` et
n'est donc jamais affecté.

Cf. test_digest_readonly_hotpath.py pour le style des tests de la chaîne.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from unittest.mock import AsyncMock, Mock, patch
from uuid import UUID, uuid4

import pytest

from app.schemas.digest import DigestResponse
from app.services import digest_service
from app.services.digest_service import (
    _schedule_background_regen,
    read_digest_or_fallback,
)

# ─── Helpers (alignés sur test_digest_readonly_hotpath.py) ───────────────────


def _make_digest_row(
    *,
    user_id: UUID,
    target_date: date,
    is_serene: bool,
    format_version: str = "editorial_v1",
):
    row = Mock()
    row.id = uuid4()
    row.user_id = user_id
    row.target_date = target_date
    row.is_serene = is_serene
    row.format_version = format_version
    row.generated_at = datetime.utcnow()
    row.items = []
    row.mode = "serein" if is_serene else "pour_vous"
    return row


def _make_response(*, is_stale_fallback: bool = False) -> DigestResponse:
    return DigestResponse(
        digest_id=uuid4(),
        user_id=uuid4(),
        target_date=date.today(),
        generated_at=datetime.utcnow(),
        items=[],
        is_completed=False,
        is_stale_fallback=is_stale_fallback,
    )


# ─── Garde directe sur _schedule_background_regen ────────────────────────────


def test_schedule_regen_skips_past_target_date():
    """Un `target_date` révolu court-circuite AVANT tout `create_task` :
    aucune tâche de régénération n'est planifiée."""
    user_id = uuid4()
    past = date.today() - timedelta(days=3)

    with patch.object(digest_service.asyncio, "create_task") as create_task_mock:
        _schedule_background_regen(
            user_id=user_id, target_date=past, is_serene=False
        )

    create_task_mock.assert_not_called()


def test_schedule_regen_still_spawns_for_today_after_cron():
    """Contrôle positif : pour `target_date == today` après l'heure du cron, la
    garde « édition passée » ne bloque pas (le spawn part normalement)."""
    user_id = uuid4()
    today = date.today()
    # `now` >= cron hour pour éviter la garde « too early » distincte.
    fake_now = datetime(today.year, today.month, today.day, 23, 0)

    # `now_paris` est importé LOCALEMENT dans `_schedule_background_regen`
    # (`from app.utils.time import now_paris`) → on patche le module source.
    with (
        patch("app.utils.time.now_paris", return_value=fake_now),
        patch.object(digest_service.asyncio, "create_task") as create_task_mock,
    ):
        _schedule_background_regen(
            user_id=user_id, target_date=today, is_serene=False
        )

    create_task_mock.assert_called_once()


# ─── Intégration via read_digest_or_fallback ─────────────────────────────────


@pytest.mark.asyncio
async def test_read_fallback_past_date_serves_stale_without_regen():
    """Ouvrir la lettre d'un jour passé sans digest propre sert bien un
    fallback stale, mais NE planifie AUCUNE régénération (la garde interne de
    `_schedule_background_regen` bloque le spawn)."""
    user_id = uuid4()
    # target = hier ; le step-4 (7 jours) trouve un digest encore plus ancien.
    target = date.today() - timedelta(days=1)
    older = _make_digest_row(
        user_id=user_id,
        target_date=target - timedelta(days=2),
        is_serene=False,
    )
    rendered = _make_response()

    exec_result = Mock()
    exec_result.scalar_one_or_none = Mock(return_value=older)
    session = AsyncMock()
    session.execute = AsyncMock(return_value=exec_result)

    with (
        patch.object(
            digest_service.DigestService,
            "_get_existing_digest",
            new=AsyncMock(return_value=None),  # ni own today-of-target, ni veille
        ),
        patch.object(
            digest_service.DigestService,
            "_try_clone_global_editorial_digest",
            new=AsyncMock(return_value=None),
        ),
        patch.object(
            digest_service.DigestService,
            "_build_digest_response",
            new=AsyncMock(return_value=rendered),
        ),
        # On NE mocke PAS _schedule_background_regen : on observe son effet réel
        # (la garde) via create_task.
        patch.object(digest_service.asyncio, "create_task") as create_task_mock,
    ):
        out = await read_digest_or_fallback(
            session, user_id, target, is_serene=False
        )

    assert out is rendered
    assert out.is_stale_fallback is True
    create_task_mock.assert_not_called()
