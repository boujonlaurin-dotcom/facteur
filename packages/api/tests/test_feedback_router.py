"""Tests du système de feedback utilisateur (Epic 13)."""

from datetime import date, datetime, timedelta
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest

from app.routers.feedback import (
    ACTIVE_MIN,
    LOWACTIVE_SPREAD_DAYS,
    MAX_SHOWS,
    RETURNING_GAP_DAYS,
    SNOOZE_DAYS,
    classify_segment,
    get_invite_status,
    mark_invite_shown,
    submit_invite_action,
    submit_sentiment,
)
from app.schemas.feedback import InviteActionRequest, SentimentRequest


# --- classify_segment (fonction pure) ---


def test_classify_segment_empty():
    assert classify_segment([], date(2026, 6, 29)) is None


def test_classify_segment_new_user_not_eligible():
    # 1 seul digest aujourd'hui, aucun historique → pas encore éligible
    today = date(2026, 6, 29)
    assert classify_segment([today], today) is None


def test_classify_segment_returning():
    # Revient après une longue absence → "returning" dès 1 lecture
    today = date(2026, 6, 29)
    old = today - timedelta(days=RETURNING_GAP_DAYS + 5)
    assert classify_segment([old, today], today) == "returning"


def test_classify_segment_returning_takes_priority_over_active():
    # Même un utilisateur avec assez de lectures mais revenu après un gap
    # est classé "returning" en priorité.
    today = date(2026, 6, 29)
    old = today - timedelta(days=RETURNING_GAP_DAYS + 1)
    dates = [old - timedelta(days=i) for i in range(ACTIVE_MIN)] + [today]
    assert classify_segment(dates, today) == "returning"


def test_classify_segment_active():
    today = date(2026, 6, 29)
    dates = [today - timedelta(days=i) for i in range(ACTIVE_MIN)]
    assert classify_segment(dates, today) == "active"


def test_classify_segment_low_active():
    # 2 lectures étalées sur >= 7 jours, pas de gap de retour
    today = date(2026, 6, 29)
    first = today - timedelta(days=LOWACTIVE_SPREAD_DAYS)
    assert classify_segment([first, today], today) == "low_active"


def test_classify_segment_two_reads_too_close_not_eligible():
    # 2 lectures rapprochées (pas étalées) → pas encore "low_active"
    today = date(2026, 6, 29)
    yesterday = today - timedelta(days=1)
    assert classify_segment([yesterday, today], today) is None


def test_classify_segment_dedups_dates():
    today = date(2026, 6, 29)
    # Doublons ne doivent pas gonfler artificiellement le total
    assert classify_segment([today, today, today], today) is None


# --- submit_sentiment ---


@pytest.mark.asyncio
async def test_submit_sentiment_upsert():
    mock_db = AsyncMock()
    user_id = str(uuid4())
    request = SentimentRequest(sentiment="high", digest_date="2026-06-29")

    response = await submit_sentiment(
        request=request, db=mock_db, current_user_id=user_id
    )

    assert response["sentiment"] == "high"
    assert mock_db.execute.called
    assert mock_db.commit.called


@pytest.mark.asyncio
async def test_submit_sentiment_invalid_date():
    from fastapi import HTTPException

    mock_db = AsyncMock()
    request = SentimentRequest(sentiment="ok", digest_date="not-a-date")

    with pytest.raises(HTTPException) as exc:
        await submit_sentiment(
            request=request, db=mock_db, current_user_id=str(uuid4())
        )
    assert exc.value.status_code == 400


# --- get_invite_status ---


@pytest.mark.asyncio
async def test_get_invite_status_not_eligible():
    mock_db = AsyncMock()
    with patch(
        "app.routers.feedback._eligible_segment",
        AsyncMock(return_value=None),
    ):
        result = await get_invite_status(db=mock_db, current_user_id=str(uuid4()))
    assert result.should_show is False
    assert result.reason == "not_eligible"


@pytest.mark.asyncio
async def test_get_invite_status_eligible_no_prior_invite():
    mock_db = AsyncMock()
    mock_db.scalar = AsyncMock(return_value=None)
    with patch(
        "app.routers.feedback._eligible_segment",
        AsyncMock(return_value="active"),
    ):
        result = await get_invite_status(db=mock_db, current_user_id=str(uuid4()))
    assert result.should_show is True
    assert result.segment == "active"


