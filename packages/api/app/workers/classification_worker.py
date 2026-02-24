"""Worker asynchrone pour la classification ML des contenus."""

import asyncio
import contextlib
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.config import get_settings
from app.models.classification_queue import ClassificationQueue
from app.models.content import Content
from app.models.source import Source
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
        self._task: asyncio.Task | None = None

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

        await self._recover_stuck_items()

        self.running = True
        self._task = asyncio.create_task(self._run_loop())

    async def _recover_stuck_items(self):
        """Reset items stuck in 'processing' state from previous crash/restart."""
        import structlog
        from sqlalchemy import update

        logger = structlog.get_logger()

        try:
            async with self.session_maker() as session:
                result = await session.execute(
                    update(ClassificationQueue)
                    .where(ClassificationQueue.status == "processing")
                    .values(status="pending", updated_at=datetime.utcnow())
                )
                count = result.rowcount
                await session.commit()

                if count > 0:
                    logger.info(
                        "classification_worker.recovered_stuck_items", count=count
                    )
        except Exception as e:
            logger.error("classification_worker.recovery_failed", error=str(e))

    async def stop(self):
        """Stop the worker gracefully."""
        self.running = False
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
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

            import structlog

            logger = structlog.get_logger()
            logger.info("classification_worker.processing_batch", count=len(items))

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
        Uses explicit async loads to avoid lazy-loading MissingGreenlet errors.
        """
        # Explicit async load (item.content would trigger sync lazy-load → MissingGreenlet)
        content = await session.get(Content, item.content_id)
        if not content:
            service = ClassificationQueueService(session)
            await service.mark_completed_with_entities(item.id, [], [])
            return

        # Pre-load source for fallback topics (same lazy-loading issue)
        source = (
            await session.get(Source, content.source_id) if content.source_id else None
        )

        # Get topics and entities
        topics, entities = await self._extract_topics_and_entities(content, source)

        # Mark as completed with both topics and entities
        service = ClassificationQueueService(session)
        await service.mark_completed_with_entities(item.id, topics, entities)

    async def _extract_topics_and_entities(
        self, content: Content, source=None
    ) -> tuple[list[str], list[dict]]:
        """Extract both topics and entities from content.

        Args:
            content: The content to classify
            source: Pre-loaded source (to avoid async lazy-loading)

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
                logger.warning(
                    "classification_failed", error=str(e), content_id=str(content.id)
                )

        # Fallback to source topics if classification fails
        if not topics and source:
            topics = source.granular_topics or []

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
                logger.warning(
                    "ner_extraction_failed", error=str(e), content_id=str(content.id)
                )

        return topics, entities


# Global worker instance (singleton)
_worker_instance: ClassificationWorker | None = None


def get_worker() -> ClassificationWorker:
    """Get or create the global worker instance."""
    global _worker_instance
    if _worker_instance is None:
        _worker_instance = ClassificationWorker()
    return _worker_instance
