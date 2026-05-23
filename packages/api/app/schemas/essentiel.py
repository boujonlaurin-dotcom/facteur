"""Schemas pour l'endpoint `GET /api/essentiel` (Story 9.1).

Renvoie les 5 articles transversaux du jour pour alimenter la carte hi-fi
"L'Essentiel du jour" du feed mobile.

Lecture seule : consomme le digest déjà calculé par la cron nocturne (jamais
de pipeline LLM au request time, comme `/api/digest`).
"""

from datetime import date, datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.content import SourceMini


class EssentielKind(StrEnum):
    """Famille de section côté mobile (pilote l'icône / l'accent générique).

    Aligne avec `SectionKind` côté mobile (`apps/mobile/lib/features/
    flux_continu/models/flux_continu_models.dart`).
    """

    ESSENTIEL = "essentiel"
    BONNES = "bonnes"
    THEME = "theme"
    VEILLE = "veille"


class EssentielArticle(BaseModel):
    """Un article du top 5 transversal de l'Essentiel.

    Reprend les champs nécessaires à la carte hi-fi (lead/médium/light) sans
    réexposer toute la richesse d'un `DigestTopicArticle`.
    """

    content_id: UUID
    title: str
    url: str
    thumbnail_url: str | None = None
    published_at: datetime
    source: SourceMini
    source_letter: str = Field(
        ..., min_length=1, max_length=1, description="Initiale source pour la pastille"
    )
    kind: EssentielKind = EssentielKind.THEME
    theme: str | None = Field(
        None, description="Slug du thème du topic d'origine (mapping couleur mobile)"
    )
    section_label: str = Field(..., description="Libellé du topic d'origine")
    perspective_count: int = 0
    rank: int = Field(..., ge=1, le=5, description="Position dans l'essentiel (1..5)")
    is_read: bool = False
    is_saved: bool = False
    is_liked: bool = False
    is_dismissed: bool = False

    class Config:
        from_attributes = True


class EssentielResponse(BaseModel):
    """Réponse pour `GET /api/essentiel`."""

    target_date: date
    generated_at: datetime
    articles: list[EssentielArticle] = Field(default_factory=list)
    is_stale_fallback: bool = Field(
        default=False,
        description=(
            "True quand l'essentiel a été construit depuis le digest d'hier "
            "en attendant que celui d'aujourd'hui soit prêt."
        ),
    )

    class Config:
        from_attributes = True
