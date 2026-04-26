"""Schemas pour la note self-reported "bien informé" (Story 14.3)."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class WellInformedRatingCreate(BaseModel):
    """Payload de soumission d'une note 1-10."""

    score: int = Field(..., ge=1, le=10, description="Note 1 (pas informé) à 10")
    context: str = Field(
        "digest_inline",
        max_length=32,
        description="Surface d'origine (digest_inline, etc.)",
    )


class WellInformedRatingRead(BaseModel):
    """Représentation publique d'une note soumise."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    score: int
    context: str
    submitted_at: datetime
