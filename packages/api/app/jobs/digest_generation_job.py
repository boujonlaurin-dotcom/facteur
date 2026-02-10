"""Jobs pour la génération quotidienne des digests.

Ce module contient les tâches de génération batch des digests pour tous
les utilisateurs actifs. Le job est conçu pour être exécuté via un
scheduler (APScheduler, Celery Beat, etc.) une fois par jour.

Usage:
    # Via CLI ou script
    from app.jobs.digest_generation_job import run_digest_generation
    await run_digest_generation()

    # Via scheduler
    from apscheduler.schedulers.asyncio import AsyncIOScheduler
    scheduler.add_job(run_digest_generation, 'cron', hour=8, minute=0)
"""

import asyncio
import datetime
from typing import List, Optional, Dict, Any
from uuid import UUID

import structlog
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert

from app.database import async_session_maker
from app.models.user import UserProfile
from app.models.daily_digest import DailyDigest
from app.services.digest_selector import DigestSelector, DigestItem, DiversityConstraints

logger = structlog.get_logger()


class DigestGenerationJob:
    """Job de génération quotidienne des digests.
    
    Cette classe gère la génération batch des digests pour tous les
    utilisateurs actifs. Elle est conçue pour être exécutée une fois
    par jour, typiquement à 8h du matin (heure de Paris).
    
    Attributes:
        batch_size: Nombre d'utilisateurs traités par batch (défaut: 100)
        concurrency_limit: Nombre de digests générés en parallèle (défaut: 10)
    """
    
    def __init__(
        self,
        batch_size: int = 100,
        concurrency_limit: int = 10,
        hours_lookback: int = 48
    ):
        self.batch_size = batch_size
        self.concurrency_limit = concurrency_limit
        self.hours_lookback = hours_lookback
        self.stats = {
            "total_users": 0,
            "processed": 0,
            "success": 0,
            "failed": 0,
            "skipped": 0
        }
    
    async def run(self, session: AsyncSession, target_date: Optional[datetime.date] = None) -> Dict[str, Any]:
        """Exécute le job de génération pour tous les utilisateurs.
        
        Args:
            session: Session SQLAlchemy async
            target_date: Date du digest (défaut: aujourd'hui)
            
        Returns:
            Statistiques d'exécution
        """
        if target_date is None:
            target_date = datetime.date.today()
        
        logger.info(
            "digest_generation_job_started",
            target_date=str(target_date),
            batch_size=self.batch_size,
            concurrency_limit=self.concurrency_limit
        )
        
        start_time = datetime.datetime.utcnow()
        
        try:
            # 1. Récupérer tous les utilisateurs avec un profil
            user_ids = await self._get_active_users(session)
            self.stats["total_users"] = len(user_ids)
            
            logger.info(
                "digest_generation_users_loaded",
                count=len(user_ids),
                target_date=str(target_date)
            )
            
            # 2. Traiter par batches pour limiter la charge mémoire
            for i in range(0, len(user_ids), self.batch_size):
                batch = user_ids[i:i + self.batch_size]
                await self._process_batch(session, batch, target_date)
                
                # Commit après chaque batch
                await session.commit()
                
                logger.debug(
                    "digest_generation_batch_complete",
                    batch_start=i,
                    batch_size=len(batch),
                    processed=self.stats["processed"]
                )
            
            # 3. Finaliser
            duration = (datetime.datetime.utcnow() - start_time).total_seconds()
            
            logger.info(
                "digest_generation_job_completed",
                target_date=str(target_date),
                duration_seconds=duration,
                **self.stats
            )
            
            return {
                "success": True,
                "target_date": str(target_date),
                "duration_seconds": duration,
                "stats": self.stats.copy()
            }
            
        except Exception as e:
            logger.error(
                "digest_generation_job_failed",
                target_date=str(target_date),
                error=str(e)
            )
            raise
    
    async def _get_active_users(self, session: AsyncSession) -> List[UUID]:
        """Récupère la liste des utilisateurs actifs (avec profil).
        
        Pour l'instant, tous les utilisateurs avec un profil sont considérés
        comme actifs. Dans le futur, on pourrait ajouter une logique de
        "dernière connexion" ou "utilisateur actif".
        """
        stmt = select(UserProfile.user_id).order_by(UserProfile.user_id)
        result = await session.execute(stmt)
        return list(result.scalars().all())
    
    async def _process_batch(
        self,
        session: AsyncSession,
        user_ids: List[UUID],
        target_date: datetime.date
    ) -> None:
        """Traite un batch d'utilisateurs avec limitation de concurrence.
        
        Utilise un semaphore pour limiter le nombre de digests générés
        simultanément et éviter de surcharger la base de données.
        """
        semaphore = asyncio.Semaphore(self.concurrency_limit)
        
        async def process_with_limit(user_id: UUID) -> None:
            async with semaphore:
                await self._generate_digest_for_user(session, user_id, target_date)
        
        # Créer les tâches
        tasks = [process_with_limit(uid) for uid in user_ids]
        
        # Exécuter toutes les tâches du batch
        await asyncio.gather(*tasks, return_exceptions=True)
    
    async def _generate_digest_for_user(
        self,
        session: AsyncSession,
        user_id: UUID,
        target_date: datetime.date
    ) -> None:
        """Génère le digest pour un utilisateur spécifique.
        
        Args:
            session: Session SQLAlchemy
            user_id: ID de l'utilisateur
            target_date: Date du digest
        """
        self.stats["processed"] += 1
        
        try:
            # Vérifier si un digest existe déjà pour cette date
            existing = await session.scalar(
                select(DailyDigest).where(
                    DailyDigest.user_id == user_id,
                    DailyDigest.target_date == target_date
                )
            )
            
            if existing:
                logger.debug(
                    "digest_generation_skipped_exists",
                    user_id=str(user_id),
                    target_date=str(target_date)
                )
                self.stats["skipped"] += 1
                return
            
            # Sélectionner les articles via DigestSelector
            selector = DigestSelector(session)
            digest_items = await selector.select_for_user(
                user_id=user_id,
                limit=DiversityConstraints.TARGET_DIGEST_SIZE,
                hours_lookback=self.hours_lookback
            )
            
            if not digest_items:
                logger.warning(
                    "digest_generation_empty",
                    user_id=str(user_id),
                    target_date=str(target_date)
                )
                self.stats["failed"] += 1
                return
            
            # Construire les items JSONB
            items = []
            for item in digest_items:
                items.append({
                    "content_id": str(item.content.id),
                    "rank": item.rank,
                    "reason": item.reason,
                    "score": item.score,
                    "source_id": str(item.content.source_id) if item.content.source_id else None,
                    "title": item.content.title,
                    "published_at": item.content.published_at.isoformat() if item.content.published_at else None
                })
            
            # Insérer le digest
            digest = DailyDigest(
                user_id=user_id,
                target_date=target_date,
                items=items,
                generated_at=datetime.datetime.utcnow()
            )
            
            session.add(digest)
            
            logger.debug(
                "digest_generation_success",
                user_id=str(user_id),
                target_date=str(target_date),
                article_count=len(items)
            )
            
            self.stats["success"] += 1
            
        except Exception as e:
            logger.error(
                "digest_generation_user_failed",
                user_id=str(user_id),
                target_date=str(target_date),
                error=str(e)
            )
            self.stats["failed"] += 1


