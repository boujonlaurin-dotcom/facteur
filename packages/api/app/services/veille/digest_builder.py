"""Construit la liste d'items pour une livraison de veille.

Invariant : zéro session DB tenue pendant l'appel LLM. Sessions ouvertes
via `session_maker` (typiquement `safe_async_session`) et fermées entre
chaque phase.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import SessionMaker
from app.models.content import Content
from app.models.veille import VeilleConfig, VeilleSource, VeilleTopic
from app.services.briefing.importance_detector import ImportanceDetector, TopicCluster
from app.services.editorial.llm_client import EditorialLLMClient

logger = structlog.get_logger()

DEFAULT_LOOKBACK_DAYS = 7
DEFAULT_TOP_N_CLUSTERS = 8
DEFAULT_MAX_ARTICLES_PER_CLUSTER = 5
DEFAULT_EXCERPT_LENGTH = 280
_FETCH_CONTENTS_LIMIT = 500


@dataclass
class VeilleDigestInput:
    config_id: UUID
    user_topic_ids: list[str]
    user_topic_labels: list[str]
    user_source_ids: list[UUID]
    last_delivered_at: datetime | None
    theme_id: str
    theme_label: str


class VeilleDigestBuilder:
    """Génère les `items` d'une livraison à partir d'une config veille."""

    def __init__(
        self,
        llm: EditorialLLMClient,
        session_maker: SessionMaker,
        top_n: int = DEFAULT_TOP_N_CLUSTERS,
        max_articles_per_cluster: int = DEFAULT_MAX_ARTICLES_PER_CLUSTER,
        lookback_days: int = DEFAULT_LOOKBACK_DAYS,
    ) -> None:
        self.llm = llm
        self.session_maker = session_maker
        self.detector = ImportanceDetector()
        self.top_n = top_n
        self.max_articles_per_cluster = max_articles_per_cluster
        self.lookback_days = lookback_days

    async def build(self, config_id: UUID) -> list[dict]:
        async with self.session_maker() as s:
            ctx = await self._load_input(s, config_id)

        if not ctx.user_source_ids or not ctx.user_topic_ids:
            logger.info(
                "veille_pipeline.skip_empty_config",
                config_id=str(config_id),
                source_count=len(ctx.user_source_ids),
                topic_count=len(ctx.user_topic_ids),
            )
            return []

        async with self.session_maker() as s:
            contents = await self._fetch_contents(s, ctx)

        if not contents:
            logger.info(
                "veille_pipeline.no_contents",
                config_id=str(config_id),
                since=ctx.last_delivered_at.isoformat()
                if ctx.last_delivered_at
                else None,
            )
            return []

        all_clusters = self.detector.build_topic_clusters(contents)
        relevant = self._filter_clusters_for_topics(all_clusters, ctx.user_topic_ids)
        top_clusters = self._top_n_clusters(relevant)

        if not top_clusters:
            logger.info(
                "veille_pipeline.no_relevant_clusters",
                config_id=str(config_id),
                total_clusters=len(all_clusters),
            )
            return []

        why_map = await self._generate_why_it_matters(top_clusters, ctx)

        items = self._build_items(top_clusters, why_map)
        logger.info(
            "veille_pipeline.items_built",
            config_id=str(config_id),
            item_count=len(items),
            article_count=sum(len(it["articles"]) for it in items),
        )
        return items

    async def _load_input(self, s: AsyncSession, config_id: UUID) -> VeilleDigestInput:
        # Une seule AsyncSession ne peut servir qu'une requête à la fois
        # (`InterfaceError: another operation is in progress`) — on garde
        # les 3 SELECT séquentiels.
        cfg = (
            (await s.execute(select(VeilleConfig).where(VeilleConfig.id == config_id)))
            .scalars()
            .first()
        )
        if cfg is None:
            raise ValueError(f"VeilleConfig introuvable: {config_id}")
        topics = (
            (
                await s.execute(
                    select(VeilleTopic).where(VeilleTopic.veille_config_id == config_id)
                )
            )
            .scalars()
            .all()
        )
        sources = (
            (
                await s.execute(
                    select(VeilleSource).where(
                        VeilleSource.veille_config_id == config_id
                    )
                )
            )
            .scalars()
            .all()
        )
        return VeilleDigestInput(
            config_id=cfg.id,
            user_topic_ids=[t.topic_id for t in topics],
            user_topic_labels=[t.label for t in topics],
            user_source_ids=[s.source_id for s in sources],
            last_delivered_at=cfg.last_delivered_at,
            theme_id=cfg.theme_id,
            theme_label=cfg.theme_label,
        )

    async def _fetch_contents(
        self, s: AsyncSession, ctx: VeilleDigestInput
    ) -> list[Content]:
        since = ctx.last_delivered_at or (
            datetime.now(UTC) - timedelta(days=self.lookback_days)
        )
        stmt = (
            select(Content)
            .where(
                Content.source_id.in_(ctx.user_source_ids),
                Content.published_at >= since,
                Content.topics.op("&&")(ctx.user_topic_ids),
            )
            .order_by(Content.published_at.desc())
            .limit(_FETCH_CONTENTS_LIMIT)
        )
        return list((await s.execute(stmt)).scalars().all())

    def _filter_clusters_for_topics(
        self, clusters: list[TopicCluster], user_topic_ids: list[str]
    ) -> list[TopicCluster]:
        topic_set = set(user_topic_ids)
        return [
            c
            for c in clusters
            if any(
                content.topics and topic_set.intersection(content.topics)
                for content in c.contents
            )
        ]

    def _top_n_clusters(self, clusters: list[TopicCluster]) -> list[TopicCluster]:
        return sorted(
            clusters,
            key=lambda c: (len(c.contents), len(c.source_ids)),
            reverse=True,
        )[: self.top_n]

    async def _generate_why_it_matters(
        self, clusters: list[TopicCluster], ctx: VeilleDigestInput
    ) -> dict[str, str]:
        if not self.llm.is_ready:
            return self._fallback_why_it_matters(clusters)
        response = await self.llm.chat_json(
            system=(
                "Tu es éditeur de veille thématique pour Facteur. Pour chaque "
                "cluster d'articles, tu rédiges UNE phrase (max 220 caractères) "
                "expliquant en quoi ce sujet est pertinent pour un lecteur "
                "intéressé par les topics donnés. Ton: factuel, concret, pas "
                "de lyrisme. Réponds UNIQUEMENT en JSON: "
                '{"clusters": {"<cluster_id>": "<why_it_matters>"}}.'
            ),
            user_message=self._build_prompt(clusters, ctx),
            temperature=0.3,
            max_tokens=1500,
        )
        mapping = response.get("clusters") if isinstance(response, dict) else None
        if not isinstance(mapping, dict):
            logger.warning(
                "veille_pipeline.why_llm_invalid_response",
                response_type=type(response).__name__,
            )
            return self._fallback_why_it_matters(clusters)
        return {
            c.cluster_id: (
                str(mapping.get(c.cluster_id) or "").strip()
                or self._fallback_for_cluster(c)
            )
            for c in clusters
        }

    def _fallback_why_it_matters(self, clusters: list[TopicCluster]) -> dict[str, str]:
        return {c.cluster_id: self._fallback_for_cluster(c) for c in clusters}

    def _fallback_for_cluster(self, c: TopicCluster) -> str:
        n_articles = len(c.contents)
        n_sources = len(c.source_ids)
        if n_sources >= 2:
            return f"{n_articles} articles de {n_sources} sources couvrent ce sujet."
        return f"{n_articles} article(s) sur ce sujet."

    def _build_prompt(
        self, clusters: list[TopicCluster], ctx: VeilleDigestInput
    ) -> str:
        payload = {
            "theme": ctx.theme_label,
            "topics": ctx.user_topic_labels,
            "clusters": [
                {
                    "cluster_id": c.cluster_id,
                    "title_sample": self._derive_cluster_title(c),
                    "n_articles": len(c.contents),
                    "n_sources": len(c.source_ids),
                    "sample_titles": [
                        content.title[:160]
                        for content in sorted(
                            c.contents,
                            key=lambda x: x.published_at,
                            reverse=True,
                        )[:3]
                    ],
                }
                for c in clusters
            ],
        }
        return json.dumps(payload, ensure_ascii=False)

    def _build_items(
        self, clusters: list[TopicCluster], why_map: dict[str, str]
    ) -> list[dict]:
        items: list[dict] = []
        for c in clusters:
            articles = [
                {
                    "content_id": str(content.id),
                    "source_id": str(content.source_id),
                    "title": content.title,
                    "url": content.url,
                    "excerpt": (content.description or "")[:DEFAULT_EXCERPT_LENGTH],
                    "published_at": content.published_at.isoformat(),
                }
                for content in sorted(
                    c.contents, key=lambda x: x.published_at, reverse=True
                )[: self.max_articles_per_cluster]
            ]
            items.append(
                {
                    "cluster_id": c.cluster_id,
                    "title": self._derive_cluster_title(c),
                    "articles": articles,
                    "why_it_matters": why_map.get(c.cluster_id, ""),
                }
            )
        return items

    def _derive_cluster_title(self, c: TopicCluster) -> str:
        if not c.contents:
            return "Cluster veille"
        most_recent = max(c.contents, key=lambda x: x.published_at)
        return most_recent.title[:160]
