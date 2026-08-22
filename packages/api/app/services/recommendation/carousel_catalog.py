"""Catalogue des carrousels Phase B (DB-driven), partagé entre Flâner et l'Essentiel.

Story 32.1 — extraction (quasi verbatim) de la logique de
`RecommendationService._build_carousels` pour les 4 types DB-driven :
`saved`, `quiet_sources`, `new_source`, `community`.

Chaque type = une coroutine `build_<type>(ctx) -> CarouselContent | None`. Les
builds n'appliquent QUE des exclusions **surface-indépendantes** — articles
*consommés* (`consumed_ids`) et, pour les carrousels de découverte, articles
déjà *triés* dans la pile Essentiel (`triaged_ids`) — jamais les `promoted_ids`
propres à Flâner (complémentarité déterministe entre Flâner et l'Essentiel,
cf. `carousel_selection_service.pick_essentiel_type`).

Le carrousel `community` est **unifié** : il passe désormais par
`CommunityRecommendationService.get_top_recommendations` (tri decay = récence +
nombre de tournesols), consommé aussi bien par Flâner que par l'Essentiel.
"""

from __future__ import annotations

import datetime
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field, replace
from uuid import UUID

import structlog
from sqlalchemy import desc, func, literal, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import SessionMaker
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, InterestState
from app.models.essentiel_triage import EssentielTriageDecision
from app.models.source import Source, UserSource

# Sérialisation vers le schéma API partagé (même mapping que routers/feed.py).
from app.schemas.feed import CarouselInfo, CarouselItemBadge
from app.services.community_recommendation_service import (
    CommunityRecommendationService,
)

# Import du MODULE (pas des noms) pour que les tests qui patchent
# `randomization.compute_seed` atteignent bien les appels ci-dessous — le
# rebinding par-nom au load figerait la référence avant le patch.
from app.services.recommendation import randomization
from app.utils.time import today_paris

logger = structlog.get_logger()

FOLLOWED_SOURCE_STATES = (InterestState.FOLLOWED, InterestState.FAVORITE)

# Seuils repris de `_build_carousels` (mêmes valeurs).
MIN_CAROUSEL_ITEMS = 3  # community / saved
MIN_DISPLAY_ITEMS = 2  # quiet_sources / new_source
MAX_CAROUSEL_ITEMS = 5
# « Tes sources discrètes » est un filet de dernier recours (Volet B, grief PO
# n°2) : 3 items max, jamais plus vieux que la fenêtre de la sonde d'éligibilité.
QUIET_SOURCES_MAX_ITEMS = 3
QUIET_SOURCE_WINDOW_DAYS = 30


@dataclass
class CarouselContent:
    """Un carrousel construit (avant sérialisation en `CarouselInfo`)."""

    carousel_type: str
    title: str
    emoji: str
    items: list[Content]
    badges: list[dict]

    def excluding(self, exclude_ids: set[UUID], max_items: int) -> CarouselContent:
        """Nouvelle copie sans les items exclus (badges alignés), capée à `max_items`.

        Utilisé par Flâner pour retirer les articles déjà promus en Phase A / dans
        un carrousel Phase B précédent, et par l'Essentiel pour ne pas re-servir un
        des articles déjà affichés dans la carte.
        """
        pairs = [
            (it, bd)
            for it, bd in zip(self.items, self.badges, strict=False)
            if it.id not in exclude_ids
        ][:max_items]
        return replace(
            self,
            items=[p[0] for p in pairs],
            badges=[p[1] for p in pairs],
        )

    def to_carousel_info(self, position: int) -> CarouselInfo:
        """Sérialise en `CarouselInfo` (schéma API). Même mapping que
        `routers/feed.py` : les `Content` sont validés en `FeedItemResponse` via
        `from_attributes`, les badges convertis en `CarouselItemBadge`."""
        return CarouselInfo(
            carousel_type=self.carousel_type,
            title=self.title,
            emoji=self.emoji,
            position=position,
            items=self.items,
            badges=[CarouselItemBadge(**b) for b in self.badges],
        )


