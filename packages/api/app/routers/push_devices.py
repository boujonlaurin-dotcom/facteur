"""Authenticated FCM device registration and revocation."""

from datetime import UTC, datetime
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.push_notification import PushDevice
from app.models.user_notification_preferences import UserNotificationPreferences
from app.services.user_service import UserService

router = APIRouter()
settings = get_settings()


class PushDeviceUpsert(BaseModel):
    device_id: UUID
    fcm_token: str = Field(min_length=20, max_length=4096)
    platform: Literal["android", "ios"]
    timezone: str = Field(min_length=1, max_length=64)
    app_version: str | None = Field(default=None, max_length=32)


class PushDeviceResponse(BaseModel):
    device_id: UUID
    registered: bool = True


@router.put("", response_model=PushDeviceResponse)
async def upsert_push_device(
    payload: PushDeviceUpsert,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
) -> PushDeviceResponse:
    if not (
        settings.firebase_service_account_json
        or settings.firebase_service_account_base64
    ):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Push serveur non configuré",
        )

    user_id = UUID(current_user_id)
    await UserService(db).get_or_create_profile(current_user_id)
    now = datetime.now(UTC)

    # The preferences table remains the scheduling source of truth. Refresh it
    # from the device at each registration so travel/timezone changes are used
    # by the next dispatcher pass without resetting the other preferences.
    await db.execute(
        pg_insert(UserNotificationPreferences)
        .values(user_id=user_id, timezone=payload.timezone)
        .on_conflict_do_update(
            index_elements=["user_id"],
            set_={"timezone": payload.timezone},
        )
    )

    existing = await db.scalar(
        select(PushDevice).where(PushDevice.device_id == payload.device_id)
    )
    if (
        existing is not None
        and existing.user_id != user_id
        and existing.revoked_at is None
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Appareil déjà associé à un autre compte",
        )

    # A refreshed token may move between locally recreated device IDs.
    await db.execute(
        update(PushDevice)
        .where(
            PushDevice.fcm_token == payload.fcm_token,
            PushDevice.device_id != payload.device_id,
        )
        .values(revoked_at=now)
    )
    stmt = (
        pg_insert(PushDevice)
        .values(
            device_id=payload.device_id,
            user_id=user_id,
            fcm_token=payload.fcm_token,
            platform=payload.platform,
            timezone=payload.timezone,
            app_version=payload.app_version,
            created_at=now,
            last_active_at=now,
            revoked_at=None,
        )
        .on_conflict_do_update(
            index_elements=["device_id"],
            set_={
                "user_id": user_id,
                "fcm_token": payload.fcm_token,
                "platform": payload.platform,
                "timezone": payload.timezone,
                "app_version": payload.app_version,
                "last_active_at": now,
                "revoked_at": None,
            },
        )
    )
    await db.execute(stmt)
    await db.commit()
    return PushDeviceResponse(device_id=payload.device_id)


@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_push_device(
    device_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
) -> None:
    user_id = UUID(current_user_id)
    device = await db.scalar(
        select(PushDevice).where(
            PushDevice.device_id == device_id,
            PushDevice.user_id == user_id,
        )
    )
    if device is None:
        raise HTTPException(status_code=404, detail="Appareil introuvable")
    device.revoked_at = datetime.now(UTC)
    await db.commit()
