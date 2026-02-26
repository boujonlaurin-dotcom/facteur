"""Service métier pour les collections de sauvegardes."""

from datetime import datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.collection import Collection, CollectionItem
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus

logger = structlog.get_logger()

MAX_COLLECTIONS_PER_USER = 50


class CollectionService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def list_collections(self, user_id: UUID) -> list[dict]:
        """Liste les collections avec count, read_count et 4 thumbnail URLs."""
        # Fetch collections
        stmt = (
            select(Collection)
            .where(Collection.user_id == user_id)
            .order_by(Collection.position, Collection.created_at)
        )
        result = await self.session.execute(stmt)
        collections = result.scalars().all()

        response = []
        for col in collections:
            # Count items
            count_stmt = (
                select(func.count())
                .select_from(CollectionItem)
                .where(CollectionItem.collection_id == col.id)
            )
            item_count = await self.session.scalar(count_stmt) or 0

            # Count read items
            read_stmt = (
                select(func.count())
                .select_from(CollectionItem)
                .join(
                    UserContentStatus,
                    (UserContentStatus.content_id == CollectionItem.content_id)
                    & (UserContentStatus.user_id == user_id),
                )
                .where(
                    CollectionItem.collection_id == col.id,
                    UserContentStatus.status == ContentStatus.CONSUMED,
                )
            )
            read_count = await self.session.scalar(read_stmt) or 0

            # Get 4 most recent thumbnails for mosaic
            thumb_stmt = (
                select(Content.thumbnail_url)
                .join(CollectionItem, CollectionItem.content_id == Content.id)
                .where(CollectionItem.collection_id == col.id)
                .order_by(CollectionItem.added_at.desc())
                .limit(4)
            )
            thumb_result = await self.session.execute(thumb_stmt)
            thumbnails = [row[0] for row in thumb_result.all()]

            response.append(
                {
                    "id": col.id,
                    "name": col.name,
                    "position": col.position,
                    "item_count": item_count,
                    "read_count": read_count,
                    "thumbnails": thumbnails,
                    "created_at": col.created_at,
                }
            )

        return response

    async def create_collection(self, user_id: UUID, name: str) -> Collection:
        """Crée une collection. Valide unicité du nom et limite max."""
        # Check limit
        count_stmt = (
            select(func.count())
            .select_from(Collection)
            .where(Collection.user_id == user_id)
        )
        count = await self.session.scalar(count_stmt) or 0
        if count >= MAX_COLLECTIONS_PER_USER:
            raise ValueError(f"Maximum {MAX_COLLECTIONS_PER_USER} collections atteint")

        # Get next position
        max_pos_stmt = select(func.coalesce(func.max(Collection.position), -1)).where(
            Collection.user_id == user_id
        )
        max_pos = await self.session.scalar(max_pos_stmt)

        collection = Collection(
            user_id=user_id,
            name=name.strip(),
            position=(max_pos or 0) + 1,
        )
        self.session.add(collection)
        await self.session.flush()

        logger.info(
            "collection_created",
            user_id=str(user_id),
            collection_id=str(collection.id),
            name=name,
        )
        return collection

    async def update_collection(
        self, user_id: UUID, collection_id: UUID, name: str
    ) -> Collection:
        """Renomme une collection."""
        collection = await self._get_user_collection(user_id, collection_id)
        collection.name = name.strip()
        collection.updated_at = datetime.utcnow()
        await self.session.flush()
        return collection

    async def delete_collection(self, user_id: UUID, collection_id: UUID) -> None:
        """Supprime une collection (les articles restent sauvegardés)."""
        collection = await self._get_user_collection(user_id, collection_id)
        await self.session.delete(collection)
        await self.session.flush()
        logger.info(
            "collection_deleted", user_id=str(user_id), collection_id=str(collection_id)
        )

    async def get_collection_items(
        self,
        user_id: UUID,
        collection_id: UUID,
        limit: int = 20,
        offset: int = 0,
        sort: str = "recent",
    ) -> list[dict]:
        """Retourne les articles d'une collection paginés avec métadonnées."""
        from sqlalchemy.orm import selectinload

        # Verify ownership
        await self._get_user_collection(user_id, collection_id)

        # Base query: join CollectionItem -> Content -> Source + UserContentStatus
        stmt = (
            select(Content, UserContentStatus, CollectionItem.added_at)
            .join(CollectionItem, CollectionItem.content_id == Content.id)
            .outerjoin(
                UserContentStatus,
                (UserContentStatus.content_id == Content.id)
                & (UserContentStatus.user_id == user_id),
            )
            .options(selectinload(Content.source))
            .where(CollectionItem.collection_id == collection_id)
        )

        # Sort
        if sort == "oldest":
            stmt = stmt.order_by(CollectionItem.added_at.asc())
        elif sort == "source":
            stmt = stmt.order_by(Content.source_id, CollectionItem.added_at.desc())
        elif sort == "theme":
            stmt = stmt.order_by(Content.theme, CollectionItem.added_at.desc())
        else:  # "recent" (default)
            stmt = stmt.order_by(CollectionItem.added_at.desc())

        stmt = stmt.limit(limit).offset(offset)
        result = await self.session.execute(stmt)
        rows = result.all()

        items = []
        for content, user_status, _added_at in rows:
            items.append(
                {
                    "id": content.id,
                    "title": content.title,
                    "url": content.url,
                    "thumbnail_url": content.thumbnail_url,
                    "content_type": content.content_type,
                    "duration_seconds": content.duration_seconds,
                    "published_at": content.published_at,
                    "source": content.source,
                    "description": content.description,
                    "topics": content.topics or [],
                    "is_paid": content.is_paid,
                    "status": user_status.status
                    if user_status
                    else ContentStatus.UNSEEN,
                    "is_saved": user_status.is_saved if user_status else False,
                    "is_liked": user_status.is_liked if user_status else False,
                    "is_hidden": user_status.is_hidden if user_status else False,
                    "hidden_reason": user_status.hidden_reason if user_status else None,
                }
            )

        return items

    async def add_to_collection(
        self, user_id: UUID, collection_id: UUID, content_id: UUID
    ) -> CollectionItem:
        """Ajoute un article à une collection."""
        # Verify ownership
        await self._get_user_collection(user_id, collection_id)

        # Check if already in collection
        existing_stmt = select(CollectionItem).where(
            CollectionItem.collection_id == collection_id,
            CollectionItem.content_id == content_id,
        )
        existing = await self.session.scalar(existing_stmt)
        if existing:
            return existing

        item = CollectionItem(
            collection_id=collection_id,
            content_id=content_id,
        )
        self.session.add(item)
        await self.session.flush()
        return item

    async def remove_from_collection(
        self, user_id: UUID, collection_id: UUID, content_id: UUID
    ) -> None:
        """Retire un article d'une collection (ne le désauvegarde pas)."""
        await self._get_user_collection(user_id, collection_id)

        stmt = delete(CollectionItem).where(
            CollectionItem.collection_id == collection_id,
            CollectionItem.content_id == content_id,
        )
        await self.session.execute(stmt)
        await self.session.flush()

    async def add_to_collections(
        self, user_id: UUID, content_id: UUID, collection_ids: list[UUID]
    ) -> None:
        """Ajoute un article à plusieurs collections d'un coup."""
        for cid in collection_ids:
            await self.add_to_collection(user_id, cid, content_id)

    async def get_saved_summary(self, user_id: UUID) -> dict:
        """Statistiques de sauvegardes pour les nudges."""
        now = datetime.utcnow()
        seven_days_ago = now - timedelta(days=7)

        # Total saved
        total_stmt = (
            select(func.count())
            .select_from(UserContentStatus)
            .where(
                UserContentStatus.user_id == user_id,
                UserContentStatus.is_saved,
            )
        )
        total_saved = await self.session.scalar(total_stmt) or 0

        # Unread saved (not CONSUMED)
        unread_stmt = (
            select(func.count())
            .select_from(UserContentStatus)
            .where(
                UserContentStatus.user_id == user_id,
                UserContentStatus.is_saved,
                UserContentStatus.status != ContentStatus.CONSUMED,
            )
        )
        unread_count = await self.session.scalar(unread_stmt) or 0

        # Recent (last 7 days)
        recent_stmt = (
            select(func.count())
            .select_from(UserContentStatus)
            .where(
                UserContentStatus.user_id == user_id,
                UserContentStatus.is_saved,
                UserContentStatus.saved_at >= seven_days_ago,
            )
        )
        recent_count = await self.session.scalar(recent_stmt) or 0

        # Top themes
        theme_stmt = (
            select(Content.theme, func.count().label("cnt"))
            .join(
                UserContentStatus,
                UserContentStatus.content_id == Content.id,
            )
            .where(
                UserContentStatus.user_id == user_id,
                UserContentStatus.is_saved,
                Content.theme.isnot(None),
            )
            .group_by(Content.theme)
            .order_by(func.count().desc())
            .limit(5)
        )
        theme_result = await self.session.execute(theme_stmt)
        top_themes = [{"theme": row[0], "count": row[1]} for row in theme_result.all()]

        return {
            "total_saved": total_saved,
            "unread_count": unread_count,
            "recent_count_7d": recent_count,
            "top_themes": top_themes,
        }

    async def _get_user_collection(
        self, user_id: UUID, collection_id: UUID
    ) -> Collection:
        """Récupère une collection en vérifiant la propriété."""
        stmt = select(Collection).where(
            Collection.id == collection_id,
            Collection.user_id == user_id,
        )
        collection = await self.session.scalar(stmt)
        if not collection:
            raise ValueError("Collection non trouvée")
        return collection
