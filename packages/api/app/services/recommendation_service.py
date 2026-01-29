import datetime
from typing import List, Optional, Set
from uuid import UUID
import asyncio

import structlog
from sqlalchemy import select, desc, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.source import Source, UserSource
from app.models.user import UserInterest, UserProfile, UserSubtopic
from app.models.enums import ContentStatus, FeedFilterMode, ContentType, BiasStance

logger = structlog.get_logger()

from app.services.recommendation.scoring_engine import ScoringEngine, ScoringContext
from app.services.recommendation.layers import CoreLayer, StaticPreferenceLayer, BehavioralLayer, QualityLayer, VisualLayer, ArticleTopicLayer, PersonalizationLayer
from app.schemas.content import RecommendationReason, ScoreContribution

# Mots-clés filtrés par défaut pour le mode "Rester serein"
SERENE_FILTER_KEYWORDS = [
    'politique', 'guerre', 'conflit', 'élections', 'inflation', 'grève', 'drame',
    'fait divers', 'faits divers', 'crise', 'scandale', 'terrorisme', 'corruption',
    'procès', 'violence', 'catastrophe', 'manifestation', 'géopolitique',
    'trump', 'musk', 'poutine', 'macron', 'netanyahou', 'zelensky', 'ukraine', 'gaza'
]

