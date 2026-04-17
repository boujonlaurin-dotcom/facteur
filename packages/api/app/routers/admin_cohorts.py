"""Endpoint admin pour tagger les utilisateurs dans des cohortes PostHog.

Story 14.1 — permet à Laurin de marquer un user comme `waitlist`, `invite`,
`creator` ou `organic` sans toucher à la base via psql.
Stocke l'info dans `user_preferences` (clé `acquisition_source`) et
propage immédiatement vers PostHog via `identify()`.
"""

from __future__ import annotations

from typing import Literal
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.models.user import UserPreference
from app.services.posthog_client import derive_cohort_properties, get_posthog_client

logger = structlog.get_logger()

router = APIRouter()

ACQUISITION_SOURCE_KEY = "acquisition_source"
AcquisitionSource = Literal["waitlist", "invite", "creator", "organic"]


class CohortUpdateRequest(BaseModel):
    """Payload pour tagger la cohorte d'un utilisateur."""

    acquisition_source: AcquisitionSource = Field(
        ...,
        description="Canal d'acquisition (waitlist, invite, creator, organic)",
    )
    email: EmailStr | None = Field(
        None,
        description="Email utilisateur — utilisé pour calculer les cohortes spéciales",
    )


class CohortUpdateResponse(BaseModel):
    user_id: UUID
    acquisition_source: AcquisitionSource
    posthog_synced: bool


def require_admin_token(
    x_admin_token: str | None = Header(default=None, alias="X-Admin-Token"),
) -> None:
    """Vérifie le header X-Admin-Token contre ADMIN_API_TOKEN.

    Refuse tout accès si le secret est vide en config (fail-closed).
    """
    settings = get_settings()
    expected = settings.admin_api_token
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin API disabled: ADMIN_API_TOKEN not configured",
        )
    if not x_admin_token or x_admin_token != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing X-Admin-Token header",
        )


@router.patch(
    "/users/{user_id}/cohorts",
    response_model=CohortUpdateResponse,
    dependencies=[Depends(require_admin_token)],
)
async def update_user_cohort(
    user_id: UUID,
    payload: CohortUpdateRequest,
    db: AsyncSession = Depends(get_db),
) -> CohortUpdateResponse:
    """Upsert acquisition_source dans user_preferences + identify PostHog."""
    stmt = select(UserPreference).where(
        UserPreference.user_id == user_id,
        UserPreference.preference_key == ACQUISITION_SOURCE_KEY,
    )
    existing = (await db.execute(stmt)).scalar_one_or_none()

    if existing is None:
        db.add(
            UserPreference(
                user_id=user_id,
                preference_key=ACQUISITION_SOURCE_KEY,
                preference_value=payload.acquisition_source,
            )
        )
    else:
        existing.preference_value = payload.acquisition_source

    await db.commit()

    posthog = get_posthog_client()
    properties: dict[str, str | bool] = {
        "acquisition_source": payload.acquisition_source,
    }
    properties.update(derive_cohort_properties(payload.email))
    posthog.identify(user_id, properties=properties)

    logger.info(
        "admin_cohort_updated",
        user_id=str(user_id),
        acquisition_source=payload.acquisition_source,
        posthog_enabled=posthog.enabled,
    )

    return CohortUpdateResponse(
        user_id=user_id,
        acquisition_source=payload.acquisition_source,
        posthog_synced=posthog.enabled,
    )
