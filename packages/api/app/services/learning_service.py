"""Service pour les preferences utilisateur sur entites nommees (follow/mute).

Historique : ce module hebergeait aussi le Learning Checkpoint (Epic 13)
— supprime en Sprint 2 PR1 (feature morte, 0 UI mobile, 0 rows prod).
Cf. migration `lp02`.
"""

from uuid import UUID

import structlog
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.learning import UserEntityPreference

logger = structlog.get_logger()


class LearningService:
    """Preferences utilisateur sur entites nommees (mute/follow)."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def set_entity_preference(
        self, user_id: UUID, entity_canonical: str, preference: str
    ) -> None:
        """Cree ou met a jour une preference entite."""
        stmt = (
            pg_insert(UserEntityPreference)
            .values(
                user_id=user_id,
                entity_canonical=entity_canonical,
                preference=preference,
            )
            .on_conflict_do_update(
                constraint="uq_user_entity_pref_user_entity",
                set_={"preference": preference},
            )
        )
        await self.db.execute(stmt)
        await self.db.flush()

    async def remove_entity_preference(
        self, user_id: UUID, entity_canonical: str
    ) -> bool:
        """Supprime une preference entite. Retourne True si supprimee."""
        result = await self.db.execute(
            delete(UserEntityPreference).where(
                UserEntityPreference.user_id == user_id,
                UserEntityPreference.entity_canonical == entity_canonical,
            )
        )
        await self.db.flush()
        return result.rowcount > 0

    async def get_entity_preferences(self, user_id: UUID) -> list[UserEntityPreference]:
        """Retourne toutes les preferences entite d'un utilisateur."""
        result = await self.db.execute(
            select(UserEntityPreference).where(UserEntityPreference.user_id == user_id)
        )
        return list(result.scalars().all())

    async def get_muted_entities(self, user_id: UUID) -> list[str]:
        """Retourne les noms canoniques des entites mutees."""
        result = await self.db.execute(
            select(UserEntityPreference.entity_canonical).where(
                UserEntityPreference.user_id == user_id,
                UserEntityPreference.preference == "mute",
            )
        )
        return [row[0] for row in result.all()]