# Fonction principale pour l'export

async def run_digest_generation(
    target_date: Optional[datetime.date] = None,
    batch_size: int = 100,
    concurrency_limit: int = 10
) -> Dict[str, Any]:
    """Fonction principale pour exécuter la génération des digests.
    
    Cette fonction est le point d'entrée pour le job de génération.
    Elle peut être appelée:
    - Via un script CLI
    - Via un scheduler (APScheduler, Celery Beat)
    - Directement depuis le code
    
    Args:
        target_date: Date du digest (défaut: aujourd'hui)
        batch_size: Nombre d'utilisateurs par batch (défaut: 100)
        concurrency_limit: Limite de concurrence (défaut: 10)
        
    Returns:
        Statistiques d'exécution
        
    Example:
        >>> result = await run_digest_generation()
        >>> print(f"Generated {result['stats']['success']} digests")
        
        >>> # Pour une date spécifique
        >>> from datetime import date
        >>> result = await run_digest_generation(target_date=date(2024, 1, 15))
    """
    job = DigestGenerationJob(
        batch_size=batch_size,
        concurrency_limit=concurrency_limit
    )
    
    # Obtenir une session depuis le contexte
    async with async_session_maker() as session:
        try:
            result = await job.run(session, target_date)
            await session.commit()
            return result
        except Exception as e:
            await session.rollback()
            raise


