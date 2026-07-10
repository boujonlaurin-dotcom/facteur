"""Arrangement quotidien intelligent de la Tournée du jour (Story 22.3).

Construit les sections « Choisie pour vous » : thèmes / sources que l'utilisateur
**suit déjà** mais n'a **pas épinglés**, sélectionnés et ordonnés chaque jour par
un blend de signaux (préférence déclarée, poids appris, quantité de contenu
frais, qualité des sources), avec une variation quotidienne déterministe.

Invariants produit (PO) :
- Jamais de thème **hors préférences réelles** : la « surprise » = variation, pas
  découverte. L'élargissement « doux » reste borné aux sources dont le thème
  primaire est un thème déjà déclaré par l'utilisateur.
- Les sections **dédiées** (validées) ne passent jamais ici ; elles sont
  résolues en amont par `get_top_themes` et ne sont jamais masquées.
- Chaque suggérée porte une **raison vraie** (breakdown non vide construit à
  partir des seules composantes réellement > 0) : anti-boîte-noire testé.

Réutilise le pattern de variation déterministe de `topic_selector.py` / digest
(`compute_seed` + `randomized_sort`, basse température) pour un ordre stable dans
la journée et varié le lendemain.
"""

import math
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.enums import InterestState, ReliabilityScore
from app.models.source import Source, UserSource
from app.models.user import UserInterest
from app.models.user_personalization import UserPersonalization
from app.schemas.content import ScoreContribution
from app.services.recommendation.randomization import compute_seed, randomized_sort
from app.services.recommendation.scoring_config import ScoringWeights

logger = structlog.get_logger(__name__)

# Reliability → score qualité 0–1. On **lit** la colonne `reliability_score`
# (pas de recalcul du FQS) et on la projette sur une échelle continue.
_RELIABILITY_QUALITY: dict[ReliabilityScore, float] = {
    ReliabilityScore.HIGH: 1.0,
    ReliabilityScore.MIXED: 0.6,
    ReliabilityScore.MEDIUM: 0.5,
    ReliabilityScore.LOW: 0.2,
    ReliabilityScore.UNKNOWN: 0.4,
}
_DEFAULT_QUALITY = 0.4


@dataclass
class TourneeSuggestion:
    """Une section « Choisie pour vous » candidate, scorée pour aujourd'hui."""

    key: str  # "theme:<slug>" | "source:<id>"
    kind: str  # "theme" | "source"
    slug: str | None  # slug thème (thème direct, ou thème primaire d'une source)
    source_id: UUID | None
    label_name: str  # nom d'affichage (libellé thème ou nom de source)
    recent_count: int
    is_soft: bool  # issu de l'élargissement doux (source on-thème non suivie)

    # Composantes normalisées 0–1 du blend `daily_score`.
    explicit: float = 0.0
    measured: float = 0.0
    quantity: float = 0.0
    quality: float = 0.0
    daily_score: float = 0.0

    reason_label: str = ""
    breakdown: list[ScoreContribution] = field(default_factory=list)


