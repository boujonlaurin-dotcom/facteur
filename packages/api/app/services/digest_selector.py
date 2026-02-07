from __future__ import annotations
"""Service de sélection d'articles pour le Digest quotidien (5 articles).

Ce service implémente l'algorithme de sélection intelligent pour Epic 10,
avec contraintes de diversité et mécanisme de fallback.

Contraintes de diversité:
- Maximum 2 articles par source
- Maximum 2 articles par thème

Fallback:
- Si le pool utilisateur < 5 articles, complète avec les sources curatées

Réutilise l'infrastructure de scoring existante sans modification.
"""

import datetime
import time
from dataclasses import dataclass
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
from app.models.enums import ContentStatus
from app.services.recommendation_service import RecommendationService
from app.services.recommendation.scoring_engine import ScoringContext
from app.services.recommendation.scoring_config import ScoringWeights
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
    muted_sources: Set[UUID]
    muted_themes: Set[str]
    muted_topics: Set[str]


class DiversityConstraints:
    """Configuration des contraintes de diversité."""
    MAX_PER_SOURCE = 2
    MAX_PER_THEME = 2
    TARGET_DIGEST_SIZE = 5


class DigestSelector:
    """Sélecteur intelligent d'articles pour le digest quotidien.
    
    Cette classe implémente la logique de sélection des 5 articles
    du digest avec garanties de diversité et mécanisme de fallback.
    
    Usage:
        selector = DigestSelector(session)
        digest_items = await selector.select_for_user(user_id)
    """
    
    def __init__(self, session: AsyncSession):
        self.session = session
        self.rec_service = RecommendationService(session)
        self.constraints = DiversityConstraints()
        
    async def select_for_user(
        self, 
        user_id: UUID, 
        limit: int = 5,
        hours_lookback: int = 168
    ) -> List[DigestItem]:
        """Sélectionne les articles pour le digest d'un utilisateur.
        
        Args:
            user_id: ID de l'utilisateur
            limit: Nombre d'articles à sélectionner (défaut: 5)
            hours_lookback: Fenêtre temporelle pour les candidats (défaut: 48h)
            
        Returns:
            Liste de DigestItem ordonnée par rank (1 à limit)
            
        Raises:
            Aucune exception - retourne une liste vide en cas d'erreur
        """
        start_time = time.time()
        
        try:
            logger.info("digest_selection_started", user_id=str(user_id), limit=limit)
            
            # 1. Construire le contexte utilisateur
            step_start = time.time()
            context = await self._build_digest_context(user_id)
            context_time = time.time() - step_start
            
            if not context.user_profile:
                logger.warning("digest_selection_no_profile", user_id=str(user_id))
                return []
            
            logger.info("digest_selector_context_built", user_id=str(user_id), duration_ms=round(context_time * 1000, 2))
            
            # 2. Récupérer les candidats
            step_start = time.time()
            candidates = await self._get_candidates(
                user_id=user_id,
                context=context,
                hours_lookback=hours_lookback,
                min_pool_size=limit
            )
            candidates_time = time.time() - step_start
            
            if not candidates:
                logger.warning("digest_selection_no_candidates", user_id=str(user_id), duration_ms=round(candidates_time * 1000, 2))
                return []
            
            logger.info("digest_selector_candidates_fetched", user_id=str(user_id), count=len(candidates), duration_ms=round(candidates_time * 1000, 2))
            
            # 3. Scorer les candidats
            step_start = time.time()
            scored_candidates_with_breakdown = await self._score_candidates(candidates, context)
            scoring_time = time.time() - step_start
            
            # DEBUG: Compter les scores nuls vs non-nuls
            non_zero_scores = [s for _, s, _ in scored_candidates_with_breakdown if s > 0]
            zero_scores = [s for _, s, _ in scored_candidates_with_breakdown if s == 0]
            
            logger.info(
                "digest_selector_scoring_done",
                user_id=str(user_id),
                count=len(scored_candidates_with_breakdown),
                non_zero_count=len(non_zero_scores),
                zero_count=len(zero_scores),
                max_score=round(max((s for _, s, _ in scored_candidates_with_breakdown), default=0), 2),
                duration_ms=round(scoring_time * 1000, 2)
            )
            
            # 4. Sélectionner avec contraintes de diversité
            step_start = time.time()
            selected = self._select_with_diversity(
                scored_candidates=scored_candidates_with_breakdown,
                target_count=limit
            )
            diversity_time = time.time() - step_start
            
            logger.info(
                "digest_diversity_selection_result",
                user_id=str(user_id),
                selected_count=len(selected),
                target_count=limit,
                had_candidates=len(scored_candidates_with_breakdown) > 0
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
                sources=list(set(item.content.source_id for item in digest_items)),
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
    
    async def _build_digest_context(self, user_id: UUID) -> DigestContext:
        """Construit le contexte utilisateur pour la sélection.
        
        Récupère les données utilisateur nécessaires depuis la base de données.
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
        
        # Récupérer les sous-thèmes
        subtopics_stmt = select(UserSubtopic.topic_slug).where(UserSubtopic.user_id == user_id)
        subtopics_result = await self.session.execute(subtopics_stmt)
        user_subtopics = set(subtopics_result.scalars().all())
        
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
        
        if personalization:
            if personalization.muted_sources:
                muted_sources = set(s for s in personalization.muted_sources if s is not None)
            if personalization.muted_themes:
                muted_themes = set(t.lower() for t in personalization.muted_themes if t)
            if personalization.muted_topics:
                muted_topics = set(t.lower() for t in personalization.muted_topics if t)
        
        return DigestContext(
            user_id=user_id,
            user_profile=user_profile,
            user_interests=user_interests,
            user_interest_weights=user_interest_weights,
            followed_source_ids=followed_source_ids,
            custom_source_ids=custom_source_ids,
            user_prefs=user_prefs,
            user_subtopics=user_subtopics,
            muted_sources=muted_sources,
            muted_themes=muted_themes,
            muted_topics=muted_topics
        )
    
    async def _get_candidates(
        self,
        user_id: UUID,
        context: DigestContext,
        hours_lookback: int,
        min_pool_size: int
    ) -> List[Content]:
        """Récupère les candidats pour le digest.
        
        Strategy:
        1. D'abord, récupérer les articles des sources suivies par l'utilisateur
        2. Si pool insuffisant (< min_pool_size), compléter avec sources curatées
        3. Exclure les articles déjà vus, sauvegardés, ou masqués
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
                
                # Prioriser les thèmes d'intérêt de l'utilisateur (seulement au premier essai)
                if context.user_interests and current_lookback == hours_lookback:
                    fallback_query = fallback_query.where(
                        Source.theme.in_(list(context.user_interests))
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
        context: DigestContext
    ) -> List[Tuple[Content, float, List[DigestScoreBreakdown]]]:
        """Score les candidats en utilisant le ScoringEngine existant avec bonus de fraîcheur.
        
        Cette méthode utilise le ScoringEngine configuré dans RecommendationService
        et ajoute un bonus de fraîcheur hiérarchisé pour favoriser les articles
        des sources suivies même s'ils sont plus anciens.
        
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
            muted_sources=context.muted_sources,
            muted_themes=context.muted_themes,
            muted_topics=context.muted_topics,
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
                
                final_score = base_score + recency_bonus
                
                # Capture CoreLayer contributions
                # Theme match
                if content.source and content.source.theme in context.user_interests:
                    breakdown.append(DigestScoreBreakdown(
                        label=f"Thème matché : {content.source.theme}",
                        points=ScoringWeights.THEME_MATCH,
                        is_positive=True
                    ))
                
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
                        if topic.lower() in context.user_subtopics and matched_topics < 2:
                            breakdown.append(DigestScoreBreakdown(
                                label=f"Sous-thème : {topic}",
                                points=ScoringWeights.TOPIC_MATCH,
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
                    if reliability and reliability < 0.5:
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
        target_count: int
    ) -> List[Tuple[Content, float, str, List[DigestScoreBreakdown]]]:
        """Sélectionne les articles avec contraintes de diversité.

        Contraintes:
        - Maximum 2 articles par source
        - Maximum 2 articles par thème
        - Minimum 3 sources différentes
        - Facteur de décroissance: 0.70 (même algorithme que le feed)

        Algorithme:
        1. Parcourir les candidats par ordre de score
        2. Pour chaque candidat, appliquer le facteur de décroissance
        3. Vérifier les contraintes avec les scores pondérés
        4. Si contraintes respectées, ajouter à la sélection
        5. S'arrêter quand on atteint target_count

        Returns:
            Liste de tuples (Content, score, reason, breakdown)
        """
        DECAY_FACTOR = 0.70  # Same as feed algorithm
        MIN_SOURCES = 3

        selected = []
        source_counts = defaultdict(int)
        theme_counts = defaultdict(int)

        for content, score, breakdown in scored_candidates:
            if len(selected) >= target_count:
                break

            source_id = content.source_id
            theme = content.source.theme if content.source else None

            # Apply decay factor based on how many articles already selected from this source
            current_source_count = source_counts.get(source_id, 0)
            decayed_score = score * (DECAY_FACTOR ** current_source_count)

            # Vérifier contraintes
            if source_counts[source_id] >= self.constraints.MAX_PER_SOURCE:
                continue

            if theme and theme_counts[theme] >= self.constraints.MAX_PER_THEME:
                continue

            # Contraintes respectées - ajouter avec raison générée
            reason = self._generate_reason(content, source_counts, theme_counts, breakdown)
            selected.append((content, decayed_score, reason, breakdown))
            source_counts[source_id] += 1
            if theme:
                theme_counts[theme] += 1

        # Ensure minimum source diversity
        selected_sources = set(item[0].source_id for item in selected)
        if len(selected_sources) < MIN_SOURCES and len(scored_candidates) >= target_count:
            logger.warning(
                "digest_diversity_insufficient_sources",
                selected_sources=len(selected_sources),
                min_required=MIN_SOURCES
            )

        logger.debug(
            "digest_diversity_selection",
            selected_count=len(selected),
            source_distribution=dict(source_counts),
            theme_distribution=dict(theme_counts),
            decay_factor=DECAY_FACTOR
        )

        return selected
    
    def _generate_reason(
        self,
        content: Content,
        source_counts: Dict[UUID, int],
        theme_counts: Dict[str, int],
        breakdown: Optional[List[DigestScoreBreakdown]] = None
    ) -> str:
        """Génère la raison de sélection pour affichage utilisateur.

        Les raisons sont en français pour l'interface utilisateur.
        """
        source_id = content.source_id
        theme = content.source.theme if content.source else None

        # Extract recency bonus from breakdown for backward compatibility
        recency_bonus = 0.0
        if breakdown:
            for b in breakdown:
                if b.label.startswith(("Article très récent", "Article récent", "Publié")):
                    recency_bonus = b.points
                    break
        
        # Build bonus suffix if applicable
        bonus_suffix = f" (+{int(recency_bonus)} pts)" if recency_bonus > 0 else ""

        # Première occurrence d'une source suivie
        if source_counts.get(source_id, 0) == 0 and content.source:
            return f"Source suivie : {content.source.name}{bonus_suffix}"

        # Premier article d'un thème d'intérêt
        if theme and theme_counts.get(theme, 0) == 0:
            theme_labels = {
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
            theme_label = theme_labels.get(theme.lower(), theme.capitalize())
            return f"Vos intérêts : {theme_label}{bonus_suffix}"

        # Fallback générique
        if content.source:
            return f"Sélectionné pour vous depuis {content.source.name}{bonus_suffix}"

        return f"Sélectionné pour vous{bonus_suffix}"
