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

logger = structlog.get_logger()


@dataclass
class DigestItem:
    """Représente un article sélectionné pour le digest.
    
    Attributes:
        content: L'article Content sélectionné
        score: Le score calculé par le ScoringEngine
        rank: La position dans le digest (1-5)
        reason: La raison de sélection (pour affichage utilisateur)
    """
    content: Content
    score: float
    rank: int
    reason: str


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
        hours_lookback: int = 48
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
        try:
            logger.info("digest_selection_started", user_id=str(user_id), limit=limit)
            
            # 1. Construire le contexte utilisateur
            context = await self._build_digest_context(user_id)
            
            if not context.user_profile:
                logger.warning("digest_selection_no_profile", user_id=str(user_id))
                return []
            
            # 2. Récupérer les candidats
            candidates = await self._get_candidates(
                user_id=user_id,
                context=context,
                hours_lookback=hours_lookback,
                min_pool_size=limit
            )
            
            if not candidates:
                logger.warning("digest_selection_no_candidates", user_id=str(user_id))
                return []
            
            # 3. Scorer les candidats
            scored_candidates = await self._score_candidates(candidates, context)
            
            # 4. Sélectionner avec contraintes de diversité
            selected = self._select_with_diversity(
                scored_candidates=scored_candidates,
                target_count=limit
            )
            
            # 5. Construire les résultats
            digest_items = []
            for i, (content, score, reason) in enumerate(selected, 1):
                digest_items.append(DigestItem(
                    content=content,
                    score=score,
                    rank=i,
                    reason=reason
                ))
            
            logger.info(
                "digest_selection_completed", 
                user_id=str(user_id), 
                count=len(digest_items),
                sources=list(set(item.content.source_id for item in digest_items)),
                themes=list(set(item.content.source.theme for item in digest_items if item.content.source))
            )
            
            return digest_items
            
        except Exception as e:
            logger.error("digest_selection_error", user_id=str(user_id), error=str(e))
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
        since = datetime.datetime.utcnow() - datetime.timedelta(hours=hours_lookback)
        
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
        
        # Étape 1: Articles des sources suivies
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
            
            logger.debug(
                "digest_candidates_user_sources",
                user_id=str(user_id),
                count=len(user_candidates)
            )
        
        # Étape 2: Fallback aux sources curatées si nécessaire
        if len(candidates) < min_pool_size:
            needed = min_pool_size - len(candidates)
            existing_ids = {c.id for c in candidates}
            
            fallback_query = (
                select(Content)
                .join(Content.source)
                .options(selectinload(Content.source))
                .where(
                    ~excluded_stmt,
                    Content.published_at >= since,
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
            
            # Prioriser les thèmes d'intérêt de l'utilisateur
            if context.user_interests:
                fallback_query = fallback_query.where(
                    Source.theme.in_(list(context.user_interests))
                )
            
            result = await self.session.execute(fallback_query)
            fallback_candidates = list(result.scalars().all())
            candidates.extend(fallback_candidates)
            
            logger.info(
                "digest_candidates_fallback_used",
                user_id=str(user_id),
                fallback_count=len(fallback_candidates),
                total_count=len(candidates)
            )
        
        return candidates
    
    async def _score_candidates(
        self,
        candidates: List[Content],
        context: DigestContext
    ) -> List[Tuple[Content, float]]:
        """Score les candidats en utilisant le ScoringEngine existant.
        
        Cette méthode utilise le ScoringEngine configuré dans RecommendationService
        sans aucune modification de l'algorithme de scoring.
        """
        # Construire le ScoringContext pour le moteur existant
        scoring_context = ScoringContext(
            user_profile=context.user_profile,
            user_interests=context.user_interests,
            user_interest_weights=context.user_interest_weights,
            followed_source_ids=context.followed_source_ids,
            user_prefs=context.user_prefs,
            now=datetime.datetime.utcnow(),
            user_subtopics=context.user_subtopics,
            muted_sources=context.muted_sources,
            muted_themes=context.muted_themes,
            muted_topics=context.muted_topics,
            custom_source_ids=context.custom_source_ids
        )
        
        scored = []
        for content in candidates:
            try:
                score = self.rec_service.scoring_engine.compute_score(content, scoring_context)
                scored.append((content, score))
            except Exception as e:
                logger.warning(
                    "digest_scoring_failed",
                    content_id=str(content.id),
                    error=str(e)
                )
                # Attribuer un score minimal pour ne pas bloquer
                scored.append((content, 0.0))
        
        # Trier par score décroissant
        scored.sort(key=lambda x: x[1], reverse=True)
        
        return scored
    
    def _select_with_diversity(
        self,
        scored_candidates: List[Tuple[Content, float]],
        target_count: int
    ) -> List[Tuple[Content, float, str]]:
        """Sélectionne les articles avec contraintes de diversité.
        
        Contraintes:
        - Maximum 2 articles par source
        - Maximum 2 articles par thème
        
        Algorithme:
        1. Parcourir les candidats par ordre de score
        2. Pour chaque candidat, vérifier les contraintes
        3. Si contraintes respectées, ajouter à la sélection
        4. S'arrêter quand on atteint target_count
        
        Returns:
            Liste de tuples (Content, score, reason)
        """
        selected = []
        source_counts = defaultdict(int)
        theme_counts = defaultdict(int)
        
        for content, score in scored_candidates:
            if len(selected) >= target_count:
                break
            
            source_id = content.source_id
            theme = content.source.theme if content.source else None
            
            # Vérifier contraintes
            if source_counts[source_id] >= self.constraints.MAX_PER_SOURCE:
                continue
            
            if theme and theme_counts[theme] >= self.constraints.MAX_PER_THEME:
                continue
            
            # Contraintes respectées - ajouter
            selected.append((content, score, self._generate_reason(content, source_counts, theme_counts)))
            source_counts[source_id] += 1
            if theme:
                theme_counts[theme] += 1
        
        logger.debug(
            "digest_diversity_selection",
            selected_count=len(selected),
            source_distribution=dict(source_counts),
            theme_distribution=dict(theme_counts)
        )
        
        return selected
    
    def _generate_reason(
        self,
        content: Content,
        source_counts: Dict[UUID, int],
        theme_counts: Dict[str, int]
    ) -> str:
        """Génère la raison de sélection pour affichage utilisateur.
        
        Les raisons sont en français pour l'interface utilisateur.
        """
        source_id = content.source_id
        theme = content.source.theme if content.source else None
        
        # Première occurrence d'une source suivie
        if source_counts.get(source_id, 0) == 0 and content.source:
            return f"Source suivie : {content.source.name}"
        
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
            return f"Vos intérêts : {theme_label}"
        
        # Fallback générique
        if content.source:
            return f"Sélectionné pour vous depuis {content.source.name}"
        
        return "Sélectionné pour vous"
