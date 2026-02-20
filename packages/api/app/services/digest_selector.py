from __future__ import annotations
"""Service de sélection d'articles pour le Digest quotidien (7 articles).

Ce service implémente l'algorithme de sélection intelligent pour Epic 10,
avec contraintes de diversité et mécanisme de fallback.

Contraintes de diversité:
- Maximum 1 article par source (fallback à 2 si < 7 sources distinctes)
- Maximum 2 articles par thème
- Minimum 4 sources différentes

Completion:
- Seuil de completion à 5/7 interactions (configurable via COMPLETION_THRESHOLD)

Fallback:
- Si le pool utilisateur < 7 articles, complète avec les sources curatées

Réutilise l'infrastructure de scoring existante sans modification.
"""

import asyncio
import datetime
import time
from dataclasses import dataclass
from math import ceil
from typing import Any, List, Set, Tuple, Optional, Dict
from uuid import UUID
from collections import defaultdict

import structlog
from sqlalchemy import select, and_, or_, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.source import Source, UserSource
from app.models.user import UserProfile, UserInterest, UserSubtopic
from app.models.enums import ContentStatus, DigestMode, BiasStance
from app.services.briefing.importance_detector import ImportanceDetector
from app.services.recommendation_service import RecommendationService
from app.services.recommendation.scoring_engine import ScoringContext
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.filter_presets import (
    apply_serein_filter,
    apply_theme_focus_filter,
    get_opposing_biases,
    calculate_user_bias,
)
from app.schemas.digest import DigestScoreBreakdown

logger = structlog.get_logger()


@dataclass
class DigestItem:
    """Représente un article sélectionné pour le digest.
    
    Attributes:
        content: L'article Content sélectionné
        score: Le score calculé par le ScoringEngine
        rank: La position dans le digest (1-5)
        reason: La raison de sélection (pour affichage utilisateur)
        breakdown: Les contributions détaillées au score (pour transparence)
    """
    content: Content
    score: float
    rank: int
    reason: str
    breakdown: Optional[List[DigestScoreBreakdown]] = None


@dataclass
class DigestContext:
    """Contexte pour la sélection du digest.
    
    Contient les données utilisateur nécessaires pour la sélection.
    """
    user_id: UUID
    user_profile: Optional[UserProfile]
    user_interests: Set[str]
    user_interest_weights: Dict[str, float]
    followed_source_ids: Set[UUID]
    custom_source_ids: Set[UUID]
    user_prefs: Dict[str, Any]
    user_subtopics: Set[str]
    user_subtopic_weights: Dict[str, float]
    muted_sources: Set[UUID]
    muted_themes: Set[str]
    muted_topics: Set[str]
    muted_content_types: Set[str]
    hide_paid_content: bool = True
    user_bias_stance: Optional[BiasStance] = None


@dataclass
class GlobalTrendingContext:
    """Contexte global trending, calculé 1x par batch.

    Contient les IDs des contenus objectivement importants
    (trending cross-source et "À la une" éditorial).
    """
    trending_content_ids: Set[UUID]
    une_content_ids: Set[UUID]
    computed_at: datetime.datetime


class DiversityConstraints:
    """Configuration des contraintes de diversité."""
    MAX_PER_SOURCE = 1
    MAX_PER_THEME = 2
    TARGET_DIGEST_SIZE = 7
    COMPLETION_THRESHOLD = 5
    MIN_SOURCES = 4


