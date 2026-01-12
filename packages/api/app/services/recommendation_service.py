import datetime
from typing import List, Optional, Set
from uuid import UUID

import structlog
from sqlalchemy import select, desc, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.source import Source, UserSource
from app.models.user import UserInterest, UserProfile
from app.models.enums import ContentStatus, FeedFilterMode, ContentType, BiasStance

logger = structlog.get_logger()

from app.services.recommendation.scoring_engine import ScoringEngine, ScoringContext
from app.services.recommendation.layers import CoreLayer, StaticPreferenceLayer, BehavioralLayer, QualityLayer
from app.schemas.content import RecommendationReason

class RecommendationService:
    def __init__(self, session: AsyncSession):
        self.session = session
        # Initialisation du moteur avec les couches configurées
        # L'ordre n'affecte pas le score (somme), mais affecte les logs/debugging
        self.scoring_engine = ScoringEngine([
            CoreLayer(),
            StaticPreferenceLayer(),
            BehavioralLayer(),
            QualityLayer()
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
        # 1. Fetch user profile with interests, followed sources AND preferences
        user_profile = await self.session.scalar(
            select(UserProfile)
            .options(
                selectinload(UserProfile.interests),
                selectinload(UserProfile.preferences)
            )
            .where(UserProfile.user_id == user_id)
        )
        
        followed_sources_result = await self.session.scalars(
            select(UserSource.source_id).where(UserSource.user_id == user_id)
        )
        followed_source_ids = set(followed_sources_result.all())
        
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
        # 500 is heuristic to ensure we have enough diversity after scoring, 
        # but small enough to sort in memory quickly.
        candidates = await self._get_candidates(
            user_id, 
            limit_candidates=500,
            content_type=content_type,
            mode=mode
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
            now=now
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
                # Simple Synthesis Strategy: Take the highest impactful factor
                # Sort by score contribution desc
                reasons_list.sort(key=lambda x: x['score_contribution'], reverse=True)
                top = reasons_list[0]
                
                label = "Recommandé pour vous" # Fallback
                
                # Mapping des thèmes Anglais -> Français
                THEME_TRANSLATIONS = {
                    "tech": "Tech",
                    "geopolitics": "Géopolitique",
                    "economy": "Économie",
                    "society_climate": "Société & Climat",
                    "culture_ideas": "Culture & Idées"
                }
                
                def _get_theme_label(raw_theme: str) -> str:
                    # Clean and translate
                    raw_theme = raw_theme.lower().strip()
                    return THEME_TRANSLATIONS.get(raw_theme, raw_theme.capitalize())

                if top['layer'] == 'core_v1':
                    if "Theme match" in top['details']:
                        # Extract theme name if possible or just use generic
                        try:
                            # Usually format "Theme match: theme_slug"
                            theme_slug = top['details'].split(': ')[1]
                            theme_fr = _get_theme_label(theme_slug)
                            label = f"Vos intérêts : {theme_fr}"
                        except Exception:
                            label = "Vos intérêts"
                    elif "Followed source" in top['details']:
                        label = "Source suivie"
                    elif "Recency" in top['details']:
                        label = "À la une"
                elif top['layer'] == 'static_prefs':
                    if "Recent" in top['details']:
                        label = "Très récent"
                    elif "format" in top['details'] or "Pref" in top['details']:
                        label = "Format préféré"
                elif top['layer'] == 'behavioral':
                    if "High interest" in top['details']:
                         # "High interest: theme (x1.2)"
                        try:
                            theme_slug = top['details'].split(': ')[1].split(' ')[0]
                            theme_fr = _get_theme_label(theme_slug)
                            label = f"Sujet passionnant : {theme_fr}"
                        except Exception:
                            label = "Sujet passionnant"
                elif top['layer'] == 'quality':
                    if "High reliability" in top['details']:
                        label = "Source de Confiance"
                    elif "Low reliability" in top['details']:
                        label = "Source Controversée"

                content.recommendation_reason = RecommendationReason(
                    label=label,
                    confidence=0.8 # Placeholder for now
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

    async def _get_candidates(self, user_id: UUID, limit_candidates: int, content_type: Optional[str] = None, mode: Optional[FeedFilterMode] = None) -> List[Content]:
        """Récupère les N contenus les plus récents que l'utilisateur n'a pas encore vus/consommés et qui ne sont pas masqués."""
        from sqlalchemy import or_, and_

        # Candidates to EXCLUDE:
        # 1. is_hidden == True
        # OR
        # 2. is_saved == True (Triaged to watch later)
        # OR
        # 3. status IN (SEEN, CONSUMED)
        
        exclude_query = select(UserContentStatus.content_id).where(
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
            .where(Content.id.notin_(exclude_query))
        )
        
        # Apply content_type filter if provided
        if content_type:
             query = query.where(Content.content_type == content_type)
        
        # Apply Mode Logic
        if mode:
            if mode == FeedFilterMode.INSPIRATION:
                # Mode "Sérénité" : Positive/Zen. Exclude Hard News themes.
                query = query.where(Source.theme.notin_(['politics', 'geopolitics', 'economy']))
            
            elif mode == FeedFilterMode.DEEP_DIVE:
                # Mode "Grand Format" : Strictly immersive media (Video/Podcast > 10m). Exclude Articles.
                query = query.where(
                    and_(
                        Content.duration_seconds > 600,
                        Content.content_type.in_([ContentType.PODCAST, ContentType.YOUTUBE])
                    )
                )

            elif mode == FeedFilterMode.BREAKING:
                 # Mode "L'Actualité" : Fresh news (< 24h) from Hard News themes.
                 limit_date = datetime.datetime.utcnow() - datetime.timedelta(hours=24)
                 query = query.where(
                    and_(
                        Content.published_at >= limit_date,
                        Source.theme.in_(['politics', 'geopolitics', 'economy'])
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

        # Post-Processing Heuristics for L'Actualité (Refining News vs Dossier)
        if mode == FeedFilterMode.BREAKING:
            refined_list = []
            # Keywords that boost "Hot News" intent
            NEWS_BOOST = ["direct", "live", "flash", "réaction", "alerte", "gouvernement", "démission", "attentat", "crise"]
            # Keywords that suggest "Long-form / Retrospective" (to penalize if 24h old but not 'news')
            ANALYSIS_PENALTY = ["dossier", "histoire", "pourquoi", "comment", "guide", "top", "portrait", "récit"]
            
            for content in candidates_list:
                title_lower = content.title.lower()
                
                # Simple score: boost if news keywords present, penalty if analysis keywords present
                news_score = 0
                if any(k in title_lower for k in NEWS_BOOST): news_score += 2
                if any(k in title_lower for k in ANALYSIS_PENALTY): news_score -= 2
                
                # If it's a "Dossier" published very recently, it might still show up if news_score >= 0
                # but we prefer titles that don't look like long-form analysis for "L'Actualité"
                if news_score >= -1:
                    refined_list.append(content)
            
            return refined_list

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