@dataclass
class CarouselBuildContext:
    """Entrées communes aux builds Phase B."""

    session: AsyncSession
    session_maker: SessionMaker
    user_id: UUID
    consumed_ids: set[UUID]
    # Articles déjà triés dans la pile Essentiel (keep/later/pass) — exclus des
    # carrousels de découverte, jamais de `saved` (cf. `fetch_triaged_ids`).
    # Default additif : les call sites existants restent valides sans lui.
    triaged_ids: set[UUID] = field(default_factory=set)

    @property
    def discovery_excluded_ids(self) -> set[UUID]:
        """Exclusions des carrousels de DÉCOUVERTE : consommés ∪ triés.

        La règle vit ici, pas dans chaque builder : `quiet_sources`,
        `new_source` et `community` l'appliquent ; `build_saved` s'en passe
        volontairement (`later` = article sauvegardé, que « Plus tard, c'est
        maintenant ! » doit re-servir).
        """
        return self.consumed_ids | self.triaged_ids


async def fetch_consumed_ids(session: AsyncSession, user_id: UUID) -> set[UUID]:
    """Articles déjà consommés par l'utilisateur — exclus de tous les carrousels.

    Règle unique partagée par Flâner (`_build_carousels`) et l'Essentiel
    (`_enrich_essentiel_carousel`) : l'ensemble éligible est **surface-indépendant**
    (exclusion `consumed` seulement), condition de la complémentarité déterministe.
    """
    rows = (
        (
            await session.execute(
                select(UserContentStatus.content_id).where(
                    UserContentStatus.user_id == user_id,
                    UserContentStatus.status == ContentStatus.CONSUMED,
                )
            )
        )
        .scalars()
        .all()
    )
    return set(rows)


async def fetch_triaged_ids(
    session: AsyncSession, user_id: UUID, days: int = 90
) -> set[UUID]:
    """Articles déjà triés (keep/later/pass) dans la pile Essentiel.

    Mémoire d'exclusion des carrousels de découverte (`quiet_sources`,
    `new_source`, `community`) : un « pass » n'écrit jamais le statut CONSUMED,
    donc sans elle le même article revenait chaque jour. Surface-indépendante,
    comme `fetch_consumed_ids` (même exigence de complémentarité déterministe).

    `build_saved` ne l'applique PAS : `decision=later` marque l'article sauvegardé
    (`set_save_status`), et « Plus tard, c'est maintenant ! » doit précisément
    pouvoir le re-servir.
    """
    since = today_paris() - datetime.timedelta(days=days)
    rows = (
        (
            await session.execute(
                select(EssentielTriageDecision.content_id).where(
                    EssentielTriageDecision.user_id == user_id,
                    EssentielTriageDecision.digest_date >= since,
                )
            )
        )
        .scalars()
        .all()
    )
    return set(rows)


async def build_new_source(ctx: CarouselBuildContext) -> CarouselContent | None:
    """« Récemment ajouté : X » — articles de LA source ajoutée récemment (T3).

    Rotation jour à jour : collecte toutes les sources récentes valides puis en
    tire UNE seedée par le jour (cooldown post-add 6 h, borne 8 sondes).
    """
    MIN_NEW_SOURCE_ITEMS = 2
    session = ctx.session
    seven_days_ago = datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=7)

    new_src_rows = (
        await session.execute(
            select(
                UserSource.source_id,
                Source.name,
                UserSource.added_at,
            )
            .join(Source, Source.id == UserSource.source_id)
            .where(
                UserSource.user_id == ctx.user_id,
                UserSource.state.in_(FOLLOWED_SOURCE_STATES),
                UserSource.added_at > seven_days_ago,
            )
            .order_by(UserSource.added_at.desc())
        )
    ).all()

    MAX_NEW_SOURCE_PROBES = 8
    now = datetime.datetime.now(datetime.UTC)
    candidates: list[tuple] = []
    excluded_ids = ctx.discovery_excluded_ids
    for src_row in new_src_rows[:MAX_NEW_SOURCE_PROBES]:
        exclusions = []
        if excluded_ids:
            exclusions.append(Content.id.notin_(excluded_ids))
        items = list(
            (
                await session.scalars(
                    select(Content)
                    .options(selectinload(Content.source))
                    .where(
                        Content.source_id == src_row.source_id,
                        Content.published_at > seven_days_ago,
                        *exclusions,
                    )
                    .order_by(Content.published_at.desc())
                    .limit(MAX_CAROUSEL_ITEMS)
                )
            ).all()
        )
        if len(items) < MIN_NEW_SOURCE_ITEMS:
            continue
        # Cooldown post-add 6 h — laisse les articles remonter dans le main feed
        # avant de pousser un carrousel « Récemment ajouté ».
        source_age_seconds = (now - src_row.added_at).total_seconds()
        if source_age_seconds < 6 * 3600:
            continue
        candidates.append((src_row, items, source_age_seconds))

    if not candidates:
        return None

    seed = randomization.compute_seed(str(ctx.user_id), "daily")
    src_row, items, _age = randomization.seeded_shuffle(candidates, seed)[0]
    badge = {"code": "new_source", "label": "Nouvelle source", "emoji": "\U0001f195"}
    return CarouselContent(
        carousel_type="new_source",
        title=f"Récemment ajouté : {src_row.name}",
        emoji="\U0001f195",
        items=items,
        badges=[badge] * len(items),
    )


