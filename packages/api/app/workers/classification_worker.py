"""Worker asynchrone pour la classification ML des contenus via Mistral API.

Batch-processes articles from the classification queue using the Mistral LLM API.
Increased throughput: batch_size=20, interval=15s → ~4800 articles/hour.
"""

import asyncio
from datetime import datetime
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.config import get_settings
from app.models.classification_queue import ClassificationQueue
from app.models.content import Content
from app.models.source import Source
from app.services.classification_queue_service import ClassificationQueueService
from app.services.ml.classification_service import get_classification_service, VALID_TOPIC_SLUGS

settings = get_settings()


class ClassificationWorker:
    """Worker qui traite la file d'attente de classification via Mistral API.

    Traite les articles par batch pour maximiser le débit.
    """

    def __init__(self, batch_size: int = 20, interval: int = 15):
        """Initialize the worker.

        Args:
            batch_size: Nombre d'articles à traiter par lot (augmenté de 10→20)
            interval: Intervalle en secondes entre chaque vérification (réduit de 60→15)
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

        self._classifier = None

    def _get_classifier(self):
        """Lazy load classification service."""
        if self._classifier is None:
            self._classifier = get_classification_service()
        return self._classifier

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
                    .where(ClassificationQueue.status == 'processing')
                    .values(status='pending', updated_at=datetime.utcnow())
                )
                count = result.rowcount
                await session.commit()

                if count > 0:
                    logger.info("classification_worker.recovered_stuck_items", count=count)
        except Exception as e:
            logger.error("classification_worker.recovery_failed", error=str(e))

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

        # Close the classification service's HTTP client
        classifier = self._get_classifier()
        if classifier:
            await classifier.close()

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

            await asyncio.sleep(self.interval)

    async def _process_batch(self):
        """Process one batch of pending items using batch API call."""
        import structlog
        logger = structlog.get_logger()

        async with self.session_maker() as session:
            service = ClassificationQueueService(session)

            items = await service.dequeue_batch(batch_size=self.batch_size)

            if not items:
                return

            logger.info("classification_worker.processing_batch", count=len(items))

            # Load all contents and sources
            contents: list[Content | None] = []
            sources: list[Source | None] = []
            for item in items:
                content = await session.get(Content, item.content_id)
                contents.append(content)
                if content and content.source_id:
                    source = await session.get(Source, content.source_id)
                    sources.append(source)
                else:
                    sources.append(None)

            # Build batch for API call
            batch_items: list[dict] = []
            batch_indices: list[int] = []  # Maps batch position → items index

            for i, (item, content) in enumerate(zip(items, contents)):
                if content and content.title:
                    batch_items.append({
                        "title": content.title or "",
                        "description": content.description or "",
                    })
                    batch_indices.append(i)

            # Call Mistral API in batch
            classifier = self._get_classifier()
            all_topics: list[list[str]] = []

            if classifier and classifier.is_ready() and batch_items:
                all_topics = await classifier.classify_batch_async(batch_items)
            else:
                all_topics = [[] for _ in batch_items]

            # Process results
            batch_result_idx = 0
            for i, (item, content, source) in enumerate(zip(items, contents, sources)):
                try:
                    if content is None:
                        await service.mark_completed_with_entities(item.id, [], [])
                        continue

                    # Get topics from batch result
                    if i in batch_indices:
                        topics = all_topics[batch_result_idx] if batch_result_idx < len(all_topics) else []
                        batch_result_idx += 1
                    else:
                        topics = []

                    # Fallback: use source.granular_topics, but only valid slugs
                    if not topics and source and source.granular_topics:
                        topics = [t for t in source.granular_topics if t in VALID_TOPIC_SLUGS]

                    await service.mark_completed_with_entities(item.id, topics, [])

                except Exception as e:
                    await service.mark_failed(item.id, str(e)[:500])


# Global worker instance (singleton)
_worker_instance: Optional[ClassificationWorker] = None


def get_worker() -> ClassificationWorker:
    """Get or create the global worker instance."""
    global _worker_instance
    if _worker_instance is None:
        _worker_instance = ClassificationWorker()
    return _worker_instance