@pytest.mark.asyncio
async def test_get_invite_status_accepted_is_terminal():
    invite = type("I", (), {})()
    invite.status = "accepted"
    invite.snoozed_until = None
    invite.shown_count = 1
    mock_db = AsyncMock()
    mock_db.scalar = AsyncMock(return_value=invite)
    with patch(
        "app.routers.feedback._eligible_segment",
        AsyncMock(return_value="active"),
    ):
        result = await get_invite_status(db=mock_db, current_user_id=str(uuid4()))
    assert result.should_show is False
    assert result.reason == "accepted"


@pytest.mark.asyncio
async def test_get_invite_status_snoozed_blocks():
    invite = type("I", (), {})()
    invite.status = "snoozed"
    invite.snoozed_until = datetime.utcnow() + timedelta(days=5)
    invite.shown_count = 1
    mock_db = AsyncMock()
    mock_db.scalar = AsyncMock(return_value=invite)
    with patch(
        "app.routers.feedback._eligible_segment",
        AsyncMock(return_value="low_active"),
    ):
        result = await get_invite_status(db=mock_db, current_user_id=str(uuid4()))
    assert result.should_show is False
    assert result.reason == "snoozed"


@pytest.mark.asyncio
async def test_get_invite_status_snooze_expired_reshows():
    invite = type("I", (), {})()
    invite.status = "snoozed"
    invite.snoozed_until = datetime.utcnow() - timedelta(days=1)
    invite.shown_count = 1
    mock_db = AsyncMock()
    mock_db.scalar = AsyncMock(return_value=invite)
    with patch(
        "app.routers.feedback._eligible_segment",
        AsyncMock(return_value="returning"),
    ):
        result = await get_invite_status(db=mock_db, current_user_id=str(uuid4()))
    assert result.should_show is True


@pytest.mark.asyncio
async def test_get_invite_status_max_shows_blocks():
    invite = type("I", (), {})()
    invite.status = "snoozed"
    invite.snoozed_until = None
    invite.shown_count = MAX_SHOWS
    mock_db = AsyncMock()
    mock_db.scalar = AsyncMock(return_value=invite)
    with patch(
        "app.routers.feedback._eligible_segment",
        AsyncMock(return_value="active"),
    ):
        result = await get_invite_status(db=mock_db, current_user_id=str(uuid4()))
    assert result.should_show is False
    assert result.reason == "max_shows"


# --- mark_invite_shown ---


@pytest.mark.asyncio
async def test_mark_invite_shown():
    mock_db = AsyncMock()
    with patch(
        "app.routers.feedback._eligible_segment",
        AsyncMock(return_value="active"),
    ):
        response = await mark_invite_shown(db=mock_db, current_user_id=str(uuid4()))
    assert response["message"] == "ok"
    assert mock_db.execute.called
    assert mock_db.commit.called


# --- submit_invite_action ---


@pytest.mark.asyncio
async def test_submit_invite_action_accepted():
    invite = type("I", (), {})()
    invite.status = "pending"
    invite.shown_count = 1
    invite.snoozed_until = None
    mock_db = AsyncMock()
    mock_db.scalar = AsyncMock(return_value=invite)

    response = await submit_invite_action(
        request=InviteActionRequest(action="accepted"),
        db=mock_db,
        current_user_id=str(uuid4()),
    )
    assert invite.status == "accepted"
    assert response["status"] == "accepted"
    assert mock_db.commit.called


@pytest.mark.asyncio
async def test_submit_invite_action_declined_snoozes():
    invite = type("I", (), {})()
    invite.status = "pending"
    invite.shown_count = 1  # < MAX_SHOWS
    invite.snoozed_until = None
    mock_db = AsyncMock()
    mock_db.scalar = AsyncMock(return_value=invite)

    await submit_invite_action(
        request=InviteActionRequest(action="declined"),
        db=mock_db,
        current_user_id=str(uuid4()),
    )
    assert invite.status == "snoozed"
    assert invite.snoozed_until is not None
    # snooze ~ SNOOZE_DAYS dans le futur
    delta = invite.snoozed_until - datetime.utcnow()
    assert timedelta(days=SNOOZE_DAYS - 1) < delta <= timedelta(days=SNOOZE_DAYS)


@pytest.mark.asyncio
async def test_submit_invite_action_declined_terminal_after_max():
    invite = type("I", (), {})()
    invite.status = "snoozed"
    invite.shown_count = MAX_SHOWS  # >= MAX_SHOWS → définitif
    invite.snoozed_until = datetime.utcnow()
    mock_db = AsyncMock()
    mock_db.scalar = AsyncMock(return_value=invite)

    await submit_invite_action(
        request=InviteActionRequest(action="declined"),
        db=mock_db,
        current_user_id=str(uuid4()),
    )
    assert invite.status == "declined"
    assert invite.snoozed_until is None
