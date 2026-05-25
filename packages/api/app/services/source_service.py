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

    async def _load_user_source_context(
        self, user_id: UUID
    ) -> tuple[set[UUID], dict[UUID, float], dict[UUID, bool]]:
        """Charge trusted_ids, multipliers et subscriptions en une seule query.

        Remplace les trois appels séparés (_load_user_source_multipliers,
        _load_user_source_subscriptions, SELECT source_id) par une unique
        query combinée — réduit le nombre de round-trips DB de 3 à 1.
        Fix partiel PYTHON-46 / PYTHON-1W (N+1 sur sources).
        """
        result = await self.db.execute(
            select(
                UserSource.source_id,
                UserSource.priority_multiplier,
                UserSource.has_subscription,
            ).where(UserSource.user_id == user_id)
        )
        rows = result.all()
        trusted_ids = {row.source_id for row in rows}
        multipliers = {row.source_id: row.priority_multiplier for row in rows}
        subscriptions = {row.source_id: row.has_subscription for row in rows}
        return trusted_ids, multipliers, subscriptions

    def _build_source_response(
        self,
        s: Source,
        *,
        is_curated: bool,
        is_custom: bool,
        is_trusted: bool,
        muted_source_ids: set[UUID],
        multipliers: dict[UUID, float],
        subscriptions: dict[UUID, bool],
        follower_count: int = 0,
    ) -> SourceResponse:
        """Construit un SourceResponse à partir d'un objet Source et du contexte user.

        Helper synchrone pur — élimine la duplication du bloc SourceResponse(...)
        présent dans get_all_sources, get_curated_sources, get_trending_sources, etc.
        """
        return SourceResponse(
            id=s.id,
            name=s.name,
            url=s.url,
            type=s.type,
            theme=s.theme,
            description=s.description,
            logo_url=s.logo_url,
            is_curated=is_curated,
            is_custom=is_custom,
            is_trusted=is_trusted,
            is_muted=s.id in muted_source_ids,
            priority_multiplier=multipliers.get(s.id, 1.0),
            has_subscription=subscriptions.get(s.id, False),
            content_count=0,  # TODO
            follower_count=follower_count,
            bias_stance=getattr(s.bias_stance, "value", "unknown"),
            reliability_score=getattr(s.reliability_score, "value", "unknown"),
            bias_origin=getattr(s.bias_origin, "value", "unknown"),
            score_independence=s.score_independence,
            score_rigor=s.score_rigor,
            score_ux=s.score_ux,
            recommended_by=getattr(s, "recommended_by", None),
            recommendation_reason=getattr(s, "recommendation_reason", None),
        )

    async def get_all_sources(self, user_id: str) -> SourceCatalogResponse:
        """Récupère toutes les sources (curées + custom).

        Optimisé : 4 queries au lieu de 8 (fix PYTHON-46 / PYTHON-1W N+1).
        Les données user (trusted_ids, multipliers, subscriptions, muted) sont
        chargées une seule fois et partagées entre curated et custom, éliminant
        les 4 queries redondantes de l'implémentation précédente qui appelait
        get_curated_sources() puis re-chargeait les mêmes données.

        Combiné avec le fix du router (session ouverte après lock), résout
        l'IdleInTransactionSessionTimeout lors de l'onboarding (PYTHON-4R / 3C).
        """
        user_uuid = UUID(user_id)

        # 1 query combinée : trusted_ids + multipliers + subscriptions
        (
            trusted_source_ids,
            multipliers,
            subscriptions,
        ) = await self._load_user_source_context(user_uuid)

        # 1 query : muted sources via UserPersonalization
        muted_source_ids: set[UUID] = set()
        personalization = await self.db.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
        )
        if personalization and personalization.muted_sources:
            muted_source_ids = set(personalization.muted_sources)

        # 1 query : sources curées
        curated_result = await self.db.execute(
            select(Source).where(Source.is_curated, Source.is_active)
        )
        curated = [
            self._build_source_response(
                s,
                is_curated=True,
                is_custom=False,
                is_trusted=s.id in trusted_source_ids,
                muted_source_ids=muted_source_ids,
                multipliers=multipliers,
                subscriptions=subscriptions,
            )
            for s in curated_result.scalars().all()
        ]

        # 1 query : sources custom (distinct pour éviter doublons user_sources)
        custom_result = await self.db.execute(
            select(Source)
            .join(UserSource)
            .where(
                UserSource.user_id == user_uuid,
                ~Source.is_curated,
            )
            .distinct()
        )
        custom = [
            self._build_source_response(
                s,
                is_curated=False,
                is_custom=True,
                is_trusted=True,  # les sources custom sont toujours trusted
                muted_source_ids=muted_source_ids,
                multipliers=multipliers,
                subscriptions=subscriptions,
            )
            for s in custom_result.scalars().all()
        ]

        return SourceCatalogResponse(curated=curated, custom=custom)

    async def get_curated_sources(
        self, user_id: str | None = None
    ) -> list[SourceResponse]:
        """Récupère les sources curées.

        Optimisé : 3 queries au lieu de 5 (trusted_ids + multipliers +
        subscriptions chargés en une seule query via _load_user_source_context).
        """
        curated_result = await self.db.execute(
            select(Source).where(Source.is_curated, Source.is_active)
        )
        sources = curated_result.scalars().all()

        trusted_source_ids: set[UUID] = set()
        muted_source_ids: set[UUID] = set()
        multipliers: dict[UUID, float] = {}
        subscriptions: dict[UUID, bool] = {}

        if user_id:
            user_uuid = UUID(user_id)
            (
                trusted_source_ids,
                multipliers,
                subscriptions,
            ) = await self._load_user_source_context(user_uuid)
            personalization = await self.db.scalar(
                select(UserPersonalization).where(
                    UserPersonalization.user_id == user_uuid
                )
            )
            if personalization and personalization.muted_sources:
                muted_source_ids = set(personalization.muted_sources)

        return [
            self._build_source_response(
                s,
                is_curated=True,
                is_custom=False,
                is_trusted=s.id in trusted_source_ids,
                muted_source_ids=muted_source_ids,
                multipliers=multipliers,
                subscriptions=subscriptions,
            )
            for s in sources
        ]

    async def get_trending_sources(
        self, user_id: str, limit: int = 10
    ) -> list[SourceResponse]:
        """Récupère les sources les plus populaires de la communauté."""
        count_col = func.count(UserSource.user_id).label("follower_count")
        result = await self.db.execute(
            select(Source, count_col)
            .join(UserSource)
            .where(Source.is_active)
            .where(~Source.is_curated)
            .group_by(Source.id)
            .order_by(count_col.desc())
            .limit(limit)
        )
        rows = result.all()  # list of (Source, follower_count) tuples

        user_uuid = UUID(user_id)
        (
            trusted_source_ids,
            multipliers,
            subscriptions,
        ) = await self._load_user_source_context(user_uuid)

        muted_source_ids: set[UUID] = set()
        personalization = await self.db.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_uuid)
        )
        if personalization and personalization.muted_sources:
            muted_source_ids = set(personalization.muted_sources)

        return [
            self._build_source_response(
                s,
                is_curated=s.is_curated,
                is_custom=not s.is_curated,
                is_trusted=s.id in trusted_source_ids,
                muted_source_ids=muted_source_ids,
                multipliers=multipliers,
                subscriptions=subscriptions,
                follower_count=follower_count,
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

        trusted_source_ids: set[UUID] = set()
        muted_source_ids: set[UUID] = set()
        multipliers: dict[UUID, float] = {}
        subscriptions: dict[UUID, bool] = {}
        if user_id:
            user_uuid = UUID(user_id)
            (
                trusted_source_ids,
                multipliers,
                subscriptions,
            ) = await self._load_user_source_context(user_uuid)
            personalization = await self.db.scalar(
                select(UserPersonalization).where(
                    UserPersonalization.user_id == user_uuid
                )
            )
            if personalization and personalization.muted_sources:
                muted_source_ids = set(personalization.muted_sources)

        return [
            self._build_source_response(
                s,
                is_curated=s.is_curated,
                is_custom=not s.is_curated,
                is_trusted=s.id in trusted_source_ids,
                muted_source_ids=muted_source_ids,
                multipliers=multipliers,
                subscriptions=subscriptions,
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
            recommended_by=getattr(source, "recommended_by", None),
            recommendation_reason=getattr(source, "recommendation_reason", None),
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
            recommended_by=getattr(source, "recommended_by", None),
            recommendation_reason=getattr(source, "recommendation_reason", None),
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
