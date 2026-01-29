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
from app.services.rss_parser import RSSParser


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
                is_trusted=True,
                content_count=0,  # TODO
                bias_stance=s.bias_stance.value,
                reliability_score=s.reliability_score.value,
                bias_origin=s.bias_origin.value,
                score_independence=s.score_independence,
                score_rigor=s.score_rigor,
                score_ux=s.score_ux,
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
                bias_stance=s.bias_stance.value,
                reliability_score=s.reliability_score.value,
                bias_origin=s.bias_origin.value,
                score_independence=s.score_independence,
                score_rigor=s.score_rigor,
                score_ux=s.score_ux,
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
            if source.theme == "custom":
                 source.theme = self._guess_theme(source.name, source.description or "")
        else:
            # Créer la nouvelle source
            source = Source(
                id=uuid4(),
                name=name or detection.name,
                url=url,
                feed_url=detection.feed_url,
                type=detection.detected_type,
                theme=self._guess_theme(name or detection.name, detection.description or ""),
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

        # Trigger immediate sync in background
        from app.workers.rss_sync import sync_source
        import asyncio
        asyncio.create_task(sync_source(str(source.id)))
        logger.info("Triggered background sync for new source", source_id=source.id)

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
            is_trusted=True,
            content_count=0,
            bias_stance=source.bias_stance.value,
            reliability_score=source.reliability_score.value,
            bias_origin=source.bias_origin.value,
            score_independence=source.score_independence,
            score_rigor=source.score_rigor,
            score_ux=source.score_ux,
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
        
        # Decommission YouTube for now
        if "youtube.com" in url or "youtu.be" in url:
            raise ValueError("YouTube handles are currently disabled. Please use RSS feeds for newsletters or journals.")

        # Use new Smart Detect
        try:
            detected = await self.rss_parser.detect(url)
            
            latest_titles = []
            if detected.entries:
                latest_titles = [e["title"] for e in detected.entries[:3]]
                
            # Map feed_type to valid SourceType
            source_type = detected.feed_type
            if source_type in ("rss", "atom"):
                source_type = "article"
                
            return SourceDetectResponse(
                detected_type=source_type,
                feed_url=detected.feed_url,
                name=detected.title,
                description=detected.description,
                logo_url=detected.logo_url,
                theme=self._guess_theme(detected.title, detected.description or ""),
                preview={
                    "item_count": len(detected.entries),
                    "latest_title": detected.entries[0].get("title") if detected.entries else None,
                },
            )
        except ValueError as e:
            # Fallback for youtube if smart detect fails but structure looks like youtube?
            # Actually RSSParser handles youtube better now.
            raise ValueError(f"Unable to parse URL as RSS feed: {str(e)}")

    async def _get_source_by_feed_url(self, feed_url: str) -> Optional[Source]:
        """Récupère une source par son feed_url."""
        query = select(Source).where(Source.feed_url == feed_url)
        result = await self.db.execute(query)
        return result.scalars().first()

    def _guess_theme(self, name: str, description: str) -> str:
        """Devine le thème d'une source à partir de son nom et description."""
        text = f"{name} {description}".lower()
        
        keywords = {
            "tech": ["ai", "ia", "tech", "crypto", "web3", "digital", "logiciel", "startup", "innov", "code", "dev"],
            "society_climate": ["société", "santé", "justice", "éduc", "travail", "fémin", "urban", "logement", "climat", "écolo", "environ", "vert", "durable", "énergi", "transit", "biodiv"],
            "economy": ["économ", "financ", "marché", "inflat", "business", "argent", "bourse"],
            "politics": ["politi", "élection", "démocra", "gouvern", "activis", "loi"],
            "culture_ideas": ["cultur", "philoso", "art", "cinéma", "livre", "média", "idée", "littérat", "musique"],
            "science": ["scien", "recherch", "physiq", "biolo", "espace", "laborat"],
            "geopolitics": ["géopolit", "internation", "monde", "diploma", "guerre", "conflit"],
        }
        
        scores = {t: 0 for t in keywords}
        for theme, kws in keywords.items():
            for kw in kws:
                if kw in text:
                    scores[theme] += 1
        
        best_theme = max(scores, key=scores.get)
        if scores[best_theme] > 0:
            return best_theme
            
        return "society_climate" # Default common theme for better recs vs 'custom'

