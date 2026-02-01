
import structlog
import asyncio
from typing import List, Set, Tuple
from sqlalchemy import select
from datetime import datetime

from app.database import async_session_maker
from app.models.user import UserProfile
from app.services.briefing_service import BriefingService

logger = structlog.get_logger()

async def generate_daily_top3_job(trigger_manual: bool = False):
    """Génère le Top 3 (Briefing) quotidien pour tous les utilisateurs.
    
    Refactorisé pour utiliser BriefingService.
    Ce job agit maintenant comme un 'Cache Warmer' pour préparer les données
    avant l'arrivée des utilisateurs.
    """
    logger.info("daily_top3_job_started", manual=trigger_manual)
    start_time = datetime.utcnow()
    
    try:
        async with async_session_maker() as session:
            # 1. Prepare Global Context (Une, Trending)
            briefing_service = BriefingService(session)
            
            logger.info("daily_top3_building_context")
            # On pré-calcule le contexte global une seule fois pour tout le batch
            global_context = await briefing_service._build_global_context()
            
            une_ids = global_context.get('une_ids', set())
            trending_ids = global_context.get('trending_ids', set())
            
            logger.info(
                "daily_top3_context_ready", 
                une_count=len(une_ids), 
                trending_count=len(trending_ids)
            )
            
            # 2. Get Users Eligible
            # On prend les utilisateurs ayant complété l'onboarding
            stmt = select(UserProfile.user_id).where(UserProfile.onboarding_completed == True)
            result = await session.execute(stmt)
            user_ids = result.scalars().all()
            
            total_users = len(user_ids)
            logger.info("daily_top3_users_found", count=total_users)
            
            # 3. Process Users (Batch)
            processed_count = 0
            errors_count = 0
            
            for user_id in user_ids:
                try:
                    # On appelle la génération explicite
                    # Note: generate_briefing_for_user gère l'idempotence (ON CONFLICT DO NOTHING)
                    # mais pour être plus propre on pourrait checker l'existence avant.
                    # BriefingService.get_or_create fait le check, mais ici on veut forcer/assurer la génération.
                    # On va utiliser generate_briefing_for_user directement avec le contexte pré-calculé.
                    
                    await briefing_service.generate_briefing_for_user(
                        user_id=user_id, 
                        global_context=global_context
                    )
                    processed_count += 1
                    
                    # Petit sleep pour éviter de saturer CPU/DB si beaucoup d'users
                    if processed_count % 50 == 0:
                        await asyncio.sleep(0.1)
                        
                except Exception as e:
                    errors_count += 1
                    logger.error(
                        "daily_top3_user_failed", 
                        user_id=str(user_id), 
                        error=str(e)
                    )
            
            duration = (datetime.utcnow() - start_time).total_seconds()
            logger.info(
                "daily_top3_job_completed", 
                duration_seconds=duration,
                users_processed=processed_count,
                errors=errors_count,
                total=total_users
            )
            
    except Exception as e:
        logger.critical("daily_top3_job_crashed", error=str(e))
        raise e