class RecommendationService:
    def __init__(self, session: AsyncSession):
        self.session = session
        # Initialisation du moteur avec les couches configurées
        # L'ordre n'affecte pas le score (somme), mais affecte les logs/debugging
        self.scoring_engine = ScoringEngine([
            CoreLayer(),
            StaticPreferenceLayer(),
            BehavioralLayer(),
            QualityLayer(),
            VisualLayer(),
            ArticleTopicLayer(),
            PersonalizationLayer()  # Story 4.7
        ])

    async def get_feed(self, user_id: UUID, limit: int = 20, offset: int = 0, content_type: Optional[str] = None, mode: Optional[FeedFilterMode] = None, saved_only: bool = False) -> List[Content]:
        """
        Génère un feed personnalisé pour l'utilisateur.
        
        Algorithme V2 (Modular Scoring):
        1. Récupérer les candidats.
        2. Scorer via ScoringEngine (Core + Prefs + Behavioral).
        3. Appliquer la pénalité de fatigue de source (Diversité).
        4. Trier et paginer.
        """
        # 1. Fetch user profile with interests and preferences
        from sqlalchemy.orm import joinedload
        from app.models.user_personalization import UserPersonalization
        
        # Batch independent DB calls
        # We need followed_source_ids, subtopics and personalization
        user_profile_fut = self.session.scalar(
            select(UserProfile)
            .options(
                joinedload(UserProfile.interests),
                joinedload(UserProfile.preferences)
            )
            .where(UserProfile.user_id == user_id)
        )
        
        followed_sources_fut = self.session.execute(
            select(UserSource.source_id, UserSource.is_custom).where(UserSource.user_id == user_id)
        )
        
        subtopics_fut = self.session.scalars(
            select(UserSubtopic.topic_slug).where(UserSubtopic.user_id == user_id)
        )
        
        personalization_fut = self.session.scalar(
            select(UserPersonalization).where(UserPersonalization.user_id == user_id)
        )
        
        # Execute sequentially because SQLAlchemy AsyncSession is not thread-safe for concurrent operations
        user_profile = await user_profile_fut
        followed_sources_res = await followed_sources_fut
        
        followed_source_ids = set()
        custom_source_ids = set()
        for row in followed_sources_res:
             followed_source_ids.add(row.source_id)
             if row.is_custom:
                 custom_source_ids.add(row.source_id)
        
        subtopics_res = await subtopics_fut
        personalization = await personalization_fut
        user_subtopics = set(subtopics_res.all())
        
        user_interests = set()
        user_interest_weights = {}
        user_prefs = {}
        
        if user_profile:
            for i in user_profile.interests:
                user_interests.add(i.interest_slug)
                user_interest_weights[i.interest_slug] = i.weight
                
            for p in user_profile.preferences:
                user_prefs[p.preference_key] = p.preference_value
        
        if saved_only:
             # Fetch saved items directly
             stmt = (
                 select(UserContentStatus)
                 .options(selectinload(UserContentStatus.content).options(selectinload(Content.source)))
                 .where(
                     UserContentStatus.user_id == user_id,
                     UserContentStatus.is_saved == True
                 )
                 .order_by(desc(func.coalesce(UserContentStatus.saved_at, UserContentStatus.updated_at)))
                 .offset(offset)
                 .limit(limit)
             )
             
             statuses = await self.session.scalars(stmt)
             results = []
             for st in statuses:
                 content = st.content
                 # Populate transient fields
                 content.is_saved = True
                 content.is_hidden = st.is_hidden
                 content.hidden_reason = st.hidden_reason
                 content.status = st.status
                 results.append(content)
                 
             return results
        
        # 2. Get Candidates (Top 500 recent unseen contents)
        # Story 4.7: Personalization filters
        muted_sources = set(personalization.muted_sources) if personalization and personalization.muted_sources else set()
        muted_themes = set(t.lower() for t in personalization.muted_themes) if personalization and personalization.muted_themes else set()
        muted_topics = set(t.lower() for t in personalization.muted_topics) if personalization and personalization.muted_topics else set()

        candidates = await self._get_candidates(
            user_id, 
            limit_candidates=500,
            content_type=content_type,
            mode=mode,
            followed_source_ids=followed_source_ids,
            # Story 4.7 : Filter out muted items at DB level
            muted_sources=muted_sources,
            muted_themes=muted_themes,
            muted_topics=muted_topics
        )
        
        # 3. Score Candidates using ScoringEngine
        scored_candidates = []
        now = datetime.datetime.utcnow()
        
        # Context creation
        context = ScoringContext(
            user_profile=user_profile,
            user_interests=user_interests,
            user_interest_weights=user_interest_weights,
            followed_source_ids=followed_source_ids,
            user_prefs=user_prefs,
            now=now,
            user_subtopics=user_subtopics,
            # Story 4.7
            muted_sources=muted_sources,
            muted_themes=muted_themes,
            muted_topics=muted_topics,
            custom_source_ids=custom_source_ids
        )
        
        for content in candidates:
            score = self.scoring_engine.compute_score(content, context)
            scored_candidates.append((content, score))
            
        # 4. Sort by score DESC
        scored_candidates.sort(key=lambda x: x[1], reverse=True)
        
        # 4b. Diversity Re-ranking (Source Fatigue)
        # Apply a cumulative penalty for multiple items from the same source
        # to ensure a diverse top-of-feed.
        final_list = []
        source_counts = {}
        decay_factor = 0.85 # Each subsequent item from same source loses 15% score
        
        for content, base_score in scored_candidates:
             source_id = content.source_id
             count = source_counts.get(source_id, 0)
             
             # FinalScore = BaseScore * (decay_factor ^ count)
             final_score = base_score * (decay_factor ** count)
             
             final_list.append((content, final_score))
             source_counts[source_id] = count + 1
             
        # Sort again with diversity penalties applied to find the new Top-N
        final_list.sort(key=lambda x: x[1], reverse=True)
        
        # 5. Paginate
        scored_candidates = final_list
        start = offset
        end = offset + limit
        # Check bounds
        if start >= len(scored_candidates):
            return []
            
    
        result = [item[0] for item in scored_candidates[start:end]]
        
        # 5.5 Hydrate Recommendation Reason (Transparency)
        for content in result:
            reasons_list = context.reasons.get(content.id, [])
            if reasons_list:
                # Mapping des 8 thèmes macro -> Français
                THEME_TRANSLATIONS = {
                    "tech": "Tech & Innovation",
                    "society": "Société",
                    "environment": "Environnement",
                    "economy": "Économie",
                    "politics": "Politique",
                    "culture": "Culture & Idées",
                    "science": "Sciences",
                    "international": "Géopolitique",
                    # Legacy/synonymes pour rétrocompatibilité
                    "geopolitics": "Géopolitique",
                    "society_climate": "Société",
                    "culture_ideas": "Culture & Idées",
                }
                
                # Mapping des 50 sous-thèmes -> Français
                SUBTOPIC_TRANSLATIONS = {
                    # Tech (12)
                    "ai": "IA", "llm": "LLM", "crypto": "Crypto", "web3": "Web3",
                    "space": "Spatial", "biotech": "Biotech", "quantum": "Quantique",
                    "cybersecurity": "Cybersécurité", "robotics": "Robotique",
                    "gaming": "Gaming", "cleantech": "Cleantech", "data-privacy": "Données",
                    # Society (10)
                    "social-justice": "Justice sociale", "feminism": "Féminisme",
                    "lgbtq": "LGBTQ+", "immigration": "Immigration", "health": "Santé",
                    "education": "Éducation", "urbanism": "Urbanisme", "housing": "Logement",
                    "work-reform": "Travail", "justice-system": "Justice",
                    # Environment (8)
                    "climate": "Climat", "biodiversity": "Biodiversité",
                    "energy-transition": "Transition énergétique", "pollution": "Pollution",
                    "circular-economy": "Économie circulaire", "agriculture": "Agriculture",
                    "oceans": "Océans", "forests": "Forêts",
                    # Economy (8)
                    "macro": "Macro-économie", "finance": "Finance", "startups": "Startups",
                    "venture-capital": "VC", "labor-market": "Emploi", "inflation": "Inflation",
                    "trade": "Commerce", "taxation": "Fiscalité",
                    # Politics (5)
                    "elections": "Élections", "institutions": "Institutions",
                    "local-politics": "Politique locale", "activism": "Activisme",
                    "democracy": "Démocratie",
                    # Culture (4)
                    "philosophy": "Philosophie", "art": "Art", "cinema": "Cinéma",
                    "media-critics": "Critique des médias",
                    # Science (2)
                    "fundamental-research": "Recherche", "applied-science": "Sciences appliquées",
                    # International (1)
                    "geopolitics": "Géopolitique",
                }
                
                def _get_theme_label(raw_theme: str) -> str:
                    raw_theme = raw_theme.lower().strip()
                    return THEME_TRANSLATIONS.get(raw_theme, raw_theme.capitalize())
                
                def _get_subtopic_label(slug: str) -> str:
                    slug = slug.lower().strip()
                    return SUBTOPIC_TRANSLATIONS.get(slug, slug.capitalize())
                
                def _reason_to_label(reason: dict) -> str:
                    """Convert a reason dict to a human-readable French label."""
                    layer = reason['layer']
                    details = reason['details']
                    
                    if layer == 'core_v1':
                        if "Theme match" in details:
                            try:
                                theme_slug = details.split(': ')[1]
                                return f"Thème : {_get_theme_label(theme_slug)}"
                            except Exception:
                                return "Thème matché"
                        elif "confiance" in details.lower():
                            return "Source de confiance"
                        elif "personnalisée" in details.lower():
                            return "Ta source personnalisée"
                        elif "Recency" in details:
                            return "Récence"
                        else:
                            return details
                    elif layer == 'article_topic':
                        try:
                            # "Topic match: ai, crypto (précis)" -> "Sous-thèmes : IA, Crypto"
                            raw = details.split(': ')[1]
                            # Remove "(précis)" suffix if present
                            raw = raw.replace(" (précis)", "")
                            slugs = [t.strip() for t in raw.split(',')]
                            labels = [_get_subtopic_label(s) for s in slugs[:2]]
                            return f"Sous-thèmes : {', '.join(labels)}"
                        except Exception:
                            return "Sous-thèmes matchés"
                    elif layer == 'static_prefs':
                        if "Recent" in details:
                            return "Très récent"
                        elif "format" in details.lower():
                            return "Format préféré"
                        else:
                            return "Préférence"
                    elif layer == 'behavioral':
                        if "High interest" in details:
                            try:
                                theme_slug = details.split(': ')[1].split(' ')[0]
                                return f"Engagement élevé : {_get_theme_label(theme_slug)}"
                            except Exception:
                                return "Engagement élevé"
                        else:
                            return "Engagement"
                    elif layer == 'quality':
                        if "qualitative" in details.lower():
                            return "Source qualitative"
                        elif "Low" in details:
                            return "Fiabilité basse"
                        else:
                            return "Qualité source"
                    elif layer == 'visual':
                        return "Aperçu disponible"
                    else:
                        return details
                
                # Build breakdown list
                breakdown = []
                score_total = 0.0
                
                for reason in reasons_list:
                    pts = reason['score_contribution']
                    score_total += pts
                    breakdown.append(ScoreContribution(
                        label=_reason_to_label(reason),
                        points=pts,
                        is_positive=(pts >= 0)
                    ))
                
                # Sort by absolute contribution (highest first)
                breakdown.sort(key=lambda x: abs(x.points), reverse=True)
                
                # Determine top label (for the tag)
                # Prioritize granular topics over broad themes
                reasons_list.sort(key=lambda x: (x['layer'] == 'article_topic', x['score_contribution']), reverse=True)
                top = reasons_list[0]
                
                label = "Recommandé pour vous"  # Fallback
                
                if top['layer'] == 'core_v1':
                    if "Theme match" in top['details']:
                        try:
                            theme_slug = top['details'].split(': ')[1]
                            theme_fr = _get_theme_label(theme_slug)
                            label = f"Vos intérêts : {theme_fr}"
                        except Exception:
                            label = "Vos intérêts"
                    elif "confiance" in top['details'].lower():
                        label = "Source suivie"
                    elif "Recency" in top['details']:
                        label = "À la une"
                elif top['layer'] == 'article_topic':
                    try:
                        raw_topics = top['details'].split(': ')[1].replace(" (précis)", "")
                        topic_slugs = [t.strip() for t in raw_topics.split(',')]
                        topic_labels = [_get_subtopic_label(t) for t in topic_slugs[:2]]
                        label = f"Vos centres d'intérêt : {', '.join(topic_labels)}"
                    except Exception:
                        label = "Vos centres d'intérêt"
                elif top['layer'] == 'static_prefs':
                    if "Recent" in top['details']:
                        label = "Très récent"
                    elif "format" in top['details'] or "Pref" in top['details']:
                        label = "Format préféré"
                elif top['layer'] == 'behavioral':
                    if "High interest" in top['details']:
                        try:
                            theme_slug = top['details'].split(': ')[1].split(' ')[0]
                            theme_fr = _get_theme_label(theme_slug)
                            label = f"Sujet passionnant : {theme_fr}"
                        except Exception:
                            label = "Sujet passionnant"
                elif top['layer'] == 'quality':
                    if "qualitative" in top['details'].lower():
                        label = "Source de Confiance"
                    elif "Low" in top['details']:
                        label = "Source Controversée"
                elif top['layer'] == 'visual':
                    label = "Aperçu disponible"

                content.recommendation_reason = RecommendationReason(
                    label=label,
                    score_total=score_total,
                    breakdown=breakdown
                )
        
        # 6. Hydrate with User Status (is_saved, etc)
        content_ids = [c.id for c in result]
        if content_ids:
            # Fetch statuses for these contents
            stmt = select(UserContentStatus).where(
                UserContentStatus.user_id == user_id,
                UserContentStatus.content_id.in_(content_ids)
            )
            statuses = await self.session.scalars(stmt)
            status_map = {s.content_id: s for s in statuses}
            
            for content in result:
                st = status_map.get(content.id)
                # Attach temporary attributes for Pydantic serialization
                content.is_saved = st.is_saved if st else False
                content.is_hidden = st.is_hidden if st else False
                content.hidden_reason = st.hidden_reason if st else None
                content.status = st.status if st else ContentStatus.UNSEEN
        
        return result

    async def _get_candidates(self, user_id: UUID, limit_candidates: int, content_type: Optional[str] = None, mode: Optional[FeedFilterMode] = None, followed_source_ids: Set[UUID] = None, muted_sources: Set[UUID] = None, muted_themes: Set[str] = None, muted_topics: Set[str] = None) -> List[Content]:
        """Récupère les N contenus les plus récents que l'utilisateur n'a pas encore vus/consommés et qui ne sont pas masqués."""
        from sqlalchemy import or_, and_

        # Sanitize inputs to prevent SQL Tri-state logic issues with "NOT IN (NULL, ...)"
        # If a set contains None, "NOT IN" evaluates to NULL (unknown) for ALL rows, causing empty results.
        if muted_sources:
             muted_sources = {s for s in muted_sources if s is not None}
        
        if muted_themes:
             # Filter out None and empty strings
             muted_themes = {t for t in muted_themes if t}
        
        if muted_topics:
             # Filter out None and empty strings
             muted_topics = {t for t in muted_topics if t}

        # Candidates to EXCLUDE:
        # 1. is_hidden == True
        # OR
        # 2. is_saved == True (Triaged to watch later)
        # OR
        # 3. status IN (SEEN, CONSUMED)
        
        # Optimization: Use NOT EXISTS instead of NOT IN for exclusion
        # This is generally faster in Postgres for large status tables
        from sqlalchemy import exists
        
        exists_stmt = exists().where(
            UserContentStatus.content_id == Content.id,
            UserContentStatus.user_id == user_id,
            or_(
                UserContentStatus.is_hidden == True,
                UserContentStatus.is_saved == True,
                UserContentStatus.status.in_([ContentStatus.SEEN, ContentStatus.CONSUMED])
            )
        )
        
        query = (
            select(Content)
            .join(Content.source) # Join needed for all mode filters
            .options(selectinload(Content.source)) 
            .where(~exists_stmt)
        )

        # Base filter: Priority to Curated sources OR explicitly Followed sources
        query = query.where(
            or_(
                Source.is_curated == True,
                Source.id.in_(list(followed_source_ids)) if followed_source_ids else False
            )
        )
        
        # Apply Personalization Filters (Mutes)
        if muted_sources:
             query = query.where(Source.id.notin_(list(muted_sources)))
        
        if muted_themes:
             # SQL IN operator is case-sensitive, but we stored lowercase slugs. 
             # Ensure Source.theme is compared correctly (assuming themes are lowercase in DB or we use lower())
             query = query.where(~Source.theme.in_(list(muted_themes)))

        if muted_topics:
             # Filter based on Content.topics (Array overlap)
             # Postgres operator && (overlap). Negated with ~
             # Fix 500: Handle NULL Content.topics explicitly
             query = query.where(
                 or_(
                     Content.topics.is_(None),
                     ~Content.topics.overlap(list(muted_topics))
                 )
             )
        
        # Apply content_type filter if provided
        if content_type:
             query = query.where(Content.content_type == content_type)
        
        # Apply Mode Logic
        if mode:
            if mode == FeedFilterMode.INSPIRATION:
                # Mode "Sérénité" : Positive/Zen. Exclude Hard News themes.
                # Hard News = society_climate, geopolitics, economy (themes en DB via THEME_MAPPING)
                query = query.where(Source.theme.notin_(['society_climate', 'geopolitics', 'economy']))
                
                # Exclude content containing stressful keywords in title or description
                # (Case-insensitive regex match in Postgres)
                keywords_pattern = '|'.join(SERENE_FILTER_KEYWORDS)
                query = query.where(~Content.title.op('~*')(keywords_pattern))
                query = query.where(~Content.description.op('~*')(keywords_pattern))
            
            elif mode == FeedFilterMode.DEEP_DIVE:
                # Mode "Grand Format" : Contenus > 10min (videos, podcasts, OU articles longs)
                # Note: 45 videos ont duration_seconds=NULL en base. On les inclut par défaut.
                query = query.where(
                    or_(
                        # Videos et Podcasts: Durée inconnue (NULL) ou > 10 min
                        and_(
                            or_(Content.duration_seconds > 600, Content.duration_seconds == None),
                            Content.content_type.in_([ContentType.PODCAST, ContentType.YOUTUBE])
                        ),
                        # Articles longs (estimation basée sur description length comme proxy)
                        # TODO: Ajouter un vrai champ reading_time_minutes à Content
                        and_(
                            Content.content_type == ContentType.ARTICLE,
                            func.length(Content.description) > 2000  # ~10 min de lecture
                        )
                    )
                )

            elif mode == FeedFilterMode.BREAKING:
                 # Mode "Dernières news" : Feed Twitter-like avec les actualités chaudes
                 # Philosophie : Immédiateté et réactivité, comme un fil d'actu en temps réel
                 # - Fenêtre courte (12h) pour garantir la fraîcheur
                 # - Thèmes Hard News : actualités chaudes (society_climate, geopolitics, economy)
                 #   Note: themes en DB correspondent au THEME_MAPPING de import_sources.py
                 # - Tri par date de publication (les plus récents en premier)
                 limit_date = datetime.datetime.utcnow() - datetime.timedelta(hours=12)
                 hard_news_themes = ['society_climate', 'geopolitics', 'economy']
                 logger.info("breaking_filter_debug", 
                            limit_date=limit_date.isoformat(),
                            target_themes=hard_news_themes)
                 query = query.where(
                    and_(
                        Content.published_at >= limit_date,
                        Source.theme.in_(hard_news_themes)
                    )
                 )

            elif mode == FeedFilterMode.PERSPECTIVES:
                # Mode "Angle Mort" : Perspective swap
                user_bias_stance = await self._calculate_user_bias(user_id)
                target_bias = self._get_opposing_biases(user_bias_stance)
                
                query = query.where(Source.bias_stance.in_(target_bias))

        query = (
            query
            .order_by(Content.published_at.desc())
            .limit(limit_candidates)
        )
        
        candidates = await self.session.scalars(query)
        candidates_list = list(candidates.all())
        
        # Debug logging for mode filters
        if mode:
            logger.info("candidates_after_mode_filter", 
                       mode=mode.value, 
                       count=len(candidates_list),
                       sample_sources=[c.source.name if c.source else "N/A" for c in candidates_list[:5]])

        return candidates_list

    async def _calculate_user_bias(self, user_id: UUID) -> BiasStance:
        """Heuristic: Determine user's dominant bias based on followed sources."""
        # TODO: Refine with actual consumption history. For now, followed sources.
        result = await self.session.execute(
            select(Source.bias_stance)
            .join(UserSource)
            .where(UserSource.user_id == user_id)
        )
        biases = result.scalars().all()
        
        score = 0
        for b in biases:
            if b in [BiasStance.LEFT, BiasStance.CENTER_LEFT]:
                score -= 1
            elif b in [BiasStance.RIGHT, BiasStance.CENTER_RIGHT]:
                score += 1
        
        if score < 0:
            return BiasStance.LEFT # Represents "Left Leaning"
        elif score > 0:
            return BiasStance.RIGHT # Represents "Right Leaning"
        else:
            return BiasStance.CENTER # Balanced or None
            
    def _get_opposing_biases(self, user_stance: BiasStance) -> List[BiasStance]:
        """Return list of biases to show for perspective swap."""
        if user_stance == BiasStance.LEFT:
             # User is Left -> Show Right
             return [BiasStance.RIGHT, BiasStance.CENTER_RIGHT]
        elif user_stance == BiasStance.RIGHT:
             # User is Right -> Show Left
             return [BiasStance.LEFT, BiasStance.CENTER_LEFT]
        else:
             # User is Center/Neutral -> Show Extremes or Alternative
             return [BiasStance.ALTERNATIVE, BiasStance.SPECIALIZED, BiasStance.LEFT, BiasStance.RIGHT]

