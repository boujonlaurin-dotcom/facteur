"""Schemas collections."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CollectionCreate(BaseModel):
    """Requête de création d'une collection."""

    name: str = Field(..., min_length=1, max_length=100)


class CollectionUpdate(BaseModel):
    """Requête de renommage d'une collection."""

    name: str = Field(..., min_length=1, max_length=100)


class CollectionResponse(BaseModel):
    """Réponse collection avec métadonnées."""

    id: UUID
    name: str
    position: int
    item_count: int = 0
    read_count: int = 0
    thumbnails: list[str | None] = []
    created_at: datetime

    class Config:
        from_attributes = True


class CollectionItemAdd(BaseModel):
    """Requête d'ajout d'un article à une collection."""

    content_id: UUID


class SaveContentRequest(BaseModel):
    """Requête de sauvegarde avec collection_ids optionnels."""

    collection_ids: list[UUID] | None = None


class ThemeCount(BaseModel):
    """Compteur d'articles par thème."""

    theme: str
    count: int


class SavedSummaryResponse(BaseModel):
    """Résumé des sauvegardes pour les nudges."""

    total_saved: int = 0
    unread_count: int = 0
    recent_count_7d: int = 0
    top_themes: list[ThemeCount] = []