class DigestSelector:
    """Sélecteur intelligent d'articles pour le digest quotidien.

    Cette classe implémente la logique de sélection des 7 articles
    du digest avec garanties de diversité et mécanisme de fallback.
    
    Usage:
        selector = DigestSelector(session)
        digest_items = await selector.select_for_user(user_id)
    """
    
    def __init__(self, session: AsyncSession):
        self.session = session
        self.rec_service = RecommendationService(session)
        self.constraints = DiversityConstraints()
        self.importance_detector = ImportanceDetector()
        
    async def select_for_user(
        self,
        user_id: UUID,
        limit: int = 7,
        hours_lookback: int = 168,
        mode: str = "pour_vous",
        focus_theme: Optional[str] = None,
        global_trending_context: Optional[GlobalTrendingContext] = None,
        output_format: str = "topics",
    ) -> list:
        """Sélectionne les articles pour le digest d'un utilisateur.

        Args:
            user_id: ID de l'utilisateur
            limit: Nombre d'articles à sélectionner (défaut: 7)
            hours_lookback: Fenêtre temporelle pour les candidats (défaut: 168h/7j)
            mode: Mode de digest (pour_vous, serein, perspective, theme_focus)
            focus_theme: Slug du thème pour le mode theme_focus
            global_trending_context: Contexte trending pré-calculé (batch) ou None (on-demand)

        Returns:
            Liste de DigestItem ordonnée par rank (1 à limit)

        Raises:
            Aucune exception - retourne une liste vide en cas d'erreur
        """
        start_time = time.time()

        try:
            logger.info("digest_selection_started", user_id=str(user_id), limit=limit, mode=mode, focus_theme=focus_theme)

            # 1. Construire le contexte utilisateur
            step_start = time.time()
            context = await self._build_digest_context(user_id, mode=mode)
            context_time = time.time() - step_start
            
            if not context.user_profile:
                logger.warning("digest_selection_no_profile", user_id=str(user_id))
                return []
            
            logger.info("digest_selector_context_built", user_id=str(user_id), duration_ms=round(context_time * 1000, 2))

            # 1.5 Build or use global trending context (pour_vous only)
            trending_context = None
            if mode == "pour_vous" or mode == DigestMode.POUR_VOUS:
                if global_trending_context is not None:
                    trending_context = global_trending_context
                    logger.info(
                        "digest_using_precomputed_trending_context",
                        user_id=str(user_id),
                        trending_count=len(global_trending_context.trending_content_ids),
                        une_count=len(global_trending_context.une_content_ids),
                    )
                else:
                    step_start = time.time()
                    trending_context = await self._build_global_trending_context()
                    trending_time = time.time() - step_start
                    logger.info(
                        "digest_trending_context_computed_ondemand",
                        user_id=str(user_id),
                        trending_count=len(trending_context.trending_content_ids),
                        une_count=len(trending_context.une_content_ids),
                        duration_ms=round(trending_time * 1000, 2),
                    )

            # 2. Récupérer les candidats
            step_start = time.time()
            candidates = await self._get_candidates(
                user_id=user_id,
                context=context,
                hours_lookback=hours_lookback,
                min_pool_size=limit,
                mode=mode,
                focus_theme=focus_theme,
            )
            candidates_time = time.time() - step_start

            if not candidates:
                logger.warning("digest_selection_no_candidates", user_id=str(user_id), duration_ms=round(candidates_time * 1000, 2))
                return []

            logger.info("digest_selector_candidates_fetched", user_id=str(user_id), count=len(candidates), duration_ms=round(candidates_time * 1000, 2))

            # === TOPIC FORMAT: delegate to TopicSelector ===
            if output_format == "topics":
                from app.services.topic_selector import TopicSelector
                step_start = time.time()
                topic_selector = TopicSelector()
                topic_groups = await topic_selector.select_topics_for_user(
                    candidates=candidates,
                    context=context,
                    target_topics=limit,
                    trending_context=trending_context,
                    mode=mode,
                )
                topic_time = time.time() - step_start
                total_time = time.time() - start_time
                logger.info(
                    "digest_topic_selection_completed",
                    user_id=str(user_id),
                    topic_count=len(topic_groups),
                    total_articles=sum(len(tg.articles) for tg in topic_groups),
                    topic_selection_ms=round(topic_time * 1000, 2),
                    total_ms=round(total_time * 1000, 2),
                )
                return topic_groups

            # === FLAT FORMAT (legacy): original scoring + selection ===

            # 3-4. Scoring + sélection (deux passes pour pour_vous, single-pass pour les autres)
            scoring_time, diversity_time = 0.0, 0.0
            if trending_context and (mode == "pour_vous" or mode == DigestMode.POUR_VOUS):
                step_start = time.time()
                selected = await self._two_pass_selection(
                    candidates=candidates,
                    context=context,
                    trending_context=trending_context,
                    target_count=limit,
                )
                twopass_time = time.time() - step_start
                scoring_time = twopass_time  # Use twopass_time for final logging
                logger.info(
                    "digest_two_pass_selection_done",
                    user_id=str(user_id),
                    selected_count=len(selected),
                    target_count=limit,
                    duration_ms=round(twopass_time * 1000, 2),
                )
            else:
                # Single-pass pour serein, perspective, theme_focus (inchangé)
                step_start = time.time()
                scored_candidates_with_breakdown = await self._score_candidates(candidates, context, mode=mode)
                scoring_time = time.time() - step_start

                non_zero_scores = [s for _, s, _ in scored_candidates_with_breakdown if s > 0]
                zero_scores = [s for _, s, _ in scored_candidates_with_breakdown if s == 0]

                logger.info(
                    "digest_selector_scoring_done",
                    user_id=str(user_id),
                    count=len(scored_candidates_with_breakdown),
                    non_zero_count=len(non_zero_scores),
                    zero_count=len(zero_scores),
                    max_score=round(max((s for _, s, _ in scored_candidates_with_breakdown), default=0), 2),
                    duration_ms=round(scoring_time * 1000, 2),
                )

                step_start = time.time()
                selected = self._select_with_diversity(
                    scored_candidates=scored_candidates_with_breakdown,
                    target_count=limit,
                    mode=mode,
                )
                diversity_time = time.time() - step_start

                logger.info(
                    "digest_diversity_selection_result",
                    user_id=str(user_id),
                    selected_count=len(selected),
                    target_count=limit,
                    had_candidates=len(scored_candidates_with_breakdown) > 0,
                )
            
            # 5. Construire les résultats
            digest_items = []
            user_source_items = []
            curated_items = []
            
            for i, (content, score, reason, breakdown) in enumerate(selected, 1):
                digest_items.append(DigestItem(
                    content=content,
                    score=score,
                    rank=i,
                    reason=reason,
                    breakdown=breakdown
                ))
                # Track source type
                if content.source_id in context.followed_source_ids:
                    user_source_items.append(content.id)
                else:
                    curated_items.append(content.id)
            
            total_time = time.time() - start_time
            
            # Calculate ratio of user sources vs curated in final selection
            total_items = len(digest_items)
            user_items_count = len(user_source_items)
            curated_items_count = len(curated_items)
            
            logger.info(
                "digest_selection_completed", 
                user_id=str(user_id), 
                count=len(digest_items),
                sources=[str(s) for s in set(item.content.source_id for item in digest_items)],
                themes=list(set(item.content.source.theme for item in digest_items if item.content.source)),
                context_ms=round(context_time * 1000, 2),
                candidates_ms=round(candidates_time * 1000, 2),
                scoring_ms=round(scoring_time * 1000, 2),
                diversity_ms=round(diversity_time * 1000, 2),
                total_ms=round(total_time * 1000, 2),
                # Source tracking for curation verification
                final_user_source_count=user_items_count,
                final_curated_count=curated_items_count,
                user_to_curated_ratio=f"{user_items_count}:{curated_items_count}",
                percent_user_sources=round(user_items_count / total_items * 100, 1) if total_items > 0 else 0
            )
            
            return digest_items
            
        except Exception as e:
            total_time = time.time() - start_time
            logger.error("digest_selection_error", user_id=str(user_id), error=str(e), total_ms=round(total_time * 1000, 2), exc_info=True)
            return []
    
    async def _build_digest_context(self, user_id: UUID, mode: str = "pour_vous") -> DigestContext:
        """Construit le contexte utilisateur pour la sélection.

        Récupère les données utilisateur nécessaires depuis la base de données.
        Si mode=perspective, calcule le biais utilisateur pour le scoring.
        """
        # Récupérer le profil avec intérêts et préférences
        profile_stmt = (
            select(UserProfile)
            .options(
                selectinload(UserProfile.interests),
                selectinload(UserProfile.preferences)
            )
            .where(UserProfile.user_id == user_id)
        )
        profile_result = await self.session.execute(profile_stmt)
        user_profile = profile_result.scalar_one_or_none()
        
        # Récupérer les sources suivies
        sources_stmt = select(UserSource).where(UserSource.user_id == user_id)
        sources_result = await self.session.execute(sources_stmt)
        user_sources = sources_result.scalars().all()
        
        followed_source_ids = set()
        custom_source_ids = set()
        for us in user_sources:
            followed_source_ids.add(us.source_id)
            if us.is_custom:
                custom_source_ids.add(us.source_id)
        
        # Récupérer les sous-thèmes et poids
        subtopics_stmt = select(UserSubtopic).where(UserSubtopic.user_id == user_id)
        subtopics_result = await self.session.execute(subtopics_stmt)
        subtopic_rows = subtopics_result.scalars().all()
        user_subtopics = {row.topic_slug for row in subtopic_rows}
        user_subtopic_weights = {row.topic_slug: row.weight for row in subtopic_rows}
        
        # Construire les sets d'intérêts et poids
        user_interests = set()
        user_interest_weights = {}
        user_prefs = {}
        
        if user_profile:
            for interest in user_profile.interests:
                user_interests.add(interest.interest_slug)
                user_interest_weights[interest.interest_slug] = interest.weight
            
            for pref in user_profile.preferences:
                user_prefs[pref.preference_key] = pref.preference_value
        
        # Récupérer la personnalisation (mutes)
        from app.models.user_personalization import UserPersonalization
        personalization = await self.session.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_id)
        )
        
        muted_sources = set()
        muted_themes = set()
        muted_topics = set()
        muted_content_types = set()

        if personalization:
            if personalization.muted_sources:
                muted_sources = set(s for s in personalization.muted_sources if s is not None)
            if personalization.muted_themes:
                muted_themes = set(t.lower() for t in personalization.muted_themes if t)
            if personalization.muted_topics:
                muted_topics = set(t.lower() for t in personalization.muted_topics if t)
            if personalization.muted_content_types:
                muted_content_types = set(t.lower() for t in personalization.muted_content_types if t)

        # Paywall filter preference
        hide_paid_content = True  # Default: hide paid articles
        if personalization and personalization.hide_paid_content is not None:
            hide_paid_content = personalization.hide_paid_content

        # Calculer le biais utilisateur si mode perspective
        user_bias_stance = None
        if mode == DigestMode.PERSPECTIVE:
            user_bias_stance = await calculate_user_bias(self.session, user_id)

        return DigestContext(
            user_id=user_id,
            user_profile=user_profile,
            user_interests=user_interests,
            user_interest_weights=user_interest_weights,
            followed_source_ids=followed_source_ids,
            custom_source_ids=custom_source_ids,
            user_prefs=user_prefs,
            user_subtopics=user_subtopics,
            user_subtopic_weights=user_subtopic_weights,
            muted_sources=muted_sources,
            muted_themes=muted_themes,
            muted_topics=muted_topics,
            muted_content_types=muted_content_types,
            hide_paid_content=hide_paid_content,
            user_bias_stance=user_bias_stance,
        )
    
    async def _get_candidates(
        self,
        user_id: UUID,
        context: DigestContext,
        hours_lookback: int,
        min_pool_size: int,
        mode: str = "pour_vous",
        focus_theme: Optional[str] = None,
    ) -> List[Content]:
        """Récupère les candidats pour le digest.

        Strategy:
        1. D'abord, récupérer les articles des sources suivies par l'utilisateur
        2. Si pool insuffisant (< min_pool_size), compléter avec sources curatées
        3. Exclure les articles déjà vus, sauvegardés, ou masqués
        4. Appliquer les filtres de mode (serein, theme_focus)
        """
        since = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours_lookback)
        
        # Construire la requête de base avec exclusions
        from sqlalchemy import exists
        
        # Sous-requête pour exclure les articles déjà traités
        excluded_stmt = exists().where(
            UserContentStatus.content_id == Content.id,
            UserContentStatus.user_id == user_id,
            or_(
                UserContentStatus.is_hidden == True,
                UserContentStatus.is_saved == True,
                UserContentStatus.status.in_([ContentStatus.SEEN, ContentStatus.CONSUMED])
            )
        )
        
        candidates = []
        
        # Étape 1: Articles des sources suivies (PRIORITY)
        if context.followed_source_ids:
            user_sources_query = (
                select(Content)
                .join(Content.source)
                .options(selectinload(Content.source))
                .where(
                    ~excluded_stmt,
                    Content.published_at >= since,
                    Source.id.in_(list(context.followed_source_ids)),
                    # Respecter les mutes
                    Source.id.notin_(list(context.muted_sources)) if context.muted_sources else True,
                    ~Source.theme.in_(list(context.muted_themes)) if context.muted_themes else True
                )
                .order_by(Content.published_at.desc())
                .limit(200)
            )
            
            # Filtrage des topics muets
            if context.muted_topics:
                user_sources_query = user_sources_query.where(
                    or_(
                        Content.topics.is_(None),
                        ~Content.topics.overlap(list(context.muted_topics))
                    )
                )

            # Filtrage des types de contenu mutés
            if context.muted_content_types:
                user_sources_query = user_sources_query.where(
                    Content.content_type.notin_(list(context.muted_content_types))
                )

            # Filtrage des articles payants (is_not(True) handles NULL rows)
            if context.hide_paid_content:
                user_sources_query = user_sources_query.where(
                    Content.is_paid.is_not(True)
                )

            # Appliquer les filtres de mode sur les sources utilisateur
            if mode == DigestMode.SEREIN:
                user_sources_query = apply_serein_filter(user_sources_query)
            elif mode == DigestMode.THEME_FOCUS and focus_theme:
                user_sources_query = apply_theme_focus_filter(user_sources_query, focus_theme)

            result = await self.session.execute(user_sources_query)
            user_candidates = list(result.scalars().all())
            candidates.extend(user_candidates)
            
            logger.info(
                "digest_candidates_user_sources",
                user_id=str(user_id),
                count=len(user_candidates),
                lookback_hours=hours_lookback
            )
        
        # Track user source count separately for fallback decision
        user_source_count = len(candidates)
        total_candidates = len(candidates)
        
        # Étape 2: Fallback aux sources curatées si nécessaire
        # CRITICAL FIX: Use curated fallback if user sources < 3 OR total < min_pool_size
        # This ensures users always get a full digest even if they follow few sources
        max_lookback = 168  # 7 jours max
        fallback_iterations = 0
        
        # Enter fallback if we have fewer than 3 user sources OR need more candidates
        needs_fallback = user_source_count < 3 or total_candidates < min_pool_size
        
        logger.info(
            "digest_fallback_decision",
            user_id=str(user_id),
            user_source_count=user_source_count,
            total_candidates=total_candidates,
            min_pool_size=min_pool_size,
            needs_fallback=needs_fallback,
            condition_user_sources=f"{user_source_count} < 3",
            condition_total=f"{total_candidates} < {min_pool_size}"
        )
        
        if needs_fallback:
            for current_lookback in [hours_lookback, max_lookback]:
                fallback_iterations += 1
                
                if len(candidates) >= min_pool_size:
                    break
                    
                needed = min_pool_size - len(candidates)
                existing_ids = {c.id for c in candidates}
                since_fallback = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=current_lookback)
                
                fallback_query = (
                    select(Content)
                    .join(Content.source)
                    .options(selectinload(Content.source))
                    .where(
                        ~excluded_stmt,
                        Content.published_at >= since_fallback,
                        Source.is_curated == True,
                        # Exclure les articles déjà sélectionnés
                        Content.id.notin_(list(existing_ids)) if existing_ids else True,
                        # Respecter les mutes même en fallback
                        Source.id.notin_(list(context.muted_sources)) if context.muted_sources else True,
                        ~Source.theme.in_(list(context.muted_themes)) if context.muted_themes else True
                    )
                    .order_by(Content.published_at.desc())
                    .limit(needed * 3)  # Marge pour le scoring/diversité
                )
                
                # Filtrage des topics muets
                if context.muted_topics:
                    fallback_query = fallback_query.where(
                        or_(
                            Content.topics.is_(None),
                            ~Content.topics.overlap(list(context.muted_topics))
                        )
                    )

                # Filtrage des types de contenu mutés
                if context.muted_content_types:
                    fallback_query = fallback_query.where(
                        Content.content_type.notin_(list(context.muted_content_types))
                    )

                # Filtrage des articles payants (fallback, is_not(True) handles NULL rows)
                if context.hide_paid_content:
                    fallback_query = fallback_query.where(
                        Content.is_paid.is_not(True)
                    )

                # Appliquer les filtres de mode sur le fallback aussi
                if mode == DigestMode.SEREIN:
                    fallback_query = apply_serein_filter(fallback_query)
                elif mode == DigestMode.THEME_FOCUS and focus_theme:
                    fallback_query = apply_theme_focus_filter(fallback_query, focus_theme)

                # Prioriser les thèmes d'intérêt de l'utilisateur (seulement au premier essai)
                # Inclut les sources dont les secondary_themes matchent aussi
                if context.user_interests and current_lookback == hours_lookback:
                    interests_list = list(context.user_interests)
                    fallback_query = fallback_query.where(
                        or_(
                            Source.theme.in_(interests_list),
                            Source.secondary_themes.overlap(interests_list)
                        )
                    )
                
                result = await self.session.execute(fallback_query)
                fallback_candidates = list(result.scalars().all())
                candidates.extend(fallback_candidates)
                
                curated_count = len(candidates) - user_source_count
                
                logger.info(
                    "digest_candidates_fallback_iteration",
                    user_id=str(user_id),
                    iteration=fallback_iterations,
                    lookback_hours=current_lookback,
                    fetched_count=len(fallback_candidates),
                    total_count=len(candidates),
                    user_sources=user_source_count,
                    curated_sources=curated_count,
                    reason="user_sources_below_threshold_3"
                )
        else:
            logger.info(
                "digest_candidates_no_fallback_needed",
                user_id=str(user_id),
                user_source_count=user_source_count,
                total_candidates=len(candidates),
                min_pool_size=min_pool_size
            )
            
        if len(candidates) >= min_pool_size:
            curated_count = len(candidates) - user_source_count
            logger.info(
                "digest_candidates_pool_complete",
                user_id=str(user_id),
                total_candidates=len(candidates),
                user_sources=user_source_count,
                curated_sources=curated_count,
                user_to_curated_ratio=f"{user_source_count}:{curated_count}",
                fallback_iterations=fallback_iterations
            )
        else:
            curated_count = len(candidates) - user_source_count
            logger.warning(
                "digest_candidates_pool_insufficient",
                user_id=str(user_id),
                total_candidates=len(candidates),
                user_sources=user_source_count,
                curated_sources=curated_count,
                required=min_pool_size
            )
            
        return candidates
    
    async def _score_candidates(
        self,
        candidates: List[Content],
        context: DigestContext,
        mode: str = "pour_vous",
    ) -> List[Tuple[Content, float, List[DigestScoreBreakdown]]]:
        """Score les candidats en utilisant le ScoringEngine existant avec bonus de fraîcheur.

        Cette méthode utilise le ScoringEngine configuré dans RecommendationService
        et ajoute un bonus de fraîcheur hiérarchisé pour favoriser les articles
        des sources suivies même s'ils sont plus anciens.

        En mode PERSPECTIVE, ajoute un boost de +80 pts aux articles de biais opposé.

        Retourne les candidats avec leur score et un breakdown détaillé des contributions
        pour la transparence algorithmique.
        """
        # Construire le ScoringContext pour le moteur existant
        scoring_context = ScoringContext(
            user_profile=context.user_profile,
            user_interests=context.user_interests,
            user_interest_weights=context.user_interest_weights,
            followed_source_ids=context.followed_source_ids,
            user_prefs=context.user_prefs,
            now=datetime.datetime.now(datetime.timezone.utc),
            user_subtopics=context.user_subtopics,
            user_subtopic_weights=context.user_subtopic_weights,
            muted_sources=context.muted_sources,
            muted_themes=context.muted_themes,
            muted_topics=context.muted_topics,
            muted_content_types=context.muted_content_types,
            custom_source_ids=context.custom_source_ids
        )
        
        scored = []
        for content in candidates:
            breakdown: List[DigestScoreBreakdown] = []
            
            try:
                # Get base score from ScoringEngine
                base_score = self.rec_service.scoring_engine.compute_score(content, scoring_context)
                
                # Calculate recency bonus based on article age
                # Defensive: Ensure both datetimes are timezone-aware
                published = content.published_at
                now = datetime.datetime.now(datetime.timezone.utc)
                
                if published.tzinfo is None:
                    published = published.replace(tzinfo=datetime.timezone.utc)
                if now.tzinfo is None:
                    now = now.replace(tzinfo=datetime.timezone.utc)
                
                hours_old = (now - published).total_seconds() / 3600
                
                # Add recency contribution to breakdown
                if hours_old < 6:
                    recency_bonus = ScoringWeights.RECENT_VERY_BONUS  # +30
                    breakdown.append(DigestScoreBreakdown(
                        label="Article très récent (< 6h)",
                        points=recency_bonus,
                        is_positive=True
                    ))
                elif hours_old < 24:
                    recency_bonus = ScoringWeights.RECENT_BONUS  # +25
                    breakdown.append(DigestScoreBreakdown(
                        label="Article récent (< 24h)",
                        points=recency_bonus,
                        is_positive=True
                    ))
                elif hours_old < 48:
                    recency_bonus = ScoringWeights.RECENT_DAY_BONUS  # +15
                    breakdown.append(DigestScoreBreakdown(
                        label="Publié aujourd'hui",
                        points=recency_bonus,
                        is_positive=True
                    ))
                elif hours_old < 72:
                    recency_bonus = ScoringWeights.RECENT_YESTERDAY_BONUS  # +8
                    breakdown.append(DigestScoreBreakdown(
                        label="Publié hier",
                        points=recency_bonus,
                        is_positive=True
                    ))
                elif hours_old < 120:
                    recency_bonus = ScoringWeights.RECENT_WEEK_BONUS  # +3
                    breakdown.append(DigestScoreBreakdown(
                        label="Article de la semaine",
                        points=recency_bonus,
                        is_positive=True
                    ))
                elif hours_old < 168:
                    recency_bonus = ScoringWeights.RECENT_OLD_BONUS  # +1
                    breakdown.append(DigestScoreBreakdown(
                        label="Article ancien",
                        points=recency_bonus,
                        is_positive=True
                    ))
                else:
                    recency_bonus = 0.0
                
                # Mode PERSPECTIVE : boost articles de biais opposé
                perspective_bonus = 0.0
                if mode == DigestMode.PERSPECTIVE and context.user_bias_stance:
                    opposing = get_opposing_biases(context.user_bias_stance)
                    if content.source and content.source.bias_stance in opposing:
                        perspective_bonus = 80.0
                        breakdown.append(DigestScoreBreakdown(
                            label="Perspective opposée",
                            points=perspective_bonus,
                            is_positive=True
                        ))

                final_score = base_score + recency_bonus + perspective_bonus

                # Capture CoreLayer contributions
                # Theme match (3-tier: content.theme > source.theme > secondary)
                _theme_breakdown_added = False
                if hasattr(content, 'theme') and content.theme and content.theme in context.user_interests:
                    breakdown.append(DigestScoreBreakdown(
                        label=f"Thème article : {content.theme}",
                        points=ScoringWeights.THEME_MATCH,
                        is_positive=True
                    ))
                    _theme_breakdown_added = True
                elif content.source and content.source.theme in context.user_interests:
                    breakdown.append(DigestScoreBreakdown(
                        label=f"Thème matché : {content.source.theme}",
                        points=ScoringWeights.THEME_MATCH,
                        is_positive=True
                    ))
                    _theme_breakdown_added = True
                elif content.source and getattr(content.source, 'secondary_themes', None):
                    matched_sec = set(content.source.secondary_themes) & context.user_interests
                    if matched_sec:
                        sec_theme = sorted(matched_sec)[0]
                        sec_pts = ScoringWeights.THEME_MATCH * ScoringWeights.SECONDARY_THEME_FACTOR
                        breakdown.append(DigestScoreBreakdown(
                            label=f"Thème secondaire : {sec_theme}",
                            points=sec_pts,
                            is_positive=True
                        ))
                        _theme_breakdown_added = True
                
                # Source followed
                if content.source_id in context.followed_source_ids:
                    breakdown.append(DigestScoreBreakdown(
                        label="Source de confiance",
                        points=ScoringWeights.TRUSTED_SOURCE,
                        is_positive=True
                    ))
                    
                    # Custom source bonus
                    if content.source_id in context.custom_source_ids:
                        breakdown.append(DigestScoreBreakdown(
                            label="Ta source personnalisée",
                            points=ScoringWeights.CUSTOM_SOURCE_BONUS,
                            is_positive=True
                        ))
                
                # Capture ArticleTopicLayer contributions
                if content.topics:
                    matched_topics = 0
                    for topic in content.topics:
                        topic_lower = topic.lower()
                        if topic_lower in context.user_subtopics and matched_topics < 2:
                            w = context.user_subtopic_weights.get(topic_lower, 1.0)
                            points = ScoringWeights.TOPIC_MATCH * w
                            if w > 1.0:
                                label = f"Renforcé par vos j'aime : {topic}"
                            else:
                                label = f"Sous-thème : {topic}"
                            breakdown.append(DigestScoreBreakdown(
                                label=label,
                                points=points,
                                is_positive=True
                            ))
                            matched_topics += 1
                    
                    # Subtopic precision bonus if any topics matched
                    if matched_topics > 0:
                        breakdown.append(DigestScoreBreakdown(
                            label="Précision thématique",
                            points=ScoringWeights.SUBTOPIC_PRECISION_BONUS,
                            is_positive=True
                        ))
                
                # Capture StaticPreferenceLayer contributions
                if content.content_type and context.user_prefs.get('preferred_format'):
                    if content.content_type.value == context.user_prefs.get('preferred_format'):
                        breakdown.append(DigestScoreBreakdown(
                            label=f"Format préféré : {content.content_type.value}",
                            points=15.0,  # Format preference weight
                            is_positive=True
                        ))
                
                # Capture QualityLayer contributions
                if content.source and content.source.is_curated:
                    breakdown.append(DigestScoreBreakdown(
                        label="Source qualitative",
                        points=ScoringWeights.CURATED_SOURCE,
                        is_positive=True
                    ))
                
                # Low reliability penalty (if applicable)
                if content.source and hasattr(content.source, 'reliability_score'):
                    reliability = content.source.reliability_score
                    if reliability and reliability.value == "low":
                        breakdown.append(DigestScoreBreakdown(
                            label="Fiabilité source faible",
                            points=ScoringWeights.FQS_LOW_MALUS,
                            is_positive=False
                        ))
                
                logger.debug(
                    "digest_scoring_breakdown",
                    content_id=str(content.id),
                    hours_old=round(hours_old, 2),
                    base_score=round(base_score, 2),
                    recency_bonus=recency_bonus,
                    final_score=round(final_score, 2),
                    breakdown_count=len(breakdown)
                )
                
                scored.append((content, final_score, breakdown))
            except Exception as e:
                logger.error(
                    "digest_scoring_failed",
                    content_id=str(content.id),
                    source_id=str(content.source_id),
                    source_name=content.source.name if content.source else None,
                    published_at=str(content.published_at),
                    error=str(e),
                    error_type=type(e).__name__,
                    exc_info=True
                )
                # Attribuer un score minimal pour ne pas bloquer
                scored.append((content, 0.0, breakdown))
        
        # Trier par score décroissant
        scored.sort(key=lambda x: x[1], reverse=True)
        
        return scored
    
    def _select_with_diversity(
        self,
        scored_candidates: List[Tuple[Content, float, List[DigestScoreBreakdown]]],
        target_count: int,
        mode: str = "pour_vous",
        initial_source_counts: Optional[Dict[UUID, int]] = None,
        initial_theme_counts: Optional[Dict[str, int]] = None,
    ) -> List[Tuple[Content, float, str, List[DigestScoreBreakdown]]]:
        """Sélectionne les articles avec contraintes de diversité.

        Contraintes:
        - Maximum 1 article par source (fallback à 2 si < 5 sources distinctes)
        - Maximum 2 articles par thème (relaxé à 7 en mode THEME_FOCUS)
        - Minimum 3 sources différentes
        - Diversité revue de presse: score ÷ 2 dès le 2ème article d'une même source

        Args:
            initial_source_counts: Compteurs source pré-existants (pour continuité entre passes)
            initial_theme_counts: Compteurs thème pré-existants (pour continuité entre passes)

        Returns:
            Liste de tuples (Content, score, reason, breakdown)
        """
        DIVERSITY_DIVISOR = ScoringWeights.DIGEST_DIVERSITY_DIVISOR
        MIN_SOURCES = 3

        # Relax max_per_theme in THEME_FOCUS mode (all articles are same theme)
        effective_max_per_theme = self.constraints.MAX_PER_THEME
        if mode == DigestMode.THEME_FOCUS:
            effective_max_per_theme = target_count  # No theme limit

        # Count distinct sources in candidate pool for fallback decision
        distinct_sources = set(c.source_id for c, _, _ in scored_candidates)
        effective_max_per_source = self.constraints.MAX_PER_SOURCE

        if len(distinct_sources) < self.constraints.TARGET_DIGEST_SIZE:
            effective_max_per_source = 2
            logger.info(
                "digest_diversity_fallback_max_per_source",
                distinct_sources=len(distinct_sources),
                target=self.constraints.TARGET_DIGEST_SIZE,
                effective_max_per_source=effective_max_per_source
            )

        selected = []
        source_counts: Dict[UUID, int] = defaultdict(int, initial_source_counts or {})
        theme_counts: Dict[str, int] = defaultdict(int, initial_theme_counts or {})

        for content, score, breakdown in scored_candidates:
            if len(selected) >= target_count:
                break

            source_id = content.source_id
            # Utiliser content.theme ML si disponible, sinon source.theme
            theme = None
            if hasattr(content, 'theme') and content.theme:
                theme = content.theme
            elif content.source:
                theme = content.source.theme

            # Vérifier contraintes hard (max par source / thème)
            if source_counts[source_id] >= effective_max_per_source:
                continue

            if theme and theme_counts[theme] >= effective_max_per_theme:
                continue

            # Appliquer la pénalité diversité si source déjà présente
            current_source_count = source_counts.get(source_id, 0)
            if current_source_count > 0:
                # Score ÷ 2 pour le 2ème article d'une même source
                diversity_penalty = -(score / DIVERSITY_DIVISOR)
                final_score = score + diversity_penalty
                # Ajouter au breakdown pour transparence (règle d'or : visible à l'utilisateur)
                breakdown = list(breakdown)  # Copie pour ne pas muter l'original
                breakdown.append(DigestScoreBreakdown(
                    label="Diversité revue de presse",
                    points=round(diversity_penalty, 1),
                    is_positive=False
                ))
            else:
                final_score = score

            # Contraintes respectées - ajouter avec raison générée
            reason = self._generate_reason(content, source_counts, theme_counts, breakdown)
            selected.append((content, final_score, reason, breakdown))
            source_counts[source_id] += 1
            if theme:
                theme_counts[theme] += 1

        # Ensure minimum source diversity
        selected_sources = set(item[0].source_id for item in selected)
        if len(selected_sources) < self.constraints.MIN_SOURCES and len(scored_candidates) >= target_count:
            logger.warning(
                "digest_diversity_insufficient_sources",
                selected_sources=len(selected_sources),
                min_required=self.constraints.MIN_SOURCES
            )

        logger.debug(
            "digest_diversity_selection",
            selected_count=len(selected),
            source_distribution={str(k): v for k, v in source_counts.items()},
            theme_distribution=dict(theme_counts),
            diversity_divisor=DIVERSITY_DIVISOR,
            effective_max_per_source=effective_max_per_source
        )

        return selected
    
    _THEME_LABELS: Dict[str, str] = {
        'tech': 'Tech & Innovation',
        'society': 'Société',
        'environment': 'Environnement',
        'economy': 'Économie',
        'politics': 'Politique',
        'culture': 'Culture & Idées',
        'science': 'Sciences',
        'international': 'Géopolitique',
        'geopolitics': 'Géopolitique',
        'society_climate': 'Société',
        'culture_ideas': 'Culture & Idées',
    }

    def _generate_reason(
        self,
        content: Content,
        source_counts: Dict[UUID, int],
        theme_counts: Dict[str, int],
        breakdown: Optional[List[DigestScoreBreakdown]] = None
    ) -> str:
        """Génère la raison de sélection pour affichage utilisateur.

        Priorité : trending/une > sous-thème > thème > source suivie > fallback.
        Le détail des scores reste dans le breakdown (personalization sheet).
        """
        # 0. Trending ou À la une (prioritaire)
        if breakdown:
            for b in breakdown:
                if b.label == "Sujet du jour":
                    return "Sujet du jour"
                if b.label == "À la une":
                    return "À la une"

        # 1. Sous-thème matché (le plus précis) — ex: "Thème : AI"
        if breakdown:
            for b in breakdown:
                if b.label.startswith("Sous-thème : "):
                    topic = b.label.removeprefix("Sous-thème : ")
                    return f"Thème : {topic}"

        # 2. Thème article ML ou thème source — ex: "Thème : Environnement"
        theme = None
        if hasattr(content, 'theme') and content.theme:
            theme = content.theme
        elif content.source:
            theme = content.source.theme
        if theme:
            label = self._THEME_LABELS.get(theme.lower(), theme.capitalize())
            return f"Thème : {label}"

        # 3. Source suivie (aucun thème disponible)
        if breakdown:
            for b in breakdown:
                if b.label == "Source de confiance":
                    return "Source suivie"

        # 4. Fallback
        return "Sélectionné pour vous"

    async def _two_pass_selection(
        self,
        candidates: list[Content],
        context: DigestContext,
        trending_context: GlobalTrendingContext,
        target_count: int,
    ) -> list[tuple[Content, float, str, list[DigestScoreBreakdown]]]:
        """Sélection hybride en 2 passes : trending + personnalisé.

        Pass 1 : Sélectionner les articles trending/une pertinents pour l'utilisateur
                 (max ~half of target_count).
        Pass 2 : Compléter avec les meilleurs articles personnalisés (algorithme existant),
                 en excluant les articles de Pass 1.

        Les contraintes de diversité (max 1/source, max 2/theme) s'appliquent globalement.
        """
        trending_target = ceil(target_count * ScoringWeights.DIGEST_TRENDING_TARGET_RATIO)

        # Partitionner les candidats en trending pertinent vs personnalisé
        trending_candidates: list[Content] = []
        personalized_candidates: list[Content] = []

        all_important_ids = trending_context.trending_content_ids | trending_context.une_content_ids

        for content in candidates:
            if content.id in all_important_ids:
                # Vérifier la pertinence pour l'utilisateur
                source_theme = content.source.theme if content.source else None
                content_theme = getattr(content, 'theme', None)
                secondary_themes = getattr(content.source, 'secondary_themes', None) or []

                is_relevant = (
                    content.source_id in context.followed_source_ids
                    or (content_theme and content_theme in context.user_interests)
                    or (source_theme and source_theme in context.user_interests)
                    or bool(set(secondary_themes) & context.user_interests)
                )

                if is_relevant:
                    trending_candidates.append(content)
                else:
                    personalized_candidates.append(content)
            else:
                personalized_candidates.append(content)

        logger.info(
            "digest_two_pass_pools",
            trending_relevant=len(trending_candidates),
            personalized=len(personalized_candidates),
            trending_target=trending_target,
        )

        # === PASSE 1 : Score et sélection trending ===
        _4t = list[tuple[Content, float, str, list[DigestScoreBreakdown]]]
        pass1_selected: _4t = []
        if trending_candidates:
            scored_trending = await self._score_candidates(
                trending_candidates, context, mode="pour_vous",
            )

            # Ajouter les bonus trending/une
            _3t = list[tuple[Content, float, list[DigestScoreBreakdown]]]
            boosted_trending: _3t = []
            for content, score, breakdown in scored_trending:
                bonus = 0.0
                bd_copy = list(breakdown)

                if content.id in trending_context.trending_content_ids:
                    bonus += ScoringWeights.DIGEST_TRENDING_BONUS
                    bd_copy.append(DigestScoreBreakdown(
                        label="Sujet du jour",
                        points=ScoringWeights.DIGEST_TRENDING_BONUS,
                        is_positive=True,
                    ))

                if content.id in trending_context.une_content_ids:
                    bonus += ScoringWeights.DIGEST_UNE_BONUS
                    bd_copy.append(DigestScoreBreakdown(
                        label="À la une",
                        points=ScoringWeights.DIGEST_UNE_BONUS,
                        is_positive=True,
                    ))

                boosted_trending.append((content, score + bonus, bd_copy))

            # Trier par score boosté décroissant
            boosted_trending.sort(key=lambda x: x[1], reverse=True)

            # Sélectionner avec diversité (max trending_target)
            pass1_selected = self._select_with_diversity(
                scored_candidates=boosted_trending,
                target_count=trending_target,
                mode="pour_vous",
            )

        logger.info("digest_pass1_result", count=len(pass1_selected))

        # === PASSE 2 : Compléter avec personnalisé ===
        remaining_count = target_count - len(pass1_selected)
        pass2_selected: _4t = []

        if remaining_count > 0 and personalized_candidates:
            scored_personalized = await self._score_candidates(
                personalized_candidates, context, mode="pour_vous",
            )

            # Construire les compteurs existants depuis pass 1 pour continuité diversité
            pass1_source_counts: Dict[UUID, int] = defaultdict(int)
            pass1_theme_counts: Dict[str, int] = defaultdict(int)
            for content, _, _, _ in pass1_selected:
                pass1_source_counts[content.source_id] += 1
                theme = getattr(content, 'theme', None)
                if not theme and content.source:
                    theme = content.source.theme
                if theme:
                    pass1_theme_counts[theme] += 1

            pass2_selected = self._select_with_diversity(
                scored_candidates=scored_personalized,
                target_count=remaining_count,
                mode="pour_vous",
                initial_source_counts=dict(pass1_source_counts),
                initial_theme_counts=dict(pass1_theme_counts),
            )

        logger.info("digest_pass2_result", count=len(pass2_selected))

        return pass1_selected + pass2_selected

    async def _build_global_trending_context(self) -> GlobalTrendingContext:
        """Construit le contexte trending global (toutes sources, 24h).

        Coûteux : fetch tous les contenus récents + parse les flux une.
        Doit être appelé 1x par batch, ou avec cache court pour on-demand.
        """
        # 1. Fetch contenus des dernières 24h (toutes sources actives)
        now = datetime.datetime.now(datetime.timezone.utc)
        since = now - datetime.timedelta(hours=24)
        stmt = (
            select(Content)
            .join(Content.source)
            .options(selectinload(Content.source))
            .where(
                Content.published_at >= since,
                Source.is_active == True,  # noqa: E712
            )
        )
        result = await self.session.execute(stmt)
        recent_contents = list(result.scalars().all())

        # 2. Détecter les clusters trending
        trending_ids = self.importance_detector.detect_trending_clusters(
            recent_contents,
        )

        # 3. Fetch GUIDs "À la une" et identifier les contenus une
        une_guids = await self._fetch_une_guids()
        une_ids = self.importance_detector.identify_une_contents(
            recent_contents, une_guids,
        )

        logger.info(
            "global_trending_context_built",
            recent_contents=len(recent_contents),
            trending_count=len(trending_ids),
            une_count=len(une_ids),
        )

        return GlobalTrendingContext(
            trending_content_ids=trending_ids,
            une_content_ids=une_ids,
            computed_at=now,
        )

    async def _fetch_une_guids(self) -> Set[str]:
        """Récupère les GUIDs des articles 'À la Une'."""
        import feedparser as fp

        stmt = select(Source).where(Source.une_feed_url.is_not(None))
        result = await self.session.execute(stmt)
        sources = result.scalars().all()

        if not sources:
            return set()

        une_guids: Set[str] = set()

        async def parse_feed(url: str) -> list[str]:
            try:
                loop = asyncio.get_event_loop()
                feed = await loop.run_in_executor(None, fp.parse, url)
                return [
                    entry.id if hasattr(entry, 'id') else entry.link
                    for entry in feed.entries[:5]
                ]
            except Exception as e:
                logger.warning("une_feed_parse_failed", url=url, error=str(e))
                return []

        tasks = [parse_feed(source.une_feed_url) for source in sources]
        results = await asyncio.gather(*tasks)
        for guids in results:
            une_guids.update(guids)

        return une_guids
