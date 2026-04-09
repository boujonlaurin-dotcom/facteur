"""Service de sélection de topics pour le Digest "Sujets du jour".

Epic 10 refonte : remplace la sélection d'articles individuels par une
sélection de N topics (N = weekly_goal, 3-7), chaque topic regroupant
1-3 articles de sources différentes.

Pipeline :
1. Clustering universel (ImportanceDetector.build_topic_clusters)
2. Scoring topic-level (source suivie, trending, une, thème, recency)
3. Sélection de N topics (multi-articles d'abord, singletons en fallback)
4. Sélection d'articles intra-topic (diversité sources, perspective)
5. Ranking final
"""

import datetime
from dataclasses import dataclass, field
from uuid import UUID

import structlog

from app.models.content import Content
from app.schemas.digest import DigestScoreBreakdown
from app.services.briefing.importance_detector import ImportanceDetector, TopicCluster
from app.services.digest_selector import DigestContext, GlobalTrendingContext
from app.services.ml.classification_service import SLUG_TO_LABEL
from app.services.perspective_service import PerspectiveService
from app.services.recommendation.filter_presets import is_cluster_serein_compatible
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import (
    PillarScoringEngine,
    ScoringContext,
)

logger = structlog.get_logger()


@dataclass
class ScoredArticle:
    """Un article scoré au sein d'un topic group."""

    content: Content
    score: float
    reason: str
    breakdown: list[DigestScoreBreakdown] = field(default_factory=list)
    is_followed_source: bool = False


@dataclass
class TopicGroup:
    """Un topic sélectionné pour le digest avec ses articles."""

    topic_id: str
    label: str  # Titre du meilleur article
    articles: list[ScoredArticle] = field(default_factory=list)
    topic_score: float = 0.0
    reason: str = ""
    is_trending: bool = False
    is_une: bool = False
    theme: str | None = None
    subjects: list[str] = field(default_factory=list)


