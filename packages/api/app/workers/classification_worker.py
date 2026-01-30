"""Worker asynchrone pour la classification ML des contenus."""

import asyncio
from typing import List, Optional
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.config import get_settings
from app.database import Base
from app.models.classification_queue import ClassificationQueue
from app.models.content import Content
from app.services.classification_queue_service import ClassificationQueueService

settings = get_settings()


class ClassificationWorker:
    """Worker qui traite la file d'attente de classification ML.
    
    Ce worker fonctionne de manière asynchrone et peut être démarré
    comme tâche de fond dans l'application FastAPI.
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
        """Process one batch of pending items."""
        async with self.session_maker() as session:
            service = ClassificationQueueService(session)
            
            # Dequeue batch
            items = await service.dequeue_batch(batch_size=self.batch_size)
            
            if not items:
                return
            
            # Process each item
            for item in items:
                try:
                    await self._classify_item(session, item)
                except Exception as e:
                    # Mark as failed - will be retried
                    await service.mark_failed(item.id, str(e)[:500])
    
    async def _classify_item(self, session: AsyncSession, item: ClassificationQueue):
        """Classify a single content item using ML.
        
        This is a placeholder - in production, this would call the ML service.
        For now, we'll just mark items as completed with mock topics.
        """
        # TODO: Replace with actual ML classification
        # For now, simulate classification with mock topics
        mock_topics = self._extract_topics_from_content(item.content)
        
        service = ClassificationQueueService(session)
        await service.mark_completed(item.id, mock_topics)
    
    def _extract_topics_from_content(self, content: Optional[Content]) -> List[str]:
        """Extract topics from content (mock implementation).
        
        In production, this would use the ML classification service.
        """
        if not content:
            return []
        
        # Simple keyword-based extraction for demo
        title_lower = (content.title or "").lower()
        desc_lower = (content.description or "").lower()
        text = title_lower + " " + desc_lower
        
        topics = []
        
        # Simple keyword matching
        topic_keywords = {
            "tech": ["technology", "tech", "software", "ai", "artificial intelligence", "digital"],
            "science": ["science", "research", "study", "discovery", "physics", "biology"],
            "politics": ["politics", "election", "government", "president", "minister"],
            "economy": ["economy", "economic", "finance", "market", "stock", "business"],
            "climate": ["climate", "environment", "green", "carbon", "warming"],
            "health": ["health", "medical", "medicine", "hospital", "disease"],
            "culture": ["culture", "art", "music", "film", "book", "literature"],
            "sports": ["sport", "football", "basketball", "tennis", "olympic"],
        }
        
        for topic, keywords in topic_keywords.items():
            if any(keyword in text for keyword in keywords):
                topics.append(topic)
        
        # If no topics found, add a default one
        if not topics:
            topics = ["general"]
        
        return topics[:3]  # Max 3 topics


# Global worker instance (singleton)
_worker_instance: Optional[ClassificationWorker] = None


def get_worker() -> ClassificationWorker:
    """Get or create the global worker instance."""
    global _worker_instance
    if _worker_instance is None:
        _worker_instance = ClassificationWorker()
    return _worker_instance
