"""Service pour gérer la file de classification."""

from datetime import datetime
from typing import List, Optional
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.classification_queue import ClassificationQueue
from app.models.content import Content


class ClassificationQueueService:
    """Service pour gérer la file d'attente de classification ML."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def enqueue(self, content_id: UUID, priority: int = 0) -> bool:
        """Ajoute un contenu à la file de classification.
        
        Returns:
            True si l'élément a été créé, False s'il existait déjà.
        """
        # Vérifier si l'item existe déjà
        existing = await self.session.execute(
            select(ClassificationQueue).where(ClassificationQueue.content_id == content_id)
        )
        if existing.scalar_one_or_none() is not None:
            return False
        
        # Créer le nouvel item
        query = insert(ClassificationQueue).values(
            content_id=content_id,
            status='pending',
            priority=priority,
            retry_count=0,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        
        await self.session.execute(query)
        await self.session.commit()
        
        return True

    async def dequeue_batch(self, batch_size: int = 10) -> List[ClassificationQueue]:
        """Récupère le prochain lot d'articles en attente (opération atomique).
        
        Utilise SELECT FOR UPDATE SKIP LOCKED pour éviter les race conditions
        lors de l'exécution de plusieurs workers.
        """
        query = (
            select(ClassificationQueue)
            .where(ClassificationQueue.status == 'pending')
            .order_by(ClassificationQueue.priority.desc(),
                     ClassificationQueue.created_at)
            .limit(batch_size)
            .with_for_update(skip_locked=True)
        )
        
        result = await self.session.execute(query)
        items = result.scalars().all()
        
        # Marquer comme en cours de traitement
        for item in items:
            item.status = 'processing'
            item.updated_at = datetime.utcnow()
        
        await self.session.commit()
        return list(items)

    async def mark_completed(self, queue_id: UUID, topics: List[str]) -> None:
        """Marque un élément comme complété et met à jour les topics du contenu."""
        item = await self.session.get(ClassificationQueue, queue_id)
        if item:
            item.status = 'completed'
            item.processed_at = datetime.utcnow()
            item.updated_at = datetime.utcnow()
            
            # Mettre à jour le contenu avec les topics classifiés
            content = await self.session.get(Content, item.content_id)
            if content:
                content.topics = topics
            
            await self.session.commit()
    
    async def mark_completed_with_entities(
        self, 
        queue_id: UUID, 
        topics: List[str],
        entities: List[dict],
    ) -> None:
        """Marque un élément comme complété avec topics ET entités extraites.
        
        Args:
            queue_id: ID de l'élément dans la file
            topics: Liste des topics classifiés
            entities: Liste des entités extraites (format: [{"text": "...", "label": "..."}])
        """
        item = await self.session.get(ClassificationQueue, queue_id)
        if item:
            item.status = 'completed'
            item.processed_at = datetime.utcnow()
            item.updated_at = datetime.utcnow()
            
            # Mettre à jour le contenu avec topics et entités
            content = await self.session.get(Content, item.content_id)
            if content:
                content.topics = topics
                # Store entities as JSON strings in the array
                if entities:
                    import json
                    content.entities = [json.dumps(entity) for entity in entities]
            
            await self.session.commit()

    async def mark_completed_with_entities(
        self, 
        queue_id: UUID, 
        topics: List[str],
        entities: List[dict],
    ) -> None:
        """Marque un élément comme complété avec topics ET entités extraites.
        
        Args:
            queue_id: ID de l'élément dans la file
            topics: Liste des topics classifiés
            entities: Liste des entités extraites (format: [{"text": "...", "label": "..."}])
        """
        import structlog
        logger = structlog.get_logger()
        
        item = await self.session.get(ClassificationQueue, queue_id)
        if item:
            item.status = 'completed'
            item.processed_at = datetime.utcnow()
            item.updated_at = datetime.utcnow()
            
            # Mettre à jour le contenu avec topics et entités
            content = await self.session.get(Content, item.content_id)
            if content:
                content.topics = topics
                # Store entities as JSON strings in the array
                if entities:
                    import json
                    try:
                        content.entities = [json.dumps(entity) for entity in entities]
                    except Exception as e:
                        # Column might not exist yet - log but don't fail
                        logger.warning("entities_column_missing", error=str(e), content_id=str(content.id))
            
            await self.session.commit()

    async def mark_failed(self, queue_id: UUID, error: str) -> bool:
        """Marque un élément comme échoué avec logique de retry.
        
        Returns:
            True si l'élément sera retenté, False si échec permanent.
        """
        item = await self.session.get(ClassificationQueue, queue_id)
        if not item:
            return False
        
        item.retry_count += 1
        item.error_message = error
        item.updated_at = datetime.utcnow()
        
        if item.retry_count >= 3:
            item.status = 'failed'
            await self.session.commit()
            return False  # Échec permanent
        else:
            item.status = 'pending'  # Réessayer
            await self.session.commit()
            return True  # Sera retenté

    async def get_queue_stats(self) -> dict:
        """Récupère les statistiques de la file de classification."""
        query = (
            select(
                ClassificationQueue.status,
                func.count(ClassificationQueue.id).label('count')
            )
            .group_by(ClassificationQueue.status)
        )
        
        result = await self.session.execute(query)
        stats = {row.status: row.count for row in result.fetchall()}
        
        # S'assurer que tous les statuts sont présents
        all_statuses = ['pending', 'processing', 'completed', 'failed', 'cancelled']
        for status in all_statuses:
            if status not in stats:
                stats[status] = 0
        
        total = sum(stats.values())
        completed = stats.get('completed', 0)
        failed = stats.get('failed', 0)
        processed = completed + failed
        
        return {
            **stats,
            'total': total,
            'backlog': stats.get('pending', 0) + stats.get('processing', 0),
            'success_rate': round(completed / processed * 100, 2) if processed > 0 else 0.0
        }

    async def is_in_queue(self, content_id: UUID) -> bool:
        """Vérifie si un contenu est déjà dans la file."""
        result = await self.session.execute(
            select(ClassificationQueue).where(
                ClassificationQueue.content_id == content_id,
                ClassificationQueue.status.in_(['pending', 'processing'])
            )
        )
        return result.scalar_one_or_none() is not None

    async def get_pending_count(self) -> int:
        """Retourne le nombre d'articles en attente."""
        result = await self.session.execute(
            select(func.count(ClassificationQueue.id)).where(
                ClassificationQueue.status == 'pending'
            )
        )
        return result.scalar()

    async def requeue_failed(self, max_retries: int = 3) -> int:
        """Remet en file d'attente les articles échoués avec retry_count < max_retries.
        
        Returns:
            Nombre d'articles remis en file d'attente.
        """
        query = (
            select(ClassificationQueue)
            .where(
                ClassificationQueue.status == 'failed',
                ClassificationQueue.retry_count < max_retries
            )
        )
        
        result = await self.session.execute(query)
        failed_items = result.scalars().all()
        
        count = 0
        for item in failed_items:
            item.status = 'pending'
            item.updated_at = datetime.utcnow()
            count += 1
        
        if count > 0:
            await self.session.commit()
        
        return count