class TourneeSuggester:
    """Orchestre la construction des suggestions « Choisie pour vous ».

    `arrange()` est le seul point d'entrée : il prend l'ensemble des slugs de
    thèmes **déjà validés** (rendus comme sections dédiées) pour ne jamais les
    re-suggérer, et un `sub_cap` = nombre de slots restants dans la Tournée.
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    async def arrange(
        self,
        user_id: UUID,
        validated_theme_slugs: set[str],
        sub_cap: int,
    ) -> list[TourneeSuggestion]:
        """Retourne au plus `sub_cap` suggestions, best-first pour aujourd'hui.

        Pipeline : pool (déclaré) → filtres durs (muted + plancher contenu) →
        score quotidien → variation déterministe → cap. Liste vide si rien ne
        passe (jour pauvre, 7 favoris, compte vide) : jamais d'empty-state suggéré.
        """
        if sub_cap <= 0:
            return []

        candidates = await self._build_pool(user_id, validated_theme_slugs, sub_cap)
        if not candidates:
            return []

        for c in candidates:
            c.daily_score = (
                ScoringWeights.TOURNEE_SUGGEST_W_EXPLICIT * c.explicit
                + ScoringWeights.TOURNEE_SUGGEST_W_MEASURED * c.measured
                + ScoringWeights.TOURNEE_SUGGEST_W_QUANTITY * c.quantity
                + ScoringWeights.TOURNEE_SUGGEST_W_QUALITY * c.quality
            )
            self._build_reason(c)

        # Variation quotidienne : seed daily (stable le jour, varié le lendemain).
        seed = compute_seed(str(user_id), granularity="daily")
        wrapped = [(c, c.daily_score) for c in candidates]
        randomized = randomized_sort(
            wrapped,
            temperature=ScoringWeights.TOURNEE_SUGGEST_TEMPERATURE,
            seed=seed,
        )
        ordered = [c for c, _ in randomized][:sub_cap]

        logger.info(
            "tournee_suggestions_arranged",
            user_id=str(user_id),
            pool=len(candidates),
            returned=len(ordered),
            sub_cap=sub_cap,
            themes=sum(1 for c in ordered if c.kind == "theme"),
            sources=sum(1 for c in ordered if c.kind == "source"),
        )
        return ordered

    # ── Pool ────────────────────────────────────────────────────────────────

    async def _build_pool(
        self,
        user_id: UUID,
        validated_theme_slugs: set[str],
        sub_cap: int,
    ) -> list[TourneeSuggestion]:
        """Construit le pool candidat issu du **déclaré**, filtres durs inclus.

        Les lectures ci-dessous sont indépendantes mais restent **séquentielles** :
        elles partagent l'`AsyncSession` du request scope, qui n'autorise pas de
        statements concurrents. Ne pas les `asyncio.gather` sans connexions
        dédiées (ça lèverait `InterfaceError: another operation is in progress`).
        """
        muted_themes, muted_sources = await self._load_muted(user_id)

        # Thèmes suivis (state followed), non validés, non mutés.
        interest_rows = (
            await self.db.execute(
                select(UserInterest.interest_slug, UserInterest.weight).where(
                    UserInterest.user_id == user_id,
                    UserInterest.state == InterestState.FOLLOWED,
                )
            )
        ).all()
        followed_themes: dict[str, float] = {
            row.interest_slug: row.weight or 1.0 for row in interest_rows
        }
        # Tous les thèmes déclarés (validés + suivis) — cible de l'élargissement doux.
        declared_theme_slugs = validated_theme_slugs | set(followed_themes)

        # Sources suivies (state followed) : candidates directes (les favorites
        # sont déjà rendues comme sections dédiées côté mobile).
        followed_source_ids = set(
            (
                await self.db.execute(
                    select(UserSource.source_id).where(
                        UserSource.user_id == user_id,
                        UserSource.state == InterestState.FOLLOWED,
                    )
                )
            )
            .scalars()
            .all()
        )

        # Catalogue sources actives (1 requête) : qualité par thème + résolution.
        source_rows = (
            await self.db.execute(
                select(
                    Source.id,
                    Source.name,
                    Source.theme,
                    Source.reliability_score,
                    Source.is_curated,
                ).where(Source.is_active)
            )
        ).all()
        source_by_id = {row.id: row for row in source_rows}
        theme_quality = self._theme_quality_map(source_rows)

        # Affinité source apprise (0–1) — réutilise la logique de reco.
        affinity = await self._source_affinity(user_id)

        theme_candidates: list[TourneeSuggestion] = []
        for slug, weight in followed_themes.items():
            if slug in validated_theme_slugs or slug in muted_themes:
                continue
            theme_candidates.append(
                TourneeSuggestion(
                    key=f"theme:{slug}",
                    kind="theme",
                    slug=slug,
                    source_id=None,
                    label_name=slug,
                    recent_count=0,
                    is_soft=False,
                    explicit=1.0,
                    measured=_clamp01(weight - 1.0),
                    quality=theme_quality.get(slug, _DEFAULT_QUALITY),
                )
            )

        source_candidates: list[TourneeSuggestion] = []
        for sid in followed_source_ids:
            if sid in muted_sources:
                continue
            row = source_by_id.get(sid)
            if row is None:
                continue
            source_candidates.append(
                self._source_candidate(row, affinity, is_soft=False)
            )

        # Élargissement doux : si le pool est sous le cap, on complète avec des
        # sources **curées** dont le thème primaire est un thème déjà déclaré
        # (préférence réelle via le thème), non suivies, non mutées.
        soft_candidates: list[TourneeSuggestion] = []
        if len(theme_candidates) + len(source_candidates) < sub_cap:
            already = followed_source_ids | muted_sources
            soft_limit = max(sub_cap * 2, 4)
            for row in source_rows:
                if len(soft_candidates) >= soft_limit:
                    break
                if not row.is_curated:
                    continue
                if row.theme not in declared_theme_slugs:
                    continue
                if row.id in already:
                    continue
                soft_candidates.append(
                    self._source_candidate(row, affinity, is_soft=True)
                )

        candidates = theme_candidates + source_candidates + soft_candidates
        if not candidates:
            return []

        # Comptes de contenu récent (plancher dur). Deux requêtes groupées.
        await self._attach_recent_counts(candidates)

        floor = ScoringWeights.TOURNEE_SUGGEST_CONTENT_FLOOR
        kept: list[TourneeSuggestion] = []
        saturation = ScoringWeights.TOURNEE_SUGGEST_QUANTITY_SATURATION
        for c in candidates:
            if c.recent_count < floor:
                continue
            c.quantity = _log_saturate(c.recent_count, saturation)
            kept.append(c)
        return kept

    async def _load_muted(self, user_id: UUID) -> tuple[set[str], set[UUID]]:
        perso = await self.db.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_id)
        )
        if perso is None:
            return set(), set()
        return set(perso.muted_themes or []), set(perso.muted_sources or [])

    def _source_candidate(
        self, row, affinity: dict[UUID, float], *, is_soft: bool
    ) -> TourneeSuggestion:
        quality = _RELIABILITY_QUALITY.get(row.reliability_score, _DEFAULT_QUALITY)
        return TourneeSuggestion(
            key=f"source:{row.id}",
            kind="source",
            slug=row.theme,
            source_id=row.id,
            label_name=row.name,
            recent_count=0,
            is_soft=is_soft,
            explicit=ScoringWeights.TOURNEE_SUGGEST_SOFT_EXPLICIT if is_soft else 1.0,
            measured=affinity.get(row.id, 0.0),
            quality=quality,
        )

    def _theme_quality_map(self, source_rows) -> dict[str, float]:
        """Qualité moyenne (reliability) des sources actives, par thème."""
        sums: dict[str, float] = {}
        counts: dict[str, int] = {}
        for row in source_rows:
            if not row.theme:
                continue
            q = _RELIABILITY_QUALITY.get(row.reliability_score, _DEFAULT_QUALITY)
            sums[row.theme] = sums.get(row.theme, 0.0) + q
            counts[row.theme] = counts.get(row.theme, 0) + 1
        return {t: sums[t] / counts[t] for t in sums}

    async def _source_affinity(self, user_id: UUID) -> dict[UUID, float]:
        """Affinité source apprise (0–1). Best-effort : `{}` si indisponible."""
        try:
            from app.services.recommendation_service import RecommendationService

            return await RecommendationService(self.db)._compute_source_affinity(
                user_id
            )
        except Exception as exc:  # pragma: no cover — defensive
            logger.warning("tournee_source_affinity_failed", error=str(exc))
            return {}

    async def _attach_recent_counts(self, candidates: list[TourneeSuggestion]) -> None:
        cutoff = datetime.now(UTC) - timedelta(
            days=ScoringWeights.TOURNEE_SUGGEST_RECENCY_DAYS
        )
        theme_slugs = [c.slug for c in candidates if c.kind == "theme" and c.slug]
        source_ids = [c.source_id for c in candidates if c.kind == "source"]

        theme_counts: dict[str, int] = {}
        if theme_slugs:
            rows = (
                await self.db.execute(
                    select(Content.theme, func.count(Content.id))
                    .where(
                        Content.theme.in_(theme_slugs),
                        Content.published_at >= cutoff,
                    )
                    .group_by(Content.theme)
                )
            ).all()
            theme_counts = {row[0]: row[1] for row in rows}

        source_counts: dict[UUID, int] = {}
        if source_ids:
            rows = (
                await self.db.execute(
                    select(Content.source_id, func.count(Content.id))
                    .where(
                        Content.source_id.in_(source_ids),
                        Content.published_at >= cutoff,
                    )
                    .group_by(Content.source_id)
                )
            ).all()
            source_counts = {row[0]: row[1] for row in rows}

        for c in candidates:
            if c.kind == "theme":
                c.recent_count = theme_counts.get(c.slug, 0)
            else:
                c.recent_count = source_counts.get(c.source_id, 0)

    # ── Transparence ──────────────────────────────────────────────────────────

    def _build_reason(self, c: TourneeSuggestion) -> None:
        """Construit `reason_label` + `breakdown` depuis les composantes > 0.

        Invariant : le breakdown n'est **jamais vide** (au pire la seule
        « Varié pour aujourd'hui »), et chaque puce reflète une composante
        réellement présente — pas de raison fabriquée.
        """
        contribs: list[tuple[float, ScoreContribution]] = []

        if c.explicit > 0:
            if c.kind == "source" and not c.is_soft:
                label = "Tu suis cette source"
            elif c.is_soft:
                label = "Sur un thème que tu suis"
            else:
                label = "Tu suis ce thème"
            weighted = ScoringWeights.TOURNEE_SUGGEST_W_EXPLICIT * c.explicit
            contribs.append(
                (
                    weighted,
                    ScoreContribution(
                        label=label,
                        points=round(c.explicit * 100, 1),
                        is_positive=True,
                        pillar="pertinence",
                    ),
                )
            )

        if c.measured > 0:
            weighted = ScoringWeights.TOURNEE_SUGGEST_W_MEASURED * c.measured
            contribs.append(
                (
                    weighted,
                    ScoreContribution(
                        label="Tu lis souvent ce genre de contenu",
                        points=round(c.measured * 100, 1),
                        is_positive=True,
                        pillar="pertinence",
                    ),
                )
            )

        if c.recent_count > 0:
            weighted = ScoringWeights.TOURNEE_SUGGEST_W_QUANTITY * c.quantity
            article_word = "article" if c.recent_count == 1 else "articles"
            contribs.append(
                (
                    weighted,
                    ScoreContribution(
                        label=f"{c.recent_count} {article_word} récents",
                        points=round(c.quantity * 100, 1),
                        is_positive=True,
                        pillar="fraicheur",
                    ),
                )
            )

        if c.quality > 0:
            weighted = ScoringWeights.TOURNEE_SUGGEST_W_QUALITY * c.quality
            contribs.append(
                (
                    weighted,
                    ScoreContribution(
                        label="Sources fiables",
                        points=round(c.quality * 100, 1),
                        is_positive=True,
                        pillar="qualite",
                    ),
                )
            )

        # Tri par contribution pondérée décroissante : le label dominant en tête.
        contribs.sort(key=lambda x: x[0], reverse=True)
        breakdown = [contrib for _, contrib in contribs]

        # Miroir du « Hasard pour diversifier » du digest (points=0, transparence).
        breakdown.append(
            ScoreContribution(
                label="Varié pour aujourd'hui",
                points=0,
                is_positive=True,
                pillar="diversite",
            )
        )

        c.breakdown = breakdown
        c.reason_label = breakdown[0].label


def _clamp01(value: float) -> float:
    if value < 0:
        return 0.0
    if value > 1:
        return 1.0
    return value


def _log_saturate(count: int, saturation: float) -> float:
    """Quantité log-saturée 0–1 : `log1p(count) / log1p(saturation)`, plafonné."""
    if count <= 0:
        return 0.0
    return _clamp01(math.log1p(count) / math.log1p(saturation))
