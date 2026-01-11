"""Service source."""

from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.source import Source, UserSource
from app.models.content import Content
from app.schemas.source import (
    SourceCatalogResponse,
    SourceDetectResponse,
    SourceResponse,
)
from app.utils.rss_parser import RSSParser
from app.utils.youtube_utils import extract_youtube_channel_id, get_youtube_rss_url


class SourceService:
    """Service pour la gestion des sources."""

    def __init__(self, db: AsyncSession):
        self.db = db
        self.rss_parser = RSSParser()

    async def get_all_sources(self, user_id: str) -> SourceCatalogResponse:
        """Récupère toutes les sources (curées + custom)."""
        user_uuid = UUID(user_id)

        # Sources curées
        curated = await self.get_curated_sources(user_id)

        # Sources custom de l'utilisateur
        query = (
            select(Source)
            .join(UserSource)
            .where(
                UserSource.user_id == user_uuid,
                UserSource.is_custom == True,
            )
        )
        result = await self.db.execute(query)
        custom_sources = result.scalars().all()

        custom = [
            SourceResponse(
                id=s.id,
                name=s.name,
                url=s.url,
                type=s.type,
                theme=s.theme,
                description=s.description,
                logo_url=s.logo_url,
                is_curated=False,
                is_custom=True,
                content_count=0,  # TODO
            )
            for s in custom_sources
        ]

        return SourceCatalogResponse(curated=curated, custom=custom)

    async def get_curated_sources(self, user_id: Optional[str] = None) -> list[SourceResponse]:
        """Récupère les sources curées."""
        query = select(Source).where(Source.is_curated == True, Source.is_active == True)
        result = await self.db.execute(query)
        sources = result.scalars().all()

        trusted_source_ids = set()
        if user_id:
            user_sources_query = select(UserSource.source_id).where(
                UserSource.user_id == UUID(user_id)
            )
            user_sources_result = await self.db.execute(user_sources_query)
            trusted_source_ids = set(user_sources_result.scalars().all())

        return [
            SourceResponse(
                id=s.id,
                name=s.name,
                url=s.url,
                type=s.type,
                theme=s.theme,
                description=s.description,
                logo_url=s.logo_url,
                is_curated=True,
                is_custom=False,
                is_trusted=s.id in trusted_source_ids,
                content_count=0,  # TODO
            )
            for s in sources
        ]

    async def add_custom_source(
        self,
        user_id: str,
        url: str,
        name: Optional[str] = None,
    ) -> SourceResponse:
        """Ajoute une source personnalisée."""
        # Détecter le type de source
        detection = await self.detect_source(url)

        # Vérifier si la source existe déjà
        existing = await self._get_source_by_feed_url(detection.feed_url)

        if existing:
            source = existing
        else:
            # Créer la nouvelle source
            source = Source(
                id=uuid4(),
                name=name or detection.name,
                url=url,
                feed_url=detection.feed_url,
                type=detection.detected_type,
                theme="custom",  # Les sources custom n'ont pas de thème défini
                description=detection.description,
                logo_url=detection.logo_url,
                is_curated=False,
                is_active=True,
            )
            self.db.add(source)

        # Lier à l'utilisateur
        user_source = UserSource(
            id=uuid4(),
            user_id=UUID(user_id),
            source_id=source.id,
            is_custom=True,
        )
        self.db.add(user_source)

        await self.db.flush()

        return SourceResponse(
            id=source.id,
            name=source.name,
            url=source.url,
            type=source.type,
            theme=source.theme,
            description=source.description,
            logo_url=source.logo_url,
            is_curated=False,
            is_custom=True,
            content_count=0,
        )

    async def delete_custom_source(self, user_id: str, source_id: str) -> bool:
        """Supprime une source personnalisée."""
        query = select(UserSource).where(
            UserSource.user_id == UUID(user_id),
            UserSource.source_id == UUID(source_id),
            UserSource.is_custom == True,
        )
        result = await self.db.execute(query)
        user_source = result.scalar_one_or_none()

        if not user_source:
            return False

        await self.db.delete(user_source)
        await self.db.flush()

        return True

    async def trust_source(self, user_id: str, source_id: str) -> bool:
        """Ajoute une source aux sources de confiance de l'utilisateur."""
        # Vérifier si la source existe (curée ou non, mais active)
        source_query = select(Source).where(Source.id == UUID(source_id), Source.is_active == True)
        source_result = await self.db.execute(source_query)
        source = source_result.scalar_one_or_none()

        if not source:
            return False

        # Vérifier si déjà trusted
        existing_query = select(UserSource).where(
            UserSource.user_id == UUID(user_id),
            UserSource.source_id == UUID(source_id),
        )
        existing_result = await self.db.execute(existing_query)
        existing = existing_result.scalar_one_or_none()

        if existing:
            return True

        # Ajouter
        user_source = UserSource(
            id=uuid4(),
            user_id=UUID(user_id),
            source_id=UUID(source_id),
            is_custom=False,  # Par définition ici
        )
        self.db.add(user_source)
        await self.db.flush()
        return True

    async def untrust_source(self, user_id: str, source_id: str) -> bool:
        """Retire une source des sources de confiance."""
        query = select(UserSource).where(
            UserSource.user_id == UUID(user_id),
            UserSource.source_id == UUID(source_id),
        )
        result = await self.db.execute(query)
        user_source = result.scalar_one_or_none()

        if not user_source:
            return False

        await self.db.delete(user_source)
        await self.db.flush()
        return True

    async def detect_source(self, url: str) -> SourceDetectResponse:
        """Détecte le type d'une URL source."""
        # Vérifier si c'est YouTube
        channel_id = extract_youtube_channel_id(url)
        if channel_id:
            feed_url = get_youtube_rss_url(channel_id)
            feed_data = await self.rss_parser.parse(feed_url)

            return SourceDetectResponse(
                detected_type="youtube",
                feed_url=feed_url,
                name=feed_data.get("title", "YouTube Channel"),
                description=feed_data.get("description"),
                logo_url=None,
                preview={
                    "item_count": len(feed_data.get("entries", [])),
                    "latest_title": feed_data.get("entries", [{}])[0].get("title"),
                },
            )

        # Tenter de parser comme RSS
        try:
            feed_data = await self.rss_parser.parse(url)

            # Détecter si c'est un podcast (enclosures audio)
            entries = feed_data.get("entries", [])
            is_podcast = any(
                "enclosure" in entry or "audio" in str(entry.get("links", []))
                for entry in entries[:5]
            )

            return SourceDetectResponse(
                detected_type="podcast" if is_podcast else "article",
                feed_url=url,
                name=feed_data.get("title", "RSS Feed"),
                description=feed_data.get("description"),
                logo_url=feed_data.get("image", {}).get("href"),
                preview={
                    "item_count": len(entries),
                    "latest_title": entries[0].get("title") if entries else None,
                },
            )
        except Exception as e:
            raise ValueError(f"Unable to parse URL as RSS feed: {str(e)}")

    async def _get_source_by_feed_url(self, feed_url: str) -> Optional[Source]:
        """Récupère une source par son feed_url."""
        query = select(Source).where(Source.feed_url == feed_url)
        result = await self.db.execute(query)
        return result.scalar_one_or_none()

