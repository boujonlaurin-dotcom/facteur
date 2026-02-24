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
from app.models.enums import DigestMode
from app.schemas.digest import DigestScoreBreakdown
from app.services.briefing.importance_detector import ImportanceDetector, TopicCluster
from app.services.digest_selector import DigestContext, GlobalTrendingContext
from app.services.recommendation.filter_presets import (
    find_perspective_article,
    get_opposing_biases,
    is_cluster_serein_compatible,
)
from app.services.perspective_service import PerspectiveService
from app.services.ml.classification_service import SLUG_TO_LABEL
from app.services.recommendation.scoring_config import ScoringWeights

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

    async def select_topics_for_user(
        self,
        candidates: list[Content],
        context: DigestContext,
        target_topics: int,
        trending_context: GlobalTrendingContext | None,
        mode: str = "pour_vous",
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
        for i, tg in enumerate(topic_groups, 1):
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
    ) -> list[tuple[TopicCluster, float, str]]:
        """Score chaque cluster au niveau topic.

        Returns:
            Liste de (cluster, score, reason) triée par score desc
        """
        scored: list[tuple[TopicCluster, float, str]] = []

        for cluster in clusters:
            # Mode serein : exclure les clusters anxiogènes
            if mode == DigestMode.SEREIN and not is_cluster_serein_compatible(cluster):
                continue

            score = 0.0
            reasons: list[str] = []

            # Bonus source suivie
            has_followed = any(
                c.source_id in context.followed_source_ids
                for c in cluster.contents
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
                    c.id in trending_context.une_content_ids
                    for c in cluster.contents
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
                    topic_label = SLUG_TO_LABEL.get(best_topic_match, best_topic_match.capitalize())
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
        now = datetime.datetime.now(datetime.timezone.utc)
        best = 0.0

        for content in contents:
            published = content.published_at
            if published and published.tzinfo is None:
                published = published.replace(tzinfo=datetime.timezone.utc)
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

            # Mode perspective : enrichir avec article de biais opposé
            if mode == DigestMode.PERSPECTIVE and context.user_bias_stance:
                if len(scored_articles) < ScoringWeights.TOPIC_MAX_ARTICLES:
                    topic_source_ids = set(a.content.source_id for a in scored_articles)
                    perspective_content = find_perspective_article(
                        candidates=all_candidates,
                        topic_source_ids=topic_source_ids,
                        user_bias=context.user_bias_stance,
                    )
                    if perspective_content:
                        scored_articles.append(ScoredArticle(
                            content=perspective_content,
                            score=0.0,
                            reason="Perspective opposée",
                            breakdown=[DigestScoreBreakdown(
                                label="Perspective opposée",
                                points=80.0,
                                is_positive=True,
                            )],
                            is_followed_source=perspective_content.source_id in context.followed_source_ids,
                        ))

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
                for kw in self._perspective_service.extract_keywords(article.content.title, max_keywords=4):
                    if kw.lower() not in seen_kw:
                        seen_kw.add(kw.lower())
                        subjects.append(kw)
            subjects = subjects[:5]

            topic_groups.append(TopicGroup(
                topic_id=cluster.cluster_id,
                label="",  # Set after this loop
                articles=scored_articles,
                topic_score=topic_score,
                reason=reason,
                is_trending=cluster.is_trending,
                is_une=is_une,
                theme=cluster.theme,
                subjects=subjects,
            ))

        return topic_groups

    def _score_and_select_articles(
        self,
        cluster: TopicCluster,
        context: DigestContext,
        trending_context: GlobalTrendingContext | None,
    ) -> list[ScoredArticle]:
        """Score et sélectionne 1-3 articles d'un cluster avec diversité de sources.

        Scoring simplifié (pas de DB) : recency + source suivie + trending/une.
        Contrainte : sources différentes entre les articles sélectionnés.
        """
        max_articles = ScoringWeights.TOPIC_MAX_ARTICLES
        now = datetime.datetime.now(datetime.timezone.utc)

        article_scores: list[tuple[Content, float, str, list[DigestScoreBreakdown]]] = []

        for content in cluster.contents:
            breakdown: list[DigestScoreBreakdown] = []
            score = 0.0

            # Recency
            published = content.published_at
            if published and published.tzinfo is None:
                published = published.replace(tzinfo=datetime.timezone.utc)
            if published:
                hours_old = (now - published).total_seconds() / 3600
                recency_bonus = self._recency_bonus(hours_old)
                if recency_bonus > 0:
                    score += recency_bonus
                    breakdown.append(DigestScoreBreakdown(
                        label=self._recency_label(hours_old),
                        points=recency_bonus,
                        is_positive=True,
                    ))

            # Source suivie
            is_followed = content.source_id in context.followed_source_ids
            if is_followed:
                score += ScoringWeights.TRUSTED_SOURCE
                breakdown.append(DigestScoreBreakdown(
                    label="Source de confiance",
                    points=ScoringWeights.TRUSTED_SOURCE,
                    is_positive=True,
                ))

            # Source affinity bonus (learned from interactions)
            affinity = context.source_affinity_scores.get(content.source_id, 0.0)
            if affinity > 0:
                affinity_bonus = affinity * ScoringWeights.SOURCE_AFFINITY_MAX_BONUS
                score += affinity_bonus
                breakdown.append(DigestScoreBreakdown(
                    label=f"Source appréciée ({affinity:.0%})",
                    points=affinity_bonus,
                    is_positive=True,
                ))

            # Thème matche
            content_theme = getattr(content, "theme", None)
            source_theme = content.source.theme if content.source else None
            theme = content_theme or source_theme
            if theme and theme in context.user_interests:
                score += ScoringWeights.THEME_MATCH
                breakdown.append(DigestScoreBreakdown(
                    label=f"Thème matché : {theme}",
                    points=ScoringWeights.THEME_MATCH,
                    is_positive=True,
                ))

            # Topic match (ML topics ∩ user_subtopics)
            if content.topics and context.user_subtopics:
                matched_topics = 0
                for topic in content.topics:
                    topic_lower = topic.lower()
                    if topic_lower in context.user_subtopics and matched_topics < ScoringWeights.TOPIC_MAX_MATCHES:
                        w = context.user_subtopic_weights.get(topic_lower, 1.0)
                        points = ScoringWeights.TOPIC_MATCH * w
                        topic_label = SLUG_TO_LABEL.get(topic_lower, topic.capitalize())
                        if w > 1.0:
                            label = f"Renforcé par vos j'aime : {topic_label}"
                        else:
                            label = f"Sujet : {topic_label}"
                        score += points
                        breakdown.append(DigestScoreBreakdown(
                            label=label,
                            points=points,
                            is_positive=True,
                        ))
                        matched_topics += 1

                # Precision bonus if topic + theme both match
                if matched_topics > 0 and theme and theme in context.user_interests:
                    score += ScoringWeights.SUBTOPIC_PRECISION_BONUS
                    breakdown.append(DigestScoreBreakdown(
                        label="Précision thématique",
                        points=ScoringWeights.SUBTOPIC_PRECISION_BONUS,
                        is_positive=True,
                    ))

            # Trending/Une bonus
            if trending_context:
                if content.id in trending_context.trending_content_ids:
                    score += ScoringWeights.DIGEST_TRENDING_BONUS
                    breakdown.append(DigestScoreBreakdown(
                        label="Sujet du jour",
                        points=ScoringWeights.DIGEST_TRENDING_BONUS,
                        is_positive=True,
                    ))
                if content.id in trending_context.une_content_ids:
                    score += ScoringWeights.DIGEST_UNE_BONUS
                    breakdown.append(DigestScoreBreakdown(
                        label="À la une",
                        points=ScoringWeights.DIGEST_UNE_BONUS,
                        is_positive=True,
                    ))

            # Source curated
            if content.source and content.source.is_curated:
                score += ScoringWeights.CURATED_SOURCE
                breakdown.append(DigestScoreBreakdown(
                    label="Source qualitative",
                    points=ScoringWeights.CURATED_SOURCE,
                    is_positive=True,
                ))

            # Build reason
            reason = self._article_reason(content, context, breakdown)

            article_scores.append((content, score, reason, breakdown))

        # Trier par score desc
        article_scores.sort(key=lambda x: x[1], reverse=True)

        # Sélectionner avec diversité de sources
        selected: list[ScoredArticle] = []
        used_sources: set[UUID] = set()

        for content, score, reason, breakdown in article_scores:
            if len(selected) >= max_articles:
                break
            if content.source_id in used_sources:
                continue

            selected.append(ScoredArticle(
                content=content,
                score=score,
                reason=reason,
                breakdown=breakdown,
                is_followed_source=content.source_id in context.followed_source_ids,
            ))
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
