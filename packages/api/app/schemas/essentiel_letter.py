"""Schemas de la « lettre » Essentiel (Story 9.6).

La lettre est un digest rédigé concis où les références sont la navigation :
un chapô fluide + 2-3 lignes-rubriques + un pied « autres thèmes ». Le texte
est découpé en segments typés pour que le mobile rende les boutons source
(ouvre l'article) et les pills thème (scrolle vers la section) inline.
"""

from datetime import datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field

# Version du format sérialisé stocké dans `essentiel_letters.letter`. À bumper
# si la structure des segments change (le mobile ignore les versions inconnues).
LETTER_FORMAT_VERSION = 1


class LetterSegmentType(StrEnum):
    """Nature d'un segment de la lettre."""

    TEXT = "text"
    SOURCE_REF = "source_ref"
    THEME_REF = "theme_ref"


class LetterSegment(BaseModel):
    """Fragment typé d'un bloc de la lettre.

    - `text` : prose brute (`text` renseigné).
    - `source_ref` : bouton source inline (`content_id` renseigné, pointe un
      article du snapshot `articles[]` de la réponse).
    - `theme_ref` : pill thème inline (`text` = slug du thème).
    """

    type: LetterSegmentType
    text: str | None = None
    content_id: UUID | None = None


class LetterRubrique(BaseModel):
    """Ligne-rubrique : pill thème en tête + 1 phrase avec bouton(s) source."""

    theme: str = Field(..., description="Slug du thème (mapping couleur mobile)")
    segments: list[LetterSegment] = Field(default_factory=list)


class EssentielLetter(BaseModel):
    """Lettre du jour de l'Essentiel (digest rédigé à références inline)."""

    version: int = LETTER_FORMAT_VERSION
    chapo: list[LetterSegment] = Field(default_factory=list)
    rubriques: list[LetterRubrique] = Field(default_factory=list)
    footer_themes: list[str] = Field(
        default_factory=list,
        description="Slugs des thèmes « Aussi dans ta tournée » (pills du pied)",
    )
    generated_at: datetime
    model: str
