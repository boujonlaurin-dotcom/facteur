"""Service de filtre temps-réel pour /api/veille/feed (Story 23.1).

Compose la config veille de l'utilisateur (thèmes/topics/sources/keywords) en
une clause `OR` SQL appliquée live sur `contents`. Boost les articles dont la
source matche la config (priorité dans le tri). Aucun appel LLM — pur SQL.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from uuid import UUID

from sqlalchemy import case, exists, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus
from app.models.source import Source
from app.models.veille import (
    VeilleConfig,
    VeilleKeyword,
    VeilleSource,
    VeilleStatus,
    VeilleTopic,
)
from app.services.recommendation.filter_presets import (
    apply_serein_filter,
    load_serein_preferences,
)


@dataclass
class VeilleFilters:
    """Filtres chargés depuis une VeilleConfig active."""

    themes: list[str] = field(default_factory=list)
    topic_slugs: list[str] = field(default_factory=list)
    source_ids: list[UUID] = field(default_factory=list)
    keywords: list[str] = field(default_factory=list)

    def has_any(self) -> bool:
        return bool(
            self.themes or self.topic_slugs or self.source_ids or self.keywords
        )


async def _get_active_config(
    session: AsyncSession, user_id: UUID
) -> VeilleConfig | None:
    stmt = select(VeilleConfig).where(
        VeilleConfig.user_id == user_id,
        VeilleConfig.status == VeilleStatus.ACTIVE.value,
    )
    return (await session.execute(stmt)).scalars().first()


async def load_veille_filters(
    session: AsyncSession, config: VeilleConfig
) -> VeilleFilters:
    """Charge topics/sources/keywords liés à la config en 3 SELECT indexés."""
    topics = (
        (
            await session.execute(
                select(VeilleTopic.topic_id).where(
                    VeilleTopic.veille_config_id == config.id
                )
            )
        )
        .scalars()
        .all()
    )
    sources = (
        (
            await session.execute(
                select(VeilleSource.source_id).where(
                    VeilleSource.veille_config_id == config.id
                )
            )
        )
        .scalars()
        .all()
    )
    keywords = (
        (
            await session.execute(
                select(VeilleKeyword.keyword)
                .where(VeilleKeyword.veille_config_id == config.id)
                .order_by(VeilleKeyword.position)
            )
        )
        .scalars()
        .all()
    )
    return VeilleFilters(
        themes=[config.theme_id] if config.theme_id else [],
        topic_slugs=list(topics),
        source_ids=list(sources),
        keywords=list(keywords),
    )


def build_or_predicate(filters: VeilleFilters):
    """Construit la clause `OR` SQL combinant les 4 axes du filtre.

    - `theme` : Content.theme IN (themes) — index ix_contents_theme_published
    - `topic` : Content.topics && topic_slugs — index GIN ix_contents_topics
    - `source` : Content.source_id IN (source_ids) — index ix_contents_source_id
    - `keyword` : title ILIKE OR description ILIKE — pas d'index trigramme V1,
      benchmark requis (cf. R1 Story 23.1).
    """
    clauses = []
    if filters.themes:
        clauses.append(Content.theme.in_(filters.themes))
    if filters.topic_slugs:
        clauses.append(Content.topics.overlap(filters.topic_slugs))
    if filters.source_ids:
        clauses.append(Content.source_id.in_(filters.source_ids))
    if filters.keywords:
        for kw in filters.keywords:
            pattern = f"%{kw}%"
            clauses.append(Content.title.ilike(pattern))
            clauses.append(Content.description.ilike(pattern))
    return or_(*clauses) if clauses else None


def _matched_axes(
    content: Content, filters: VeilleFilters
) -> list[str]:
    """Calcule sur quels axes l'article matche (info exposée au front)."""
    axes: list[str] = []
    if filters.themes and content.theme in filters.themes:
        axes.append("theme")
    if filters.topic_slugs and content.topics:
        topic_set = set(filters.topic_slugs)
        if any(t in topic_set for t in content.topics):
            axes.append("topic")
    if filters.source_ids and content.source_id in filters.source_ids:
        axes.append("source")
    if filters.keywords:
        title_lower = (content.title or "").lower()
        desc_lower = (content.description or "").lower()
        if any(kw in title_lower or kw in desc_lower for kw in filters.keywords):
            axes.append("keyword")
    return axes


async def fetch_veille_feed(
    session: AsyncSession,
    user_id: UUID,
    *,
    limit: int = 20,
    offset: int = 0,
    serein: bool = False,
) -> tuple[list[tuple[Content, list[str]]], bool]:
    """Récupère le feed veille filtré pour `user_id`.

    Returns (items_with_axes, has_more). `items_with_axes` est la liste paginée
    de tuples (Content hydraté, axes matchés). `has_more` est dérivé d'un
    fetch limit+1 pour éviter un COUNT séparé.

    Si aucune config active OU filtres vides → liste vide (200 OK avec items=[]).
    """
    config = await _get_active_config(session, user_id)
    if config is None:
        return [], False

    filters = await load_veille_filters(session, config)
    if not filters.has_any():
        return [], False

    predicate = build_or_predicate(filters)
    if predicate is None:
        return [], False

    exclude_user_status = exists().where(
        UserContentStatus.content_id == Content.id,
        UserContentStatus.user_id == user_id,
        or_(
            UserContentStatus.is_hidden,
            UserContentStatus.status.in_(
                [ContentStatus.SEEN, ContentStatus.CONSUMED]
            ),
        ),
    )

    query = (
        select(Content)
        .join(Content.source)
        .options(selectinload(Content.source))
        .where(~exclude_user_status)
        .where(predicate)
        .where(Source.is_active.is_(True))
    )

    if serein:
        serein_prefs = await load_serein_preferences(session, user_id)
        query = apply_serein_filter(
            query,
            sensitive_themes=serein_prefs.sensitive_themes,
            excluded_topics=serein_prefs.excluded_topics,
        )

    if filters.source_ids:
        source_boost = case(
            (Content.source_id.in_(filters.source_ids), 1), else_=0
        ).desc()
        query = query.order_by(source_boost, Content.published_at.desc())
    else:
        query = query.order_by(Content.published_at.desc())

    rows = (
        (await session.execute(query.limit(limit + 1).offset(offset)))
        .scalars()
        .all()
    )
    has_more = len(rows) > limit
    items = rows[:limit]
    return [(c, _matched_axes(c, filters)) for c in items], has_more