async def build_quiet_sources(ctx: CarouselBuildContext) -> CarouselContent | None:
    """« Tes sources discrètes » — dernier article des sources suivies peu actives.

    Filet de **dernier recours** (Volet B) : 3 items max, sous-ensemble stable la
    journée (seed daily md5), tournant d'un jour à l'autre, jamais un article déjà
    consommé ou trié, jamais plus vieux que la fenêtre de la sonde (30 j).

    Sonde LATERAL ... LIMIT 3 sur une short session capée 8s/5s (PYTHON-5N). Tout
    le bloc est fail-soft : une erreur DB SKIP le carrousel (renvoie None) au lieu
    de remonter.
    """
    QUIET_SOURCE_MAX_RECENT = 3  # < 3 articles en 30 jours = « discrète »
    now = datetime.datetime.now(datetime.UTC)
    # Fenêtre unique sonde + service : une source dont les 1-2 articles récents
    # sont tous consommés/triés sort du carrousel au lieu de servir un article
    # de 45 j (l'ancienne fenêtre de service à 60 j servait du 31-60 j).
    window_start = now - datetime.timedelta(days=QUIET_SOURCE_WINDOW_DAYS)

    quiet_articles: list[Content] = []
    try:
        probe = (
            select(Content.id)
            .where(
                Content.source_id == UserSource.source_id,
                Content.published_at >= window_start,
            )
            .limit(QUIET_SOURCE_MAX_RECENT)
            .lateral()
        )
        quiet_ids_stmt = (
            select(UserSource.source_id)
            .select_from(UserSource)
            .join(Source, Source.id == UserSource.source_id)
            .join(probe, literal(True))
            .where(
                UserSource.user_id == ctx.user_id,
                UserSource.state.in_(FOLLOWED_SOURCE_STATES),
                Source.is_active.is_(True),
            )
            .group_by(UserSource.source_id)
            .having(func.count() < QUIET_SOURCE_MAX_RECENT)
        )
        async with ctx.session_maker(
            statement_timeout_ms=8_000, idle_in_tx_timeout_ms=5_000
        ) as quiet_s:
            quiet_source_ids = list((await quiet_s.scalars(quiet_ids_stmt)).all())
            if quiet_source_ids:
                conds = [
                    Content.source_id.in_(quiet_source_ids),
                    Content.published_at >= window_start,
                ]
                excluded_ids = ctx.discovery_excluded_ids
                if excluded_ids:
                    conds.append(Content.id.notin_(excluded_ids))
                latest_per_source = (
                    select(Content)
                    .options(selectinload(Content.source))
                    .where(*conds)
                    .distinct(Content.source_id)
                    .order_by(Content.source_id, Content.published_at.desc())
                )
                quiet_articles = list((await quiet_s.scalars(latest_per_source)).all())
        # Seed daily ET stable inter-process (md5) : le sous-ensemble ne bouge
        # ni dans la journée, ni entre workers/redéploiements — `compute_seed`
        # repose sur `hash()`, randomisé par PYTHONHASHSEED.
        seed = randomization.compute_stable_seed(
            str(ctx.user_id), today_paris().isoformat()
        )
        quiet_articles = randomization.seeded_shuffle(quiet_articles, seed)[
            :QUIET_SOURCES_MAX_ITEMS
        ]
    except Exception as exc:
        logger.warning(
            "carousel_quiet_sources_skipped",
            error=str(exc),
            exc_type=type(exc).__name__,
        )
        return None

    if len(quiet_articles) < MIN_DISPLAY_ITEMS:
        return None
    badges = [
        {"code": "quiet_source", "label": a.source.name, "emoji": "\U0001f50d"}
        for a in quiet_articles
    ]
    return CarouselContent(
        carousel_type="quiet_sources",
        title="Tes sources discrètes",
        emoji="\U0001f92b",
        items=quiet_articles,
        badges=badges,
    )


