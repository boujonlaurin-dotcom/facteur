"""Router pour les préférences de notifications push (Activation Push v1)."""

from datetime import datetime
from typing import Literal
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.user_notification_preferences import UserNotificationPreferences
from app.services.user_service import UserService

logger = structlog.get_logger()

router = APIRouter()


Preset = Literal["minimaliste", "curieux"]
TimeSlot = Literal["morning", "evening"]


class NotificationPreferencesResponse(BaseModel):
    push_enabled: bool
    preset: Preset
    time_slot: TimeSlot
    timezone: str
    refusal_count: int
    last_refusal_at: datetime | None
    last_renudge_at: datetime | None
    renudge_shown_count: int
    modal_seen: bool


class NotificationPreferencesPatch(BaseModel):
    push_enabled: bool | None = None
    preset: Preset | None = None
    time_slot: TimeSlot | None = None
    timezone: str | None = Field(default=None, max_length=64)
    refusal_count: int | None = Field(default=None, ge=0)
    last_refusal_at: datetime | None = None
    last_renudge_at: datetime | None = None
    renudge_shown_count: int | None = Field(default=None, ge=0)
    modal_seen: bool | None = None


def _to_response(row: UserNotificationPreferences) -> NotificationPreferencesResponse:
    return NotificationPreferencesResponse(
        push_enabled=row.push_enabled,
        preset=row.preset,  # type: ignore[arg-type]
        time_slot=row.time_slot,  # type: ignore[arg-type]
        timezone=row.timezone,
        refusal_count=row.refusal_count,
        last_refusal_at=row.last_refusal_at,
        last_renudge_at=row.last_renudge_at,
        renudge_shown_count=row.renudge_shown_count,
        modal_seen=row.modal_seen,
    )


async def _get_or_create(
    db: AsyncSession, user_id: UUID
) -> UserNotificationPreferences:
    row = await db.scalar(
        select(UserNotificationPreferences).where(
            UserNotificationPreferences.user_id == user_id
        )
    )
    if row:
        return row

    # Race-safe : si une requête concurrente a déjà inséré la row, ON CONFLICT
    # DO NOTHING évite la unique-violation puis on re-SELECT (résultat garanti
    # non-null grâce à la PK user_id).
    stmt = (
        pg_insert(UserNotificationPreferences)
        .values(user_id=user_id)
        .on_conflict_do_nothing(index_elements=["user_id"])
    )
    await db.execute(stmt)
    await db.commit()

    row = await db.scalar(
        select(UserNotificationPreferences).where(
            UserNotificationPreferences.user_id == user_id
        )
    )
    assert row is not None
    return row


@router.get("/", response_model=NotificationPreferencesResponse)
async def get_notification_preferences(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Renvoie les préférences notif (auto-création de la row si absente)."""
    user_uuid = UUID(current_user_id)
    user_service = UserService(db)
    await user_service.get_or_create_profile(current_user_id)
    await db.commit()

    row = await _get_or_create(db, user_uuid)
    return _to_response(row)


@router.patch("/", response_model=NotificationPreferencesResponse)
async def patch_notification_preferences(
    patch: NotificationPreferencesPatch,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Met à jour partiellement les préférences notif."""
    user_uuid = UUID(current_user_id)
    user_service = UserService(db)
    await user_service.get_or_create_profile(current_user_id)
    await db.commit()

    row = await _get_or_create(db, user_uuid)

    updates = patch.model_dump(exclude_unset=True)
    if not updates:
        return _to_response(row)

    for field, value in updates.items():
        setattr(row, field, value)

    try:
        await db.commit()
        await db.refresh(row)
    except Exception as e:
        await db.rollback()
        logger.error(
            "notification_preferences_patch_error",
            error=str(e),
            user_id=str(user_uuid),
            updates=list(updates.keys()),
        )
        raise HTTPException(
            status_code=500,
            detail="Erreur lors de la mise à jour des préférences notifications",
        )

    return _to_response(row)
