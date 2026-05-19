"""Schemas — système d'intérêts unifié (Story 22.1, cap retiré Story 22.2).

Couvre les écrans « Mes intérêts » (Thèmes + Sujets) et « Mes sources ». L'enum
`InterestState` est l'axe sémantique unique (hidden/unfollowed/followed/favorite)
partagé par les 3 entités. `FAVORITE_CAP=3` n'est plus une limite dure mais le
cap d'affichage de la « Tournée du jour » (les 3 premiers favoris par position).
"""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models.enums import InterestState

InterestKind = Literal["theme", "custom_topic", "veille"]


class FavoriteRef(BaseModel):
    """Référence ordonnée vers un favori (Thème, Sujet, ou Veille).

    Pour `kind="veille"`, `target_id` est `str(veille_config_id)` (UUID).
    """

    kind: InterestKind
    target_id: str
    position: int = Field(ge=0)


class ThemeInterestResponse(BaseModel):
    """Thème (vocabulaire fermé) avec son weight appris et son state déclaré."""

    interest_slug: str
    weight: float
    state: InterestState

    model_config = ConfigDict(from_attributes=True)


class CustomTopicInterestResponse(BaseModel):
    """Sujet personnalisé avec multiplier appris et state déclaré."""

    id: UUID
    topic_name: str
    slug_parent: str
    state: InterestState
    priority_multiplier: float

    model_config = ConfigDict(from_attributes=True)


class UserInterestsResponse(BaseModel):
    """Réponse `GET /api/user/interests` : état complet pour écran « Mes intérêts »."""

    themes: list[ThemeInterestResponse]
    custom_topics: list[CustomTopicInterestResponse]
    favorites: list[FavoriteRef]
    favorite_count: int
    favorite_cap: int


class SetInterestStateRequest(BaseModel):
    """`PATCH /api/user/interests` : muter l'état d'un Thème ou Sujet.

    `position` optionnel : si `state=favorite` et `position=None`, le service
    auto-assigne le prochain slot libre. `state ≠ favorite` retire la row du
    table `user_favorite_interests` si elle existait.
    """

    kind: InterestKind
    target_id: str
    state: InterestState
    position: int | None = Field(None, ge=0)


class ReorderFavoritesRequest(BaseModel):
    """`POST /api/user/interests/reorder` : nouvel ordre canonique des favoris.

    Tous les targets DOIVENT déjà être `state=favorite` sur leur table source.
    La transaction wipe + insert garantit l'ordre 0..N strict.
    """

    favorites: list[FavoriteRef]

    @field_validator("favorites")
    @classmethod
    def _validate_positions(cls, v: list[FavoriteRef]) -> list[FavoriteRef]:
        positions = [f.position for f in v]
        if sorted(positions) != list(range(len(v))):
            raise ValueError("positions must be a contiguous 0..N-1 sequence")
        return v


class SourceStateResponse(BaseModel):
    """Source avec son state déclaré, exposée pour écran « Mes sources »."""

    source_id: UUID
    state: InterestState
    priority_multiplier: float

    model_config = ConfigDict(from_attributes=True)


class SourceFavoriteRef(BaseModel):
    """Favori source ordonné (pas de XOR, juste position + source_id)."""

    source_id: UUID
    position: int = Field(ge=0)


class UserSourcesStateResponse(BaseModel):
    """Réponse `GET /api/user/sources` : sources de l'utilisateur + favoris ordonnés."""

    sources: list[SourceStateResponse]
    favorites: list[SourceFavoriteRef]
    favorite_count: int
    favorite_cap: int


class SetSourceStateRequest(BaseModel):
    """`PATCH /api/user/sources` : muter l'état d'une Source."""

    source_id: UUID
    state: InterestState
    position: int | None = Field(None, ge=0)


class ReorderSourceFavoritesRequest(BaseModel):
    """`POST /api/user/sources/reorder` : nouvel ordre canonique des sources favorites."""

    favorites: list[SourceFavoriteRef]

    @field_validator("favorites")
    @classmethod
    def _validate_positions(cls, v: list[SourceFavoriteRef]) -> list[SourceFavoriteRef]:
        positions = [f.position for f in v]
        if sorted(positions) != list(range(len(v))):
            raise ValueError("positions must be a contiguous 0..N-1 sequence")
        return v