async def build_community(ctx: CarouselBuildContext) -> CarouselContent | None:
    """« Recos de la communauté » 🌻 — unifié via `get_top_recommendations`.

    Tri decay (`SUM(1/(1+heures/48))`) = récence + nombre de tournesols. Badge
    « 🌻 N » si ≥ 2 tournesols, sinon « Reco communauté ».
    """
    service = CommunityRecommendationService(ctx.session)
    excluded_ids = ctx.discovery_excluded_ids
    recs = await service.get_top_recommendations(
        limit=MAX_CAROUSEL_ITEMS,
        exclude_ids=excluded_ids or None,
    )
    if len(recs) < MIN_CAROUSEL_ITEMS:
        return None

    items = [r["content"] for r in recs]
    badges = []
    for r in recs:
        sf_count = int(r.get("sunflower_count", 0))
        label = f"\U0001f33b {sf_count}" if sf_count >= 2 else "Reco communauté"
        badges.append({"code": "community", "label": label, "emoji": "\U0001f33b"})
    return CarouselContent(
        carousel_type="community",
        title="Recos de la communauté",
        emoji="\U0001f33b",
        items=items,
        badges=badges,
    )


async def build_saved(ctx: CarouselBuildContext) -> CarouselContent | None:
    """« Plus tard, c'est maintenant ! » — articles sauvegardés non consommés."""
    items = list(
        (
            await ctx.session.scalars(
                select(Content)
                .options(selectinload(Content.source))
                .join(
                    UserContentStatus,
                    UserContentStatus.content_id == Content.id,
                )
                .where(
                    UserContentStatus.user_id == ctx.user_id,
                    UserContentStatus.is_saved.is_(True),
                    UserContentStatus.status != ContentStatus.CONSUMED,
                )
                .order_by(
                    desc(
                        func.coalesce(
                            UserContentStatus.saved_at,
                            UserContentStatus.created_at,
                        )
                    )
                )
                .limit(MAX_CAROUSEL_ITEMS)
            )
        ).all()
    )

    if len(items) < MIN_CAROUSEL_ITEMS:
        return None

    badges = []
    for item in items:
        ct = item.content_type
        if ct == ContentType.YOUTUBE:
            badges.append(
                {
                    "code": "saved_video",
                    "label": "Vidéo sauvegardée",
                    "emoji": "\U0001f4cc",
                }
            )
        elif ct == ContentType.PODCAST:
            badges.append(
                {
                    "code": "saved_audio",
                    "label": "Audio sauvegardé",
                    "emoji": "\U0001f4cc",
                }
            )
        else:
            badges.append(
                {
                    "code": "saved_article",
                    "label": "Article sauvegardé",
                    "emoji": "\U0001f4cc",
                }
            )
    return CarouselContent(
        carousel_type="saved",
        title="Plus tard, c’est maintenant !",
        emoji="\U0001f4cc",
        items=items,
        badges=badges,
    )


@dataclass(frozen=True)
class CarouselSpec:
    """Un type de carrousel Phase B : code, seuil d'émission, builder."""

    code: str
    min_items: int
    build: Callable[[CarouselBuildContext], Awaitable[CarouselContent | None]]


# Registre ordonné par priorité métier (base positions). L'ordre pilote à la fois
# l'éligibilité (priorité) et la rotation `pick_essentiel_type`.
PHASE_B_SPECS: tuple[CarouselSpec, ...] = (
    CarouselSpec("quiet_sources", MIN_DISPLAY_ITEMS, build_quiet_sources),
    CarouselSpec("saved", MIN_CAROUSEL_ITEMS, build_saved),
    CarouselSpec("new_source", MIN_DISPLAY_ITEMS, build_new_source),
    CarouselSpec("community", MIN_CAROUSEL_ITEMS, build_community),
)

MIN_ITEMS_BY_CODE: dict[str, int] = {
    spec.code: spec.min_items for spec in PHASE_B_SPECS
}

# Ordre métier stable (dérivé du registre → une seule source de vérité) : pilote
# la priorité d'éligibilité de Flâner ET la rotation date-seedée du type mis en
# avant dans l'Essentiel (`carousel_selection_service`).
PHASE_B_ORDER: tuple[str, ...] = tuple(spec.code for spec in PHASE_B_SPECS)