class TopicSelector:
    """Sélecteur de topics pour le digest quotidien.

    Orchestre le clustering → scoring → sélection de N topics,
    chacun avec 1-3 articles de sources différentes.
    """

    def __init__(self):
        self.importance_detector = ImportanceDetector()
        self._perspective_service = PerspectiveService()
        self._pillar_engine = PillarScoringEngine()

    async def select_topics_for_user(
        self,
        candidates: list[Content],
        context: DigestContext,
        target_topics: int,
        trending_context: GlobalTrendingContext | None,
        mode: str = "pour_vous",
        sensitive_themes: list[str] | None = None,
    ) -> list[TopicGroup]:
        """Sélectionne N topics pour le digest d'un utilisateur.

        Args:
            candidates: Pool de candidats (depuis DigestSelector._get_candidates)
            context: Contexte utilisateur (intérêts, sources suivies, mutes, etc.)
            target_topics: Nombre de topics à sélectionner (= weekly_goal)
            trending_context: IDs trending/une pré-calculés (ou None)
            mode: Mode digest (pour_vous, serein, perspective, theme_focus)

        Returns:
            Liste de TopicGroup ordonnée par rang (1 à target_topics)
        """
        if not candidates:
            return []

        # 1. Clustering
        clusters = self.importance_detector.build_topic_clusters(
            candidates,
            similarity_threshold=ScoringWeights.TOPIC_CLUSTER_THRESHOLD,
        )

        if not clusters:
            return []

        # 2. Score chaque cluster
        scored_clusters = self._score_clusters(
            clusters=clusters,
            context=context,
            trending_context=trending_context,
            mode=mode,
            sensitive_themes=sensitive_themes,
        )

        # 3. Sélectionner N topics
        selected_clusters = self._select_n_topics(
            scored_clusters=scored_clusters,
            target_count=target_topics,
            trending_context=trending_context,
        )

        # 4. Sélectionner articles intra-topic + construire TopicGroup
        topic_groups = self._build_topic_groups(
            selected_clusters=selected_clusters,
            context=context,
            trending_context=trending_context,
            all_candidates=candidates,
            mode=mode,
        )

        # 5. Ranking final
        for _i, tg in enumerate(topic_groups, 1):
            tg.label = tg.articles[0].content.title if tg.articles else ""

        logger.info(
            "topic_selection_complete",
            user_id=str(context.user_id),
            target=target_topics,
            selected=len(topic_groups),
            mode=mode,
            multi_article_topics=sum(1 for tg in topic_groups if len(tg.articles) > 1),
            trending_topics=sum(1 for tg in topic_groups if tg.is_trending),
        )

        return topic_groups

    def _score_clusters(
        self,
        clusters: list[TopicCluster],
        context: DigestContext,
        trending_context: GlobalTrendingContext | None,
        mode: str,
        sensitive_themes: list[str] | None = None,
    ) -> list[tuple[TopicCluster, float, str]]:
        """Score chaque cluster au niveau topic.

        Returns:
            Liste de (cluster, score, reason) triée par score desc
        """
        scored: list[tuple[TopicCluster, float, str]] = []

        for cluster in clusters:
            # Mode serein : exclure les clusters anxiogènes
            if mode == "serein" and not is_cluster_serein_compatible(
                cluster, sensitive_themes=sensitive_themes
            ):
                continue

            score = 0.0
            reasons: list[str] = []

            # Bonus source suivie
            has_followed = any(
                c.source_id in context.followed_source_ids for c in cluster.contents
            )
            if has_followed:
                score += ScoringWeights.TOPIC_FOLLOWED_SOURCE_BONUS
                reasons.append("Sources suivies")

            # Bonus trending
            if trending_context and cluster.is_trending:
                # Verify at least one content is actually in the trending set
                has_trending = any(
                    c.id in trending_context.trending_content_ids
                    for c in cluster.contents
                )
                if has_trending:
                    score += ScoringWeights.TOPIC_TRENDING_BONUS
                    reasons.append("Sujet tendance")

            # Bonus Une
            has_une = False
            if trending_context:
                has_une = any(
                    c.id in trending_context.une_content_ids for c in cluster.contents
                )
                if has_une:
                    score += ScoringWeights.TOPIC_UNE_BONUS
                    reasons.append("À la une")

            # Bonus thème matche intérêts
            if cluster.theme and cluster.theme in context.user_interests:
                score += ScoringWeights.TOPIC_THEME_MATCH_BONUS
                reasons.append(f"Thème : {cluster.theme}")

            # Bonus topic match (ML topics ∩ user_subtopics at cluster level)
            if context.user_subtopics:
                best_topic_match: str | None = None
                for c in cluster.contents:
                    if c.topics:
                        for t in c.topics:
                            if t.lower() in context.user_subtopics:
                                best_topic_match = t.lower()
                                break
                    if best_topic_match:
                        break
                if best_topic_match:
                    topic_label = SLUG_TO_LABEL.get(
                        best_topic_match, best_topic_match.capitalize()
                    )
                    score += ScoringWeights.TOPIC_MATCH
                    reasons.append(f"Sujet : {topic_label}")

            # Bonus recency (meilleur article du cluster)
            best_recency = self._best_recency_bonus(cluster.contents)
            score += best_recency

            reason = reasons[0] if reasons else "Sélectionné pour vous"

            scored.append((cluster, score, reason))

        scored.sort(key=lambda x: x[1], reverse=True)
        return scored

    def _best_recency_bonus(self, contents: list[Content]) -> float:
        """Retourne le meilleur bonus recency parmi les articles."""
        now = datetime.datetime.now(datetime.UTC)
        best = 0.0

        for content in contents:
            published = content.published_at
            if published and published.tzinfo is None:
                published = published.replace(tzinfo=datetime.UTC)
            if not published:
                continue

            hours_old = (now - published).total_seconds() / 3600

            if hours_old < 6:
                bonus = ScoringWeights.RECENT_VERY_BONUS
            elif hours_old < 24:
                bonus = ScoringWeights.RECENT_BONUS
            elif hours_old < 48:
                bonus = ScoringWeights.RECENT_DAY_BONUS
            elif hours_old < 72:
                bonus = ScoringWeights.RECENT_YESTERDAY_BONUS
            elif hours_old < 120:
                bonus = ScoringWeights.RECENT_WEEK_BONUS
            elif hours_old < 168:
                bonus = ScoringWeights.RECENT_OLD_BONUS
            else:
                bonus = 0.0

            if bonus > best:
                best = bonus

        return best

    def _select_n_topics(
        self,
        scored_clusters: list[tuple[TopicCluster, float, str]],
        target_count: int,
        trending_context: GlobalTrendingContext | None,
    ) -> list[tuple[TopicCluster, float, str]]:
        """Sélectionne N topics avec contraintes de diversité.

        Priorité : multi-articles d'abord, singletons en complément.
        Contrainte : max 2 topics du même thème.
        Garde-fou : min 1 topic trending si disponible.
        """
        MAX_PER_THEME = 2

        # Séparer multi-articles et singletons
        multi = [(c, s, r) for c, s, r in scored_clusters if len(c.contents) >= 2]
        single = [(c, s, r) for c, s, r in scored_clusters if len(c.contents) == 1]

        selected: list[tuple[TopicCluster, float, str]] = []
        theme_counts: dict[str, int] = {}
        has_trending = False

        def try_add(item: tuple[TopicCluster, float, str]) -> bool:
            nonlocal has_trending
            cluster, score, reason = item
            theme = cluster.theme or "__none__"

            if theme_counts.get(theme, 0) >= MAX_PER_THEME:
                return False

            selected.append(item)
            theme_counts[theme] = theme_counts.get(theme, 0) + 1

            if cluster.is_trending:
                has_trending = True

            return True

        # Pass 1: multi-articles
        for item in multi:
            if len(selected) >= target_count:
                break
            try_add(item)

        # Pass 2: singletons si N pas atteint
        for item in single:
            if len(selected) >= target_count:
                break
            try_add(item)

        # Garde-fou : forcer 1 topic trending si on en a 0
        if not has_trending and trending_context and len(selected) > 0:
            best_trending = None
            for cluster, score, reason in scored_clusters:
                if cluster.is_trending:
                    best_trending = (cluster, score, reason)
                    break

            if best_trending and best_trending not in selected:
                # Remplacer le dernier topic non-trending
                selected[-1] = best_trending

        return selected

    def _build_topic_groups(
        self,
        selected_clusters: list[tuple[TopicCluster, float, str]],
        context: DigestContext,
        trending_context: GlobalTrendingContext | None,
        all_candidates: list[Content],
        mode: str,
    ) -> list[TopicGroup]:
        """Construit les TopicGroup avec sélection d'articles intra-topic."""
        topic_groups: list[TopicGroup] = []

        for cluster, topic_score, reason in selected_clusters:
            # Score articles intra-topic
            scored_articles = self._score_and_select_articles(
                cluster=cluster,
                context=context,
                trending_context=trending_context,
            )

            # Determine is_une
            is_une = False
            if trending_context:
                is_une = any(
                    a.content.id in trending_context.une_content_ids
                    for a in scored_articles
                )

            # Extract display subjects from article titles
            seen_kw: set[str] = set()
            subjects: list[str] = []
            for article in scored_articles:
                for kw in self._perspective_service.extract_keywords(
                    article.content.title, max_keywords=4
                ):
                    if kw.lower() not in seen_kw:
                        seen_kw.add(kw.lower())
                        subjects.append(kw)
            subjects = subjects[:5]

            topic_groups.append(
                TopicGroup(
                    topic_id=cluster.cluster_id,
                    label="",  # Set after this loop
                    articles=scored_articles,
                    topic_score=topic_score,
                    reason=reason,
                    is_trending=cluster.is_trending,
                    is_une=is_une,
                    theme=cluster.theme,
                    subjects=subjects,
                )
            )

        return topic_groups

    def _build_scoring_context(self, context: DigestContext) -> ScoringContext:
        """Convert DigestContext to ScoringContext for pillar engine."""
        return ScoringContext(
            user_profile=context.user_profile,
            user_interests=context.user_interests,
            user_interest_weights=context.user_interest_weights,
            followed_source_ids=context.followed_source_ids,
            user_prefs=context.user_prefs,
            now=datetime.datetime.now(datetime.UTC),
            user_subtopics=context.user_subtopics,
            user_subtopic_weights=context.user_subtopic_weights,
            muted_sources=context.muted_sources,
            muted_themes=context.muted_themes,
            muted_topics=context.muted_topics,
            muted_content_types=context.muted_content_types,
            custom_source_ids=context.custom_source_ids,
            source_affinity_scores=context.source_affinity_scores,
            source_priority_multipliers=context.source_priority_multipliers,
        )

    def _score_and_select_articles(
        self,
        cluster: TopicCluster,
        context: DigestContext,
        trending_context: GlobalTrendingContext | None,
    ) -> list[ScoredArticle]:
        """Score et sélectionne 1-3 articles d'un cluster avec diversité de sources.

        Utilise PillarScoringEngine (v2) pour le scoring de base,
        puis applique les bonus digest-spécifiques (trending/une) en post-pilier.
        """
        max_articles = ScoringWeights.TOPIC_MAX_ARTICLES
        scoring_context = self._build_scoring_context(context)

        # Post-pillar digest bonuses (normalized to 0-100 scale)
        TRENDING_BONUS = 15.0  # ~45/300 from old scale
        UNE_BONUS = 12.0  # ~35/300 from old scale

        article_scores: list[
            tuple[Content, float, str, list[DigestScoreBreakdown]]
        ] = []

        for content in cluster.contents:
            # 1. Pillar scoring (0-100 base + penalties)
            pillar_result = self._pillar_engine.compute_score(content, scoring_context)
            score = pillar_result.final_score

            # Convert pillar contributions to DigestScoreBreakdown
            breakdown: list[DigestScoreBreakdown] = []
            for contrib in pillar_result.contributions:
                breakdown.append(
                    DigestScoreBreakdown(
                        label=contrib["label"],
                        points=contrib["points"],
                        is_positive=contrib["is_positive"],
                        pillar=contrib["pillar"],
                    )
                )

            # 2. Digest-specific post-pillar bonuses
            if trending_context:
                if content.id in trending_context.trending_content_ids:
                    score += TRENDING_BONUS
                    breakdown.append(
                        DigestScoreBreakdown(
                            label="Sujet du jour",
                            points=TRENDING_BONUS,
                            is_positive=True,
                            pillar="pertinence",
                        )
                    )
                if content.id in trending_context.une_content_ids:
                    score += UNE_BONUS
                    breakdown.append(
                        DigestScoreBreakdown(
                            label="À la une",
                            points=UNE_BONUS,
                            is_positive=True,
                            pillar="pertinence",
                        )
                    )

            # Build reason
            reason = self._article_reason(content, context, breakdown)
            article_scores.append((content, score, reason, breakdown))

        # Sort by score desc
        article_scores.sort(key=lambda x: x[1], reverse=True)

        # 3. Randomization (Gumbel with daily seed — stable within the day)
        if ScoringWeights.DIGEST_RANDOMIZATION_TEMPERATURE > 0:
            from app.services.recommendation.randomization import (
                compute_seed,
                randomized_sort,
            )

            seed = compute_seed(str(context.user_id), granularity="daily")
            # Wrap full tuples for randomized_sort: T = (content, reason, breakdown)
            wrapped = [
                ((content, reason, breakdown), score)
                for content, score, reason, breakdown in article_scores
            ]
            randomized = randomized_sort(
                wrapped,
                temperature=ScoringWeights.DIGEST_RANDOMIZATION_TEMPERATURE,
                seed=seed,
            )
            article_scores = [(t[0], s, t[1], t[2]) for t, s in randomized]

            # Add randomization transparency
            for _content, _score, _reason, bd in article_scores:
                bd.append(
                    DigestScoreBreakdown(
                        label="Hasard pour diversifier",
                        points=0,
                        is_positive=True,
                        pillar="diversite",
                    )
                )

        # 4. Source diversity filter (max 1 article per source intra-topic)
        selected: list[ScoredArticle] = []
        used_sources: set[UUID] = set()

        for content, score, reason, breakdown in article_scores:
            if len(selected) >= max_articles:
                break
            if content.source_id in used_sources:
                continue

            selected.append(
                ScoredArticle(
                    content=content,
                    score=score,
                    reason=reason,
                    breakdown=breakdown,
                    is_followed_source=content.source_id in context.followed_source_ids,
                )
            )
            used_sources.add(content.source_id)

        return selected

    @staticmethod
    def _recency_bonus(hours_old: float) -> float:
        if hours_old < 6:
            return ScoringWeights.RECENT_VERY_BONUS
        elif hours_old < 24:
            return ScoringWeights.RECENT_BONUS
        elif hours_old < 48:
            return ScoringWeights.RECENT_DAY_BONUS
        elif hours_old < 72:
            return ScoringWeights.RECENT_YESTERDAY_BONUS
        elif hours_old < 120:
            return ScoringWeights.RECENT_WEEK_BONUS
        elif hours_old < 168:
            return ScoringWeights.RECENT_OLD_BONUS
        return 0.0

    @staticmethod
    def _recency_label(hours_old: float) -> str:
        if hours_old < 6:
            return "Article très récent (< 6h)"
        elif hours_old < 24:
            return "Article récent (< 24h)"
        elif hours_old < 48:
            return "Publié aujourd'hui"
        elif hours_old < 72:
            return "Publié hier"
        elif hours_old < 120:
            return "Article de la semaine"
        return "Article ancien"

    @staticmethod
    def _article_reason(
        content: Content,
        context: DigestContext,
        breakdown: list[DigestScoreBreakdown],
    ) -> str:
        """Génère la raison de sélection pour un article dans un topic."""
        # Trending/Une first
        for b in breakdown:
            if b.label == "Sujet du jour":
                return "Sujet du jour"
            if b.label == "À la une":
                return "À la une"

        # Source suivie
        if content.source_id in context.followed_source_ids:
            return "Source suivie"

        # Thème
        theme = getattr(content, "theme", None)
        if not theme and content.source:
            theme = getattr(content.source, "theme", None)
        if theme:
            _LABELS = {
                "tech": "Tech & Innovation",
                "society": "Société",
                "environment": "Environnement",
                "economy": "Économie",
                "politics": "Politique",
                "culture": "Culture & Idées",
                "science": "Sciences",
                "international": "Géopolitique",
                "sport": "Sport",
            }
            return f"Thème : {_LABELS.get(theme.lower(), theme.capitalize())}"

        return "Sélectionné pour vous"
