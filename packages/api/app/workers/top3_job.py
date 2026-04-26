import asyncio
from datetime import datetime

import structlog
from sqlalchemy import select

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
        # Round 3 fix (docs/bugs/bug-infinite-load-requests.md — F1.3) :
        # Chaque user utilise SA PROPRE session courte. L'ancienne version
        # partageait une seule session pour tous les users du batch : une
        # erreur sur user N pouvait laisser la session en état invalid
        # (PendingRollbackError), et tous les users N+1 à N+M échouaient
        # en cascade sur cette même connexion empoisonnée. Pire, ça
        # contribuait à saturer le pool Supabase (connexions check-outées
        # sans rollback propre).
        # 1. Global context : session courte dédiée.
        async with async_session_maker() as ctx_session:
            try:
                briefing_service_ctx = BriefingService(ctx_session)
                logger.info("daily_top3_building_context")
                global_context = await briefing_service_ctx._build_global_context()

                une_ids = global_context.get("une_ids", set())
                trending_ids = global_context.get("trending_ids", set())

                logger.info(
                    "daily_top3_context_ready",
                    une_count=len(une_ids),
                    trending_count=len(trending_ids),
                )

                # 2. Get Users Eligible (même session courte — lecture seule)
                stmt = select(UserProfile.user_id).where(
                    UserProfile.onboarding_completed
                )
                result = await ctx_session.execute(stmt)
                user_ids = list(result.scalars().all())
            finally:
                # Libère la connexion Supavisor : sans ROLLBACK explicite, les
                # SELECTs ci-dessus laissent la session "idle in transaction"
                # côté pooler externe.
                try:
                    await ctx_session.rollback()
                except Exception:
                    logger.warning(
                        "daily_top3 ctx_session rollback failed", exc_info=True
                    )

        total_users = len(user_ids)
        logger.info("daily_top3_users_found", count=total_users)

        # 3. Process Users (une session courte PAR user)
        processed_count = 0
        errors_count = 0

        for user_id in user_ids:
            try:
                async with async_session_maker() as user_session:
                    try:
                        briefing_service = BriefingService(user_session)
                        await briefing_service.generate_briefing_for_user(
                            user_id=user_id, global_context=global_context
                        )
                    except Exception:
                        # Rollback explicite avant de fermer — évite de
                        # laisser la session en état invalide dans le pool.
                        try:
                            await user_session.rollback()
                        except Exception as rb_exc:
                            logger.debug(
                                "daily_top3_rollback_failed",
                                user_id=str(user_id),
                                error=str(rb_exc),
                            )
                        raise
                processed_count += 1

                # Petit sleep pour éviter de saturer CPU/DB si beaucoup d'users
                if processed_count % 50 == 0:
                    await asyncio.sleep(0.1)

            except Exception as e:
                errors_count += 1
                logger.error(
                    "daily_top3_user_failed", user_id=str(user_id), error=str(e)
                )

        duration = (datetime.utcnow() - start_time).total_seconds()
        logger.info(
            "daily_top3_job_completed",
            duration_seconds=duration,
            users_processed=processed_count,
            errors=errors_count,
            total=total_users,
        )

    except Exception as e:
        logger.critical("daily_top3_job_crashed", error=str(e))
        raise e
