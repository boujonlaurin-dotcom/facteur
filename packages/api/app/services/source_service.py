"""Service source."""

from uuid import UUID, uuid4

import structlog
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.source import Source, UserSource
from app.models.user_personalization import UserPersonalization
from app.schemas.source import (
    SourceCatalogResponse,
    SourceDetectResponse,
    SourceResponse,
)
from app.services.rss_parser import RSSParser

logger = structlog.get_logger()


class SourceService:
    """Service pour la gestion des sources."""

    def __init__(self, db: AsyncSession):
        self.db = db
        self.rss_parser = RSSParser()

    async def _load_user_source_multipliers(self, user_id: UUID) -> dict[UUID, float]:
        """Load priority_multiplier for all user sources."""
        result = await self.db.execute(
            select(UserSource.source_id, UserSource.priority_multiplier).where(
                UserSource.user_id == user_id
            )
        )
        return {row.source_id: row.priority_multiplier for row in result.all()}

    async def _load_user_source_subscriptions(self, user_id: UUID) -> dict[UUID, bool]:
        """Load has_subscription for all user sources."""
        result = await self.db.execute(
            select(UserSource.source_id, UserSource.has_subscription).where(
                UserSource.user_id == user_id
            )
        )
        return {row.source_id: row.has_subscription for row in result.all()}

    async def get_all_sources(self, user_id: str) -> SourceCatalogResponse:
        """Récupère toutes les sources (curées + custom)."""
        user_uuid = UUID(user_id)

        # Load muted sources for is_muted flag
        muted_source_ids = set()
        personalization = await self.db.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
        )
        if personalization and personalization.muted_sources:
            muted_source_ids = set(personalization.muted_sources)

        # Sources curées
        curated = await self.get_curated_sources(user_id)

        # Load priority multipliers and subscriptions
        multipliers = await self._load_user_source_multipliers(user_uuid)
        subscriptions = await self._load_user_source_subscriptions(user_uuid)

        # Sources custom de l'utilisateur (distinct au cas où doublons user_sources)
        query = (
            select(Source)
            .join(UserSource)
            .where(
                UserSource.user_id == user_uuid,
                ~Source.is_curated,
            )
            .distinct()
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
                is_muted=s.id in muted_source_ids,
                priority_multiplier=multipliers.get(s.id, 1.0),
                has_subscription=subscriptions.get(s.id, False),
                content_count=0,  # TODO
                bias_stance=getattr(s.bias_stance, "value", "unknown"),
                reliability_score=getattr(s.reliability_score, "value", "unknown"),
                bias_origin=getattr(s.bias_origin, "value", "unknown"),
                score_independence=s.score_independence,
                score_rigor=s.score_rigor,
                score_ux=s.score_ux,
                editorial_note=getattr(s, "editorial_note", None),
            )
            for s in custom_sources
        ]

        return SourceCatalogResponse(curated=curated, custom=custom)

    async def get_curated_sources(
        self, user_id: str | None = None
    ) -> list[SourceResponse]:
        """Récupère les sources curées."""
        query = select(Source).where(Source.is_curated, Source.is_active)
        result = await self.db.execute(query)
        sources = result.scalars().all()

        trusted_source_ids = set()
        muted_source_ids = set()
        multipliers: dict[UUID, float] = {}
        subscriptions: dict[UUID, bool] = {}
        if user_id:
            user_uuid = UUID(user_id)
            user_sources_query = select(UserSource.source_id).where(
                UserSource.user_id == user_uuid
            )
            user_sources_result = await self.db.execute(user_sources_query)
            trusted_source_ids = set(user_sources_result.scalars().all())

            multipliers = await self._load_user_source_multipliers(user_uuid)
            subscriptions = await self._load_user_source_subscriptions(user_uuid)

            personalization = await self.db.scalar(
                select(UserPersonalization).where(
                    UserPersonalization.user_id == user_uuid
                )
            )
            if personalization and personalization.muted_sources:
                muted_source_ids = set(personalization.muted_sources)

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
                is_muted=s.id in muted_source_ids,
                priority_multiplier=multipliers.get(s.id, 1.0),
                has_subscription=subscriptions.get(s.id, False),
                content_count=0,  # TODO
                bias_stance=getattr(s.bias_stance, "value", "unknown"),
                reliability_score=getattr(s.reliability_score, "value", "unknown"),
                bias_origin=getattr(s.bias_origin, "value", "unknown"),
                score_independence=s.score_independence,
                score_rigor=s.score_rigor,
                score_ux=s.score_ux,
                editorial_note=getattr(s, "editorial_note", None),
            )
            for s in sources
        ]

    async def get_trending_sources(
        self, user_id: str, limit: int = 10
    ) -> list[SourceResponse]:
        """Récupère les sources les plus populaires de la communauté."""
        count_col = func.count(UserSource.user_id).label("follower_count")
        query = (
            select(Source, count_col)
            .join(UserSource)
            .where(Source.is_active)
            .where(~Source.is_curated)
            .group_by(Source.id)
            .order_by(count_col.desc())
            .limit(limit)
        )

        result = await self.db.execute(query)
        rows = result.all()  # list of (Source, follower_count) tuples

        # Check trusted & muted status for the current user
        user_uuid = UUID(user_id)

        user_sources_query = select(UserSource.source_id).where(
            UserSource.user_id == user_uuid
        )
        user_sources_result = await self.db.execute(user_sources_query)
        trusted_source_ids = set(user_sources_result.scalars().all())

        multipliers = await self._load_user_source_multipliers(user_uuid)
        subscriptions = await self._load_user_source_subscriptions(user_uuid)

        muted_source_ids = set()
        personalization = await self.db.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
        )
        if personalization and personalization.muted_sources:
            muted_source_ids = set(personalization.muted_sources)

        return [
            SourceResponse(
                id=s.id,
                name=s.name,
                url=s.url,
                type=s.type,
                theme=s.theme,
                description=s.description,
                logo_url=s.logo_url,
                is_curated=s.is_curated,
                is_custom=not s.is_curated,
                is_trusted=s.id in trusted_source_ids,
                is_muted=s.id in muted_source_ids,
                priority_multiplier=multipliers.get(s.id, 1.0),
                has_subscription=subscriptions.get(s.id, False),
                content_count=0,
                follower_count=follower_count,
                bias_stance=getattr(s.bias_stance, "value", "unknown"),
                reliability_score=getattr(s.reliability_score, "value", "unknown"),
                bias_origin=getattr(s.bias_origin, "value", "unknown"),
                score_independence=s.score_independence,
                score_rigor=s.score_rigor,
                score_ux=s.score_ux,
                editorial_note=getattr(s, "editorial_note", None),
            )
            for s, follower_count in rows
        ]

    async def search_sources(
        self, query: str, limit: int = 10, user_id: str | None = None
    ) -> list[SourceResponse]:
        """Recherche des sources par mots-clés dans la base de données."""
        search_query = (
            select(Source)
            .where(
                Source.is_active,
                (Source.name.ilike(f"%{query}%")) | (Source.url.ilike(f"%{query}%")),
            )
            .order_by(Source.created_at.desc())
            .limit(limit)
        )

        result = await self.db.execute(search_query)
        sources = result.scalars().all()

        # Load user context for is_trusted / is_muted flags
        trusted_source_ids = set()
        muted_source_ids = set()
        multipliers: dict[UUID, float] = {}
        subscriptions: dict[UUID, bool] = {}
        if user_id:
            user_uuid = UUID(user_id)
            user_sources_result = await self.db.execute(
                select(UserSource.source_id).where(UserSource.user_id == user_uuid)
            )
            trusted_source_ids = set(user_sources_result.scalars().all())

            multipliers = await self._load_user_source_multipliers(user_uuid)
            subscriptions = await self._load_user_source_subscriptions(user_uuid)

            personalization = await self.db.scalar(
                select(UserPersonalization).where(
                    UserPersonalization.user_id == user_uuid
                )
            )
            if personalization and personalization.muted_sources:
                muted_source_ids = set(personalization.muted_sources)

        return [
            SourceResponse(
                id=s.id,
                name=s.name,
                url=s.url,
                type=s.type,
                theme=s.theme,
                description=s.description,
                logo_url=s.logo_url,
                is_curated=s.is_curated,
                is_custom=not s.is_curated,
                is_trusted=s.id in trusted_source_ids,
                is_muted=s.id in muted_source_ids,
                priority_multiplier=multipliers.get(s.id, 1.0),
                has_subscription=subscriptions.get(s.id, False),
                content_count=0,
                bias_stance=getattr(s.bias_stance, "value", "unknown"),
                reliability_score=getattr(s.reliability_score, "value", "unknown"),
                bias_origin=getattr(s.bias_origin, "value", "unknown"),
                score_independence=s.score_independence,
                score_rigor=s.score_rigor,
                score_ux=s.score_ux,
                editorial_note=getattr(s, "editorial_note", None),
            )
            for s in sources
        ]

    async def add_custom_source(
        self,
        user_id: str,
        url: str,
        name: str | None = None,
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
                theme=self._guess_theme(
                    name or detection.name, detection.description or ""
                ),
                description=detection.description,
                logo_url=detection.logo_url,
                is_curated=False,
                is_active=True,
            )
            self.db.add(source)

        # Idempotence : ne pas créer de doublon (user_id, source_id) si déjà lié
        user_uuid = UUID(user_id)
        existing_link = await self.db.execute(
            select(UserSource).where(
                UserSource.user_id == user_uuid,
                UserSource.source_id == source.id,
            )
        )
        if existing_link.scalar_one_or_none() is None:
            user_source = UserSource(
                id=uuid4(),
                user_id=user_uuid,
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
            is_trusted=True,
            content_count=0,
            bias_stance=getattr(source.bias_stance, "value", "unknown"),
            reliability_score=getattr(source.reliability_score, "value", "unknown"),
            bias_origin=getattr(source.bias_origin, "value", "unknown"),
            score_independence=source.score_independence,
            score_rigor=source.score_rigor,
            score_ux=source.score_ux,
            editorial_note=getattr(source, "editorial_note", None),
        )

    async def delete_custom_source(self, user_id: str, source_id: str) -> bool:
        """Supprime une source personnalisée."""
        query = select(UserSource).where(
            UserSource.user_id == UUID(user_id),
            UserSource.source_id == UUID(source_id),
            UserSource.is_custom,
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
        source_query = select(Source).where(
            Source.id == UUID(source_id), Source.is_active
        )
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
            is_custom=not source.is_curated,
        )
        self.db.add(user_source)

        # Auto-unmute: following a source removes it from muted list
        personalization = await self.db.scalar(
            select(UserPersonalization).where(
                UserPersonalization.user_id == UUID(user_id)
            )
        )
        if (
            personalization
            and personalization.muted_sources
            and UUID(source_id) in personalization.muted_sources
        ):
            personalization.muted_sources = [
                s for s in personalization.muted_sources if s != UUID(source_id)
            ]

        await self.db.flush()
        return True

    async def update_source_weight(
        self, user_id: str, source_id: str, priority_multiplier: float
    ) -> SourceResponse | None:
        """Met à jour le priority_multiplier d'une source suivie."""
        user_uuid = UUID(user_id)
        source_uuid = UUID(source_id)

        user_source = await self.db.scalar(
            select(UserSource).where(
                UserSource.user_id == user_uuid,
                UserSource.source_id == source_uuid,
            )
        )
        if not user_source:
            return None

        user_source.priority_multiplier = priority_multiplier
        await self.db.flush()

        source = await self.db.scalar(select(Source).where(Source.id == source_uuid))
        if not source:
            return None

        # Load muted status
        muted_source_ids = set()
        personalization = await self.db.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
        )
        if personalization and personalization.muted_sources:
            muted_source_ids = set(personalization.muted_sources)

        logger.info(
            "source_weight_updated",
            user_id=user_id,
            source_id=source_id,
            multiplier=priority_multiplier,
        )

        return SourceResponse(
            id=source.id,
            name=source.name,
            url=source.url,
            type=source.type,
            theme=source.theme,
            description=source.description,
            logo_url=source.logo_url,
            is_curated=source.is_curated,
            is_custom=user_source.is_custom,
            is_trusted=True,
            is_muted=source.id in muted_source_ids,
            priority_multiplier=priority_multiplier,
            has_subscription=user_source.has_subscription,
            content_count=0,
            bias_stance=getattr(source.bias_stance, "value", "unknown"),
            reliability_score=getattr(source.reliability_score, "value", "unknown"),
            bias_origin=getattr(source.bias_origin, "value", "unknown"),
            score_independence=source.score_independence,
            score_rigor=source.score_rigor,
            score_ux=source.score_ux,
            editorial_note=getattr(source, "editorial_note", None),
        )

    async def update_source_subscription(
        self, user_id: str, source_id: str, has_subscription: bool
    ) -> SourceResponse | None:
        """Met à jour le has_subscription d'une source suivie."""
        user_uuid = UUID(user_id)
        source_uuid = UUID(source_id)

        user_source = await self.db.scalar(
            select(UserSource).where(
                UserSource.user_id == user_uuid,
                UserSource.source_id == source_uuid,
            )
        )
        if not user_source:
            return None

        user_source.has_subscription = has_subscription
        await self.db.flush()

        source = await self.db.scalar(select(Source).where(Source.id == source_uuid))
        if not source:
            return None

        # Load muted status
        muted_source_ids = set()
        personalization = await self.db.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
        )
        if personalization and personalization.muted_sources:
            muted_source_ids = set(personalization.muted_sources)

        logger.info(
            "source_subscription_updated",
            user_id=user_id,
            source_id=source_id,
            has_subscription=has_subscription,
        )

        return SourceResponse(
            id=source.id,
            name=source.name,
            url=source.url,
            type=source.type,
            theme=source.theme,
            description=source.description,
            logo_url=source.logo_url,
            is_curated=source.is_curated,
            is_custom=user_source.is_custom,
            is_trusted=True,
            is_muted=source.id in muted_source_ids,
            priority_multiplier=user_source.priority_multiplier,
            has_subscription=has_subscription,
            content_count=0,
            bias_stance=getattr(source.bias_stance, "value", "unknown"),
            reliability_score=getattr(source.reliability_score, "value", "unknown"),
            bias_origin=getattr(source.bias_origin, "value", "unknown"),
            score_independence=source.score_independence,
            score_rigor=source.score_rigor,
            score_ux=source.score_ux,
            editorial_note=getattr(source, "editorial_note", None),
        )

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
        try:
            detected = await self.rss_parser.detect(url)

            existing = await self._get_source_by_feed_url(detected.feed_url)

            latest_titles = []
            if detected.entries:
                latest_titles = [
                    e.get("title", "Sans titre") for e in detected.entries[:3]
                ]

            # Map feed_type to valid SourceType
            # "youtube" and "reddit" pass through as-is
            source_type = detected.feed_type
            if source_type in ("rss", "atom"):
                source_type = "article"

            return SourceDetectResponse(
                source_id=existing.id if existing else None,
                detected_type=source_type,
                feed_url=detected.feed_url,
                name=detected.title,
                description=detected.description,
                logo_url=detected.logo_url,
                theme=existing.theme
                if existing
                else self._guess_theme(detected.title, detected.description or ""),
                preview={
                    "item_count": len(detected.entries),
                    "latest_titles": latest_titles,
                },
                bias_stance=getattr(existing.bias_stance, "value", "unknown")
                if existing
                else "unknown",
                reliability_score=getattr(
                    existing.reliability_score, "value", "unknown"
                )
                if existing
                else "unknown",
                bias_origin=getattr(existing.bias_origin, "value", "unknown")
                if existing
                else "unknown",
            )
        except ValueError as e:
            # Fallback for youtube if smart detect fails but structure looks like youtube?
            # Actually RSSParser handles youtube better now.
            raise ValueError(f"Unable to parse URL as RSS feed: {str(e)}")

    async def _get_source_by_feed_url(self, feed_url: str) -> Source | None:
        """Récupère une source par son feed_url."""
        query = select(Source).where(Source.feed_url == feed_url)
        result = await self.db.execute(query)
        return result.scalars().first()

    def _guess_theme(self, name: str, description: str) -> str:
        """Devine le thème d'une source à partir de son nom et description."""
        text = f"{name} {description}".lower()

        keywords = {
            "tech": [
                "ai",
                "ia",
                "tech",
                "crypto",
                "web3",
                "digital",
                "logiciel",
                "startup",
                "innov",
                "code",
                "dev",
            ],
            "society": [
                "société",
                "santé",
                "justice",
                "éduc",
                "travail",
                "fémin",
                "urban",
                "logement",
            ],
            "environment": [
                "climat",
                "écolo",
                "environ",
                "vert",
                "durable",
                "énergi",
                "transit",
                "biodiv",
            ],
            "economy": [
                "économ",
                "financ",
                "marché",
                "inflat",
                "business",
                "argent",
                "bourse",
            ],
            "politics": ["politi", "élection", "démocra", "gouvern", "activis", "loi"],
            "culture": [
                "cultur",
                "philoso",
                "art",
                "cinéma",
                "livre",
                "média",
                "idée",
                "littérat",
                "musique",
            ],
            "science": ["scien", "recherch", "physiq", "biolo", "espace", "laborat"],
            "international": [
                "géopolit",
                "internation",
                "monde",
                "diploma",
                "guerre",
                "conflit",
            ],
        }

        scores = dict.fromkeys(keywords, 0)
        for theme, kws in keywords.items():
            for kw in kws:
                if kw in text:
                    scores[theme] += 1

        best_theme = max(scores, key=scores.get)
        if scores[best_theme] > 0:
            return best_theme

        return "society"  # Default common theme for better recs vs 'custom'
