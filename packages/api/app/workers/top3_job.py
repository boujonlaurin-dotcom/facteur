"""Worker pour le briefing quotidien (Top 3).

Story 4.4: Top 3 Briefing Quotidien
Ce job s'exécute tous les jours à 8h (heure de Paris).
"""
import asyncio
import datetime
from typing import List, Set, Tuple
from uuid import UUID

import feedparser
import structlog
from sqlalchemy import select, delete, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import selectinload

from app.database import async_session_maker
from app.models.content import Content
from app.models.daily_top3 import DailyTop3
from app.models.source import Source
from app.models.user import UserProfile
from app.services.briefing import ImportanceDetector, Top3Selector
from app.services.recommendation_service import RecommendationService
from app.services.recommendation.scoring_engine import ScoringContext

logger = structlog.get_logger()

# Timeout pour fetch RSS
RSS_TIMEOUT = 10


async def fetch_une_guids(session) -> Set[str]:
    """Récupère les GUIDs des articles actuellement "À la Une".
    
    1. Récupère les sources ayant `une_feed_url` défini.
    2. Fetch et parse ces feeds RSS en parallèle.
    3. Extrait les GUIDs des 5 premiers items de chaque feed.
    
    Returns:
        Set des GUIDs trouvés.
    """
    stmt = select(Source).where(Source.une_feed_url.is_not(None))
    result = await session.execute(stmt)
    sources = result.scalars().all()
    
    if not sources:
        logger.info("No sources with une_feed_url found")
        return set()
    
    une_guids: Set[str] = set()
    logger.info("Fetching Une feeds", count=len(sources))
    
    async def parse_feed(url: str) -> List[str]:
        try:
            # Note: feedparser est bloquant, idéalement à lancer dans un executor
            # Pour simplifier ici on l'appelle directement, le job est async
            loop = asyncio.get_event_loop()
            feed = await loop.run_in_executor(None, feedparser.parse, url)
            
            # Prendre les 5 premiers items
            return [
                entry.id if hasattr(entry, 'id') else entry.link 
                for entry in feed.entries[:5]
            ]
        except Exception as e:
            logger.error("Error parsing Une feed", url=url, error=str(e))
            return []

    # Lancer en parallèle
    tasks = [parse_feed(source.une_feed_url) for source in sources]
    results = await asyncio.gather(*tasks)
    
    for guids in results:
        une_guids.update(guids)
        
    logger.info("Une parsing complete", total_guids=len(une_guids))
    return une_guids


async def get_recent_contents(session, hours: int = 24) -> List[Content]:
    """Récupère les contenus publiés dans les dernières heures."""
    since = datetime.datetime.utcnow() - datetime.timedelta(hours=hours)
    stmt = (
        select(Content)
        .where(Content.published_at >= since)
        .options(selectinload(Content.source))  # Optimisation pour ImportanceDetector
    )
    result = await session.execute(stmt)
    return list(result.scalars().all())


