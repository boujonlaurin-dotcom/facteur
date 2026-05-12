"""Router /api/letters — Lettres du Facteur (Story 19.1).

2 endpoints :
- `GET /api/letters` : retourne les 3 lettres avec leur état courant (init
  silencieux si new user).
- `POST /api/letters/{letter_id}/refresh-status` : recalcule l'auto-détection
  pour une lettre, archive si terminée, déverrouille la suivante.
"""

from __future__ import annotations

from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.services.letters.catalog import LETTERS_BY_ID
from app.services.letters.service import (
    get_user_letters,
    refresh_letter_status,
)

logger = structlog.get_logger(__name__)

router = APIRouter()


@router.get("")
async def list_letters(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
) -> list[dict]:
    return await get_user_letters(UUID(current_user_id), db)


@router.post("/{letter_id}/refresh-status")
async def refresh_status(
    letter_id: str,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    if letter_id not in LETTERS_BY_ID:
        raise HTTPException(status_code=404, detail="Letter not found")
    return await refresh_letter_status(UUID(current_user_id), letter_id, db)
