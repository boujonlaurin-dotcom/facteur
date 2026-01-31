"""Worker asynchrone pour la classification ML des contenus."""

import asyncio
from typing import List, Optional, Tuple
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.config import get_settings
from app.database import Base
from app.models.classification_queue import ClassificationQueue
from app.models.content import Content
from app.services.classification_queue_service import ClassificationQueueService
from app.services.ml.classification_service import get_classification_service
from app.services.ml.ner_service import get_ner_service

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
        
        # Initialize ML services (lazy loading)
        self._classifier = None
        self._ner = None
    
    def _get_classifier(self):
        """Lazy load classification service."""
        if self._classifier is None:
            self._classifier = get_classification_service()
        return self._classifier
    
    def _get_ner(self):
        """Lazy load NER service."""
        if self._ner is None:
            self._ner = get_ner_service()
        return self._ner
    
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
        """Classify a single content item using ML (topics + NER).
        
        Extracts both topics (mDeBERTa) and entities (spaCy NER) from the content.
        """
        content = item.content
        if not content:
            service = ClassificationQueueService(session)
            await service.mark_completed_with_entities(item.id, [], [])
            return
        
        # Get topics and entities
        topics, entities = await self._extract_topics_and_entities(content)
        
        # Mark as completed with both topics and entities
        service = ClassificationQueueService(session)
        await service.mark_completed_with_entities(item.id, topics, entities)
    
    async def _extract_topics_and_entities(self, content: Content) -> Tuple[List[str], List[dict]]:
        """Extract both topics and entities from content.
        
        Returns:
            Tuple of (topics, entities) where:
            - topics: List of topic strings
            - entities: List of entity dicts [{"text": "...", "label": "..."}]
        """
        topics = []
        entities = []
        
        # 1. Topic classification (mDeBERTa)
        classifier = self._get_classifier()
        if classifier and classifier.is_ready():
            try:
                topics = await classifier.classify_async(
                    title=content.title or "",
                    description=content.description or "",
                )
            except Exception as e:
                import structlog
                logger = structlog.get_logger()
                logger.warning("classification_failed", error=str(e), content_id=str(content.id))
        
        # Fallback to source topics if classification fails
        if not topics and content.source:
            topics = content.source.granular_topics or []
        
        # 2. Entity extraction (spaCy NER)
        ner = self._get_ner()
        if ner and ner.is_ready():
            try:
                ner_entities = await ner.extract_entities(
                    title=content.title or "",
                    description=content.description or "",
                    max_entities=10,
                )
                entities = [e.to_dict() for e in ner_entities]
            except Exception as e:
                import structlog
                logger = structlog.get_logger()
                logger.warning("ner_extraction_failed", error=str(e), content_id=str(content.id))
        
        return topics, entities


# Global worker instance (singleton)
_worker_instance: Optional[ClassificationWorker] = None


def get_worker() -> ClassificationWorker:
    """Get or create the global worker instance."""
    global _worker_instance
    if _worker_instance is None:
        _worker_instance = ClassificationWorker()
    return _worker_instance
