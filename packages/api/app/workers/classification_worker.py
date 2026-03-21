"""Worker asynchrone pour la classification ML des contenus via Mistral API.

Batch-processes articles from the classification queue using the Mistral LLM API.
Batch-5 with enriched prompt for accurate classification.
"""

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

settings = get_settings()


class ClassificationWorker:
    """Worker qui traite la file d'attente de classification via Mistral API.

    Traite les articles par batch de 5 pour maximiser la qualité de classification.
    """

    def __init__(self, batch_size: int = 5, interval: int = 10):
        """Initialize the worker.

        Args:
            batch_size: Nombre d'articles à traiter par lot (réduit de 20→5 pour qualité)
            interval: Intervalle en secondes entre chaque vérification (réduit de 15→10)
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

        self._classifier = None
        self._loop_count = 0

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

        # Close the classification service's HTTP client
        classifier = self._get_classifier()
        if classifier:
            await classifier.close()

        await self.engine.dispose()

    async def _run_loop(self):
        """Main processing loop."""
        while self.running:
            try:
                # Every ~5 minutes, reset items stuck in "processing" too long
                self._loop_count += 1
                if self._loop_count % 30 == 0:
                    await self._reset_stale_processing()

                await self._process_batch()
            except Exception as e:
                import structlog

                logger = structlog.get_logger()
                logger.error("classification_worker_error", error=str(e))

            await asyncio.sleep(self.interval)

    async def _reset_stale_processing(self):
        """Periodically reset items stuck in 'processing' for >10 minutes."""
        import structlog

        logger = structlog.get_logger()

        try:
            async with self.session_maker() as session:
                service = ClassificationQueueService(session)
                count = await service.reset_stale_processing(stale_minutes=10)
                if count > 0:
                    logger.info(
                        "classification_worker.reset_stale_processing", count=count
                    )
        except Exception as e:
            logger.error("classification_worker.reset_stale_failed", error=str(e))

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

            for i, (item, content, source) in enumerate(
                zip(items, contents, sources, strict=False)
            ):
                if content and content.title:
                    batch_items.append(
                        {
                            "title": content.title or "",
                            "description": content.description or "",
                            "source_name": source.name if source else "",
                        }
                    )
                    batch_indices.append(i)

            # Call Mistral API in batch
            classifier = self._get_classifier()
            all_results: list[dict] = []

            if classifier and classifier.is_ready() and batch_items:
                # Step 1: Classify (topics + serene only)
                all_results = await classifier.classify_batch_async(batch_items)

                # Retry individually for each article that got empty topics
                empty_indices = [
                    idx for idx, r in enumerate(all_results) if not r.get("topics")
                ]
                if empty_indices:
                    logger.info(
                        "classification_worker.individual_retry",
                        total=len(batch_items),
                        empty=len(empty_indices),
                    )
                    for idx in empty_indices:
                        bi = batch_items[idx]
                        result = await classifier.classify_async(
                            title=bi["title"],
                            description=bi.get("description", ""),
                            source_name=bi.get("source_name", ""),
                        )
                        if result.get("topics"):
                            all_results[idx] = result

                # Step 2: Extract entities (separate API call)
                try:
                    all_entities = await classifier.extract_entities_batch_async(
                        batch_items
                    )
                    for idx, entities in enumerate(all_entities):
                        if idx < len(all_results):
                            all_results[idx]["entities"] = entities
                except Exception as e:
                    logger.warning(
                        "classification_worker.entity_extraction_failed",
                        error=str(e),
                    )
            else:
                all_results = [
                    {"topics": [], "serene": None, "entities": []} for _ in batch_items
                ]

            # Process results
            batch_result_idx = 0
            for i, (item, content, source) in enumerate(
                zip(items, contents, sources, strict=False)
            ):
                try:
                    if content is None:
                        await service.mark_completed_with_entities(item.id, [], [])
                        continue

                    # Get topics, serene and entities from batch result
                    if i in batch_indices:
                        result = (
                            all_results[batch_result_idx]
                            if batch_result_idx < len(all_results)
                            else {"topics": [], "serene": None, "entities": []}
                        )
                        batch_result_idx += 1
                        topics = result.get("topics", [])
                        is_serene = result.get("serene")
                        entities = result.get("entities", [])
                    else:
                        topics = []
                        is_serene = None
                        entities = []

                    # If still no topics after individual retry, let the retry
                    # mechanism handle it (mark_failed will requeue up to 3 times)
                    if not topics:
                        if item.retry_count < 2:
                            await service.mark_failed(item.id, "empty_classification")
                            continue
                        # After max retries, mark completed with empty topics
                        logger.warning(
                            "classification_worker.exhausted_retries",
                            content_id=str(item.content_id),
                            title=(content.title or "")[:80],
                        )

                    await service.mark_completed_with_entities(
                        item.id, topics, entities, is_serene=is_serene
                    )

                except Exception as e:
                    await service.mark_failed(item.id, str(e)[:500])


# Global worker instance (singleton)
_worker_instance: ClassificationWorker | None = None


def get_worker() -> ClassificationWorker:
    """Get or create the global worker instance."""
    global _worker_instance
    if _worker_instance is None:
        _worker_instance = ClassificationWorker()
    return _worker_instance