# Fonction pour génération manuelle d'un seul utilisateur

async def generate_digest_for_user(
    user_id: UUID,
    target_date: Optional[datetime.date] = None,
    force: bool = False
) -> Optional[DailyDigest]:
    """Génère le digest pour un utilisateur spécifique (mode on-demand).
    
    Cette fonction permet de générer un digest pour un utilisateur
    spécifique, par exemple pour du testing ou pour du lazy-loading.
    
    Args:
        user_id: ID de l'utilisateur
        target_date: Date du digest (défaut: aujourd'hui)
        force: Si True, régénère même si un digest existe (défaut: False)
        
    Returns:
        Le DailyDigest créé, ou None si erreur
        
    Example:
        >>> from uuid import UUID
        >>> digest = await generate_digest_for_user(
        ...     user_id=UUID("..."),
        ...     force=True
        ... )
    """
    if target_date is None:
        target_date = datetime.date.today()
    
    async with async_session_maker() as session:
        try:
            # Vérifier l'existant
            if not force:
                existing = await session.scalar(
                    select(DailyDigest).where(
                        DailyDigest.user_id == user_id,
                        DailyDigest.target_date == target_date
                    )
                )
                if existing:
                    logger.info(
                        "digest_on_demand_skipped_exists",
                        user_id=str(user_id),
                        target_date=str(target_date)
                    )
                    return existing
            
            # Générer
            selector = DigestSelector(session)
            digest_items = await selector.select_for_user(
                user_id=user_id,
                limit=DiversityConstraints.TARGET_DIGEST_SIZE,
                hours_lookback=48
            )
            
            if not digest_items:
                logger.warning(
                    "digest_on_demand_empty",
                    user_id=str(user_id),
                    target_date=str(target_date)
                )
                return None
            
            # Construire les items
            items = []
            for item in digest_items:
                items.append({
                    "content_id": str(item.content.id),
                    "rank": item.rank,
                    "reason": item.reason,
                    "score": item.score,
                    "source_id": str(item.content.source_id) if item.content.source_id else None,
                    "title": item.content.title,
                    "published_at": item.content.published_at.isoformat() if item.content.published_at else None
                })
            
            # Supprimer l'ancien si force=True
            if force:
                await session.execute(
                    select(DailyDigest).where(
                        DailyDigest.user_id == user_id,
                        DailyDigest.target_date == target_date
                    )
                )
            
            # Créer le nouveau digest
            digest = DailyDigest(
                user_id=user_id,
                target_date=target_date,
                items=items,
                generated_at=datetime.datetime.utcnow()
            )
            
            session.add(digest)
            await session.commit()
            
            logger.info(
                "digest_on_demand_success",
                user_id=str(user_id),
                target_date=str(target_date),
                article_count=len(items)
            )
            
            return digest
            
        except Exception as e:
            await session.rollback()
            logger.error(
                "digest_on_demand_failed",
                user_id=str(user_id),
                target_date=str(target_date),
                error=str(e)
            )
            return None