async def generate_daily_top3_job(trigger_manual: bool = False):
    """Génère le Top 3 quotidien pour tous les utilisateurs éligibles."""
    logger.info("Starting Daily Top 3 generation job", trigger_manual=trigger_manual)
    
    start_time = datetime.datetime.utcnow()
    
    async with async_session_maker() as session:
        # 1. GLOBAL PHASE: Detection d'importance
        # ---------------------------------------
        importance_detector = ImportanceDetector()
        
        # A. Fetch "Une" GUIDs
        une_guids = await fetch_une_guids(session)
        
        # B. Fetch recent contents for trending detection
        recent_contents = await get_recent_contents(session, hours=24)
        
        # C. Detect Importance Flags
        une_ids = importance_detector.identify_une_contents(recent_contents, une_guids)
        trending_ids = importance_detector.detect_trending_clusters(recent_contents)
        
        # D. Pre-load Users
        # On cible les utilisateurs ayant complété l'onboarding
        stmt = select(UserProfile).where(UserProfile.onboarding_completed == True)
        result = await session.execute(stmt)
        user_profiles = result.scalars().all()
        
        logger.info(
            "Global analysis complete", 
            users_count=len(user_profiles),
            recent_contents_count=len(recent_contents),
            une_detected=len(une_ids),
            trending_detected=len(trending_ids)
        )

        # 2. USER PHASE: Selection & Persistence
        # --------------------------------------
        top3_selector = Top3Selector()
        rec_service = RecommendationService(session)
        
        generated_count = 0
        
        for profile in user_profiles:
            try:
                user_id = profile.user_id
                
                # Check si déjà généré aujourd'hui pour cet utilisateur
                # (Protection contre double exécution)
                today_start = start_time.replace(hour=0, minute=0, second=0, microsecond=0)
                exists_stmt = select(DailyTop3).where(
                    DailyTop3.user_id == user_id,
                    DailyTop3.generated_at >= today_start
                )
                if (await session.execute(exists_stmt)).first():
                    logger.debug("Briefing already generated for user", user_id=str(user_id))
                    continue

                # A. Fetch Candidates (using RecService internal logic)
                # On utilise _get_candidates qui applique déjà le filtrage de base
                # On ne filtre pas par mode spécifique, on veut une vue générale
                candidates = await rec_service._get_candidates(
                    user_id=user_id,
                    limit_candidates=200,  # Suffisant pour trouver 3 tops
                    followed_source_ids=await _get_followed_source_ids(session, user_id)
                )
                
                if not candidates:
                    logger.warning("No candidates found for user", user_id=str(user_id))
                    continue

                # B. Score Candidates (RecService logic reuse)
                scored_contents = []
                
                # Reconstruct ScoringContext manually as _get_candidates doesn't return it
                # TODO: Refactor RecommendationService to expose context creation?
                # For now, we do a simplified context creation here
                
                # Fetch user interests & prefs (should be cached ideally)
                context = await _create_scoring_context(session, profile)
                
                # PERTINENCE FIX: Pré-filtrer les candidats par thèmes d'intérêt
                # Garder les contenus dont le thème correspond aux intérêts utilisateur
                # OU qui proviennent de sources suivies (pour garantir le slot #3)
                user_themes = context.user_interests
                followed_sources = context.followed_source_ids
                
                filtered_candidates = [
                    c for c in candidates
                    if (c.source and c.source.theme in user_themes) or 
                       (c.source_id in followed_sources)
                ]
                
                logger.debug(
                    "Filtered candidates by interest themes",
                    user_id=str(user_id),
                    before=len(candidates),
                    after=len(filtered_candidates),
                    user_themes=list(user_themes)
                )
                
                # Fallback: si trop peu de candidats après filtrage, utiliser les originaux
                if len(filtered_candidates) < 10:
                    filtered_candidates = candidates
                    logger.debug("Fallback to all candidates (insufficient after filter)")
                
                for content in filtered_candidates:
                    try:
                        score = rec_service.scoring_engine.compute_score(content, context)
                        scored_contents.append((content, score))
                    except Exception as e:
                        logger.error("Scoring error", content_id=str(content.id), error=str(e))

                # C. Select Top 3
                top3_items = top3_selector.select_top3(
                    scored_contents=scored_contents,
                    user_followed_sources=context.followed_source_ids,
                    une_content_ids=une_ids,
                    trending_content_ids=trending_ids
                )
                
                # D. Persist with idempotency (ON CONFLICT DO NOTHING)
                # This prevents duplicates if the job runs multiple times
                for i, item in enumerate(top3_items):
                    stmt = insert(DailyTop3).values(
                        user_id=user_id,
                        content_id=item.content.id,
                        rank=i + 1,
                        top3_reason=item.top3_reason,
                        generated_at=start_time
                    ).on_conflict_do_nothing()
                    await session.execute(stmt)
                
                # Commit per user to ensure atomicity
                await session.commit()
                generated_count += 1
                
            except Exception as e:
                logger.error("Error generating briefing for user", user_id=str(profile.user_id), error=str(e))
                # Rollback this user's transaction and continue
                await session.rollback()
                continue

        
    duration = (datetime.datetime.utcnow() - start_time).total_seconds()
    logger.info(
        "Daily Top 3 job completed", 
        duration_seconds=duration,
        users_processed=generated_count
    )


# Helpers privés pour répliquer la logique de contexte de RecommendationService
# (Idéalement à refactoriser dans une méthode publique de RecService)

async def _get_followed_source_ids(session, user_id: UUID) -> Set[UUID]:
    from app.models.source import UserSource
    result = await session.execute(
        select(UserSource.source_id).where(UserSource.user_id == user_id)
    )
    return set(result.scalars().all())

async def _create_scoring_context(session, user_profile: UserProfile) -> ScoringContext:
    user_id = user_profile.user_id
    
    # Needs explicit loading of interests/prefs if not already loaded
    # But user_profiles list above might not have them loaded
    # Safer to reload or assume lazy loading if session is open (async require explicit load)
    
    # Reload profile with relations
    stmt = (
        select(UserProfile)
        .options(
            selectinload(UserProfile.interests),
            selectinload(UserProfile.preferences)
        )
        .where(UserProfile.user_id == user_id)
    )
    profile = (await session.execute(stmt)).scalar_one()

    followed_ids = await _get_followed_source_ids(session, user_id)
    
    user_interests = {i.interest_slug for i in profile.interests}
    user_interest_weights = {i.interest_slug: i.weight for i in profile.interests}
    user_prefs = {p.preference_key: p.preference_value for p in profile.preferences}
    
    return ScoringContext(
        user_profile=profile,
        user_interests=user_interests,
        user_interest_weights=user_interest_weights,
        followed_source_ids=followed_ids,
        user_prefs=user_prefs,
        now=datetime.datetime.utcnow()
    )
