"""Worker asynchrone pour la classification ML des contenus.

Story 4.2-US-3: mDeBERTa Worker Integration
"""

import asyncio
import time
from typing import List, Optional
from uuid import UUID

import structlog
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.config import get_settings
from app.models.classification_queue import ClassificationQueue
from app.models.content import Content
from app.services.classification_queue_service import ClassificationQueueService

settings = get_settings()
log = structlog.get_logger()


class ClassificationWorker:
    """Worker qui traite la file d'attente de classification ML avec mDeBERTa.
    
    Story 4.2-US-3: Intègre le service de classification ML mDeBERTa pour
    classifier automatiquement les articles avec fallback sur source.granular_topics.
    """
    
    def __init__(self, batch_size: int = 10, interval: int = 60):
        """Initialize the worker.
        
        Args:
            batch_size: Nombre d'articles à traiter par lot
            interval: Intervalle en secondes entre chaque vérification
        """
        self.batch_size = batch_size
        self.interval = interval
        self.running = False
        self._task: Optional[asyncio.Task] = None
        
        # Metrics tracking
        self.metrics = {
            "processed": 0,
            "failed": 0,
            "fallback": 0,
            "avg_time_ms": 0.0,
        }
        
        # Create engine for worker (separate from main app)
        self.engine = create_async_engine(
            settings.database_url,
            echo=False,
            pool_pre_ping=False,
            poolclass=NullPool,
            connect_args={
                "prepare_threshold": None,
            },
        )
        
        self.session_maker = async_sessionmaker(
            self.engine,
            class_=AsyncSession,
            expire_on_commit=False,
            autocommit=False,
            autoflush=False,
        )
    
    async def start(self):
        """Start the worker in the background."""
        if self.running:
            return
        
        self.running = True
        self._task = asyncio.create_task(self._run_loop())
    
    async def stop(self):
        """Stop the worker gracefully."""
        self.running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None
        
        await self.engine.dispose()
    
    async def _run_loop(self):
        """Main processing loop."""
        while self.running:
            try:
                await self._process_batch()
            except Exception as e:
                import structlog
                logger = structlog.get_logger()
                logger.error("classification_worker_error", error=str(e))
            
            # Wait before next batch
            await asyncio.sleep(self.interval)
    
    async def _process_batch(self):
        """Process one batch of pending items with ML classification."""
        async with self.session_maker() as session:
            service = ClassificationQueueService(session)
            
            # Dequeue batch
            items = await service.dequeue_batch(batch_size=self.batch_size)
            
            if not items:
                return
            
            log.info("worker.processing_batch", count=len(items))
            
            # Process each item
            for item in items:
                try:
                    await self._classify_item(session, item)
                    self.metrics["processed"] += 1
                except Exception as e:
                    # Mark as failed - will be retried
                    log.error(
                        "worker.item_failed",
                        content_id=str(item.content_id),
                        error=str(e),
                    )
                    await service.mark_failed(item.id, str(e)[:500])
                    self.metrics["failed"] += 1
    
    async def _classify_item(self, session: AsyncSession, item: ClassificationQueue):
        """Classify a single content item using mDeBERTa with fallback.
        
        Story 4.2-US-3: Uses ML classification with fallback to source.granular_topics.
        
        Args:
            session: SQLAlchemy async session
            item: ClassificationQueue item to process
        """
        from app.services.ml import get_classification_service
        
        start_time = time.time()
        
        # Get content and source
        content = item.content
        if not content:
            raise ValueError(f"Content not found for queue item {item.id}")
        
        # Force load source relationship if not loaded
        if not content.source:
            from sqlalchemy.orm import selectinload
            from sqlalchemy import select
            
            stmt = select(Content).options(selectinload(Content.source)).where(Content.id == content.id)
            result = await session.execute(stmt)
            content = result.scalar_one()
        
        # Get classifier service
        classifier = get_classification_service()
        topics: List[str] = []
        used_fallback = False
        
        # Try ML classification if available
        if classifier.is_ready():
            try:
                topics = await classifier.classify_async(
                    title=content.title or "",
                    description=content.description or "",
                    top_k=3,
                    threshold=0.3,
                )
                log.debug(
                    "worker.ml_classified",
                    content_id=str(content.id),
                    topics=topics,
                )
            except Exception as e:
                log.warning(
                    "worker.ml_classification_failed",
                    content_id=str(content.id),
                    error=str(e),
                )
        
        # Fallback to source.granular_topics if ML fails or returns empty
        if not topics and content.source and content.source.granular_topics:
            topics = content.source.granular_topics[:3]
            used_fallback = True
            self.metrics["fallback"] += 1
            log.debug(
                "worker.using_fallback",
                content_id=str(content.id),
                source_name=content.source.name,
                topics=topics,
            )
        
        # Save topics to content
        content.topics = topics if topics else None
        await session.commit()
        
        # Calculate processing time
        elapsed_ms = (time.time() - start_time) * 1000
        self._update_metrics(elapsed_ms)
        
        log.info(
            "worker.item_processed",
            content_id=str(content.id),
            topics=topics,
            used_fallback=used_fallback,
            elapsed_ms=round(elapsed_ms, 2),
        )
        
        # Mark queue item as completed
        service = ClassificationQueueService(session)
        await service.mark_completed(item.id, topics)
    
    def _update_metrics(self, elapsed_ms: float):
        """Update running average processing time."""
        n = self.metrics["processed"]
        if n > 0:
            self.metrics["avg_time_ms"] = (
                (self.metrics["avg_time_ms"] * (n - 1)) + elapsed_ms
            ) / n
        else:
            self.metrics["avg_time_ms"] = elapsed_ms
    
    def get_metrics(self) -> dict:
        """Get worker metrics for monitoring."""
        total = self.metrics["processed"] + self.metrics["failed"]
        fallback_rate = (
            self.metrics["fallback"] / self.metrics["processed"] * 100
            if self.metrics["processed"] > 0
            else 0
        )
        
        return {
            "processed": self.metrics["processed"],
            "failed": self.metrics["failed"],
            "fallback": self.metrics["fallback"],
            "fallback_rate_percent": round(fallback_rate, 2),
            "avg_processing_time_ms": round(self.metrics["avg_time_ms"], 2),
            "total_attempted": total,
        }


# Global worker instance (singleton)
_worker_instance: Optional[ClassificationWorker] = None


def get_worker() -> ClassificationWorker:
    """Get or create the global worker instance."""
    global _worker_instance
    if _worker_instance is None:
        _worker_instance = ClassificationWorker()
    return _worker_instance
