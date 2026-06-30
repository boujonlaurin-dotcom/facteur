"""Worker asynchrone pour la classification ML des contenus via Mistral API.

Batch-processes articles from the classification queue using the Mistral LLM API.
Batch-5 with enriched prompt for accurate classification.
"""

import asyncio
import contextlib
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.config import get_settings
from app.models.classification_queue import ClassificationQueue
from app.models.content import Content
from app.models.source import Source
from app.services.classification_queue_service import ClassificationQueueService
from app.services.ml.classification_service import get_classification_service
from app.services.ml.good_news_classifier import get_good_news_classifier
from app.services.ml.language_filter import is_french_source, looks_english

settings = get_settings()


class ClassificationWorker:
    """Worker qui traite la file d'attente de classification via Mistral API.

    Accumulation par lot (LR-1 PR 2) : le gros prompt système (taxonomie 51
    topics) est refacturé à chaque appel batch. On attend donc d'avoir
    `min_batch_size` articles en attente (ou que le plus vieux pending atteigne
    `max_wait_s`) avant de traiter un lot de `batch_size`. Priorité, retry,
    reset des items bloqués et sessions DB courtes sont préservés.
    """

    def __init__(
        self,
        batch_size: int | None = None,
        interval: int | None = None,
        min_batch_size: int | None = None,
        max_wait_s: int | None = None,
    ):
        """Initialize the worker.

        Args:
            batch_size: Nombre max d'articles à traiter par lot (def. settings).
            interval: Intervalle en secondes entre 2 vérifications (def. settings).
            min_batch_size: Seuil minimal de pending avant de traiter un lot
                (gate d'accumulation ; def. settings).
            max_wait_s: Plafond d'attente — si le plus vieux pending dépasse cet
                âge, on traite même sous le seuil (anti-famine ; def. settings).

        Les arguments None retombent sur la config (rollback env-only).
        """

        # `or` est dangereux ici : max_wait_s=0 est un override valide
        # (rollback « traiter dès qu'il y a un item »). On garde donc le
        # fallback sur None explicite.
        def _or_setting(value: int | None, default: int) -> int:
            return value if value is not None else default

        self.batch_size = _or_setting(
            batch_size, settings.classification_worker_batch_size
        )
        self.interval = _or_setting(interval, settings.classification_worker_interval_s)
        self.min_batch_size = _or_setting(
            min_batch_size, settings.classification_worker_min_batch_size
        )
        self.max_wait_s = _or_setting(
            max_wait_s, settings.classification_worker_max_wait_s
        )
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
        self._good_news_classifier = None
        self._loop_count = 0

    def _get_classifier(self):
        """Lazy load classification service."""
        if self._classifier is None:
            self._classifier = get_classification_service()
        return self._classifier

    def _get_good_news_classifier(self):
        """Lazy load good-news classifier (mistral-large pass 2)."""
        if self._good_news_classifier is None:
            self._good_news_classifier = get_good_news_classifier()
        return self._good_news_classifier

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

        good_news_classifier = self._get_good_news_classifier()
        if good_news_classifier:
            await good_news_classifier.close()

        await self.engine.dispose()

    async def _run_loop(self):
        """Main processing loop."""
        while self.running:
            try:
                # Every ~5 minutes, reset items stuck in "processing" too long
                self._loop_count += 1
                if self._loop_count % 30 == 0:
                    await self._reset_stale_processing()

                # Gate d'accumulation : ne traiter un lot que si la file est
                # assez remplie OU si le plus vieux pending a trop attendu.
                if await self._should_process():
                    await self._process_batch()
            except Exception as e:
                import structlog

                logger = structlog.get_logger()
                logger.error("classification_worker_error", error=str(e))

            await asyncio.sleep(self.interval)

    async def _should_process(self) -> bool:
        """Décide si un lot doit être traité maintenant (gate d'accumulation).

        Vrai si `pending >= min_batch_size` (lot plein) OU si le plus vieux
        pending dépasse `max_wait_s` (anti-famine du reste de file). Session
        courte dédiée, ne tient jamais de transaction. Rollback env-only :
        min_batch_size=1 / max_wait_s=0 redonne le comportement « traiter dès
        qu'il y a un item ».
        """
        async with self.session_maker() as session:
            service = ClassificationQueueService(session)
            pending, oldest_age_s = await service.get_pending_stats()

        if pending <= 0:
            return False
        if pending >= self.min_batch_size:
            return True
        return oldest_age_s is not None and oldest_age_s >= self.max_wait_s

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
        """Process one batch of pending items using batch API call.

        3 phases pour ne jamais tenir une transaction DB pendant les appels
        Mistral (90-180 s au pire) : le timeout serveur
        idle_in_transaction_session_timeout=60s tuait la session mi-batch
        (cause racine des IdleInTransactionSessionTimeout Sentry et des kills
        du zombie_session_sweeper).
        """
        import structlog

        logger = structlog.get_logger()

        # Phase 1 — session courte : dequeue + snapshot des données du batch.
        async with self.session_maker() as session:
            service = ClassificationQueueService(session)

            items = await service.dequeue_batch(batch_size=self.batch_size)

            if not items:
                return

            logger.info("classification_worker.processing_batch", count=len(items))

            # Load all contents and sources (2 SELECT batchés, pas de N+1)
            content_rows = await session.execute(
                select(Content).where(
                    Content.id.in_([item.content_id for item in items])
                )
            )
            contents_by_id = {c.id: c for c in content_rows.scalars()}
            contents = [contents_by_id.get(item.content_id) for item in items]

            source_ids = {c.source_id for c in contents if c and c.source_id}
            sources_by_id: dict = {}
            if source_ids:
                source_rows = await session.execute(
                    select(Source).where(Source.id.in_(source_ids))
                )
                sources_by_id = {s.id: s for s in source_rows.scalars()}

            # Snapshot en structures simples : tout ce dont les phases 2-3 ont
            # besoin, pour ne garder aucun objet ORM vivant hors session.
            records: list[dict] = []
            for item, content in zip(items, contents, strict=False):
                source = (
                    sources_by_id.get(content.source_id)
                    if content and content.source_id
                    else None
                )
                records.append(
                    {
                        "queue_id": item.id,
                        "content_id": item.content_id,
                        "retry_count": item.retry_count,
                        "has_content": content is not None,
                        "title": (content.title or "") if content else "",
                        "description": (content.description or "") if content else "",
                        "source_name": source.name if source else "",
                    }
                )

        # Build batch for API call. record_for_batch[k] = records index of the
        # k-ème batch item → permet de remapper all_results[k] sur son record
        # en phase 3 sans curseur séparé.
        batch_items: list[dict] = []
        record_for_batch: list[int] = []

        for i, rec in enumerate(records):
            if rec["has_content"] and rec["title"]:
                batch_items.append(
                    {
                        "title": rec["title"],
                        "description": rec["description"],
                        "source_name": rec["source_name"],
                    }
                )
                record_for_batch.append(i)

        # Phase 2 — hors session : appels Mistral.
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

            # Step 3: Good-news pass (mistral-large) on serene+FR survivors
            # Initialize good_news=None for all; only mutated for evaluated items
            for r in all_results:
                r["good_news"] = None

            good_news_indices: list[int] = []
            good_news_items: list[dict] = []
            for idx, (bi, result) in enumerate(
                zip(batch_items, all_results, strict=False)
            ):
                if result.get("serene") is not True:
                    continue
                source_name = bi.get("source_name", "")
                title = bi.get("title", "")
                if not is_french_source(source_name):
                    continue
                if looks_english(title):
                    continue
                good_news_indices.append(idx)
                good_news_items.append(bi)

            if good_news_items:
                gn_classifier = self._get_good_news_classifier()
                if gn_classifier and gn_classifier.is_ready():
                    try:
                        gn_results = await gn_classifier.classify_batch_async(
                            good_news_items
                        )
                        for offset, idx in enumerate(good_news_indices):
                            if offset < len(gn_results):
                                all_results[idx]["good_news"] = gn_results[offset]
                        logger.info(
                            "classification_worker.good_news_pass",
                            evaluated=len(good_news_items),
                            positives=sum(1 for v in gn_results if v is True),
                        )
                    except Exception as e:
                        logger.warning(
                            "classification_worker.good_news_pass_failed",
                            error=str(e),
                        )
        else:
            all_results = [
                {
                    "topics": [],
                    "serene": None,
                    "good_news": None,
                    "is_ad": None,
                    "entities": [],
                }
                for _ in batch_items
            ]

        # Remap les résultats LLM sur leur record d'origine (indices manquants
        # = articles sans contenu/titre, traités par le fallback ci-dessous).
        result_by_record: dict[int, dict] = {
            rec_idx: all_results[k]
            for k, rec_idx in enumerate(record_for_batch)
            if k < len(all_results)
        }

        # Phase 3 — session courte : écrire les résultats.
        async with self.session_maker() as session:
            service = ClassificationQueueService(session)

            for i, rec in enumerate(records):
                try:
                    if not rec["has_content"]:
                        await service.mark_completed_with_entities(
                            rec["queue_id"], [], []
                        )
                        continue

                    # Get topics, serene, is_ad and entities from batch result
                    result = result_by_record.get(i)
                    if result is not None:
                        topics = result.get("topics", [])
                        is_serene = result.get("serene")
                        is_good_news = result.get("good_news")
                        is_ad = result.get("is_ad")
                        entities = result.get("entities", [])
                    else:
                        topics = []
                        is_serene = None
                        is_good_news = None
                        is_ad = None
                        entities = []

                    # If still no topics after individual retry, let the retry
                    # mechanism handle it (mark_failed will requeue up to 3 times)
                    if not topics:
                        if rec["retry_count"] < 2:
                            await service.mark_failed(
                                rec["queue_id"], "empty_classification"
                            )
                            continue
                        # After max retries, mark completed with empty topics
                        logger.warning(
                            "classification_worker.exhausted_retries",
                            content_id=str(rec["content_id"]),
                            title=rec["title"][:80],
                        )

                    await service.mark_completed_with_entities(
                        rec["queue_id"],
                        topics,
                        entities,
                        is_serene=is_serene,
                        is_good_news=is_good_news,
                        is_ad=is_ad,
                    )

                except Exception as e:
                    await service.mark_failed(rec["queue_id"], str(e)[:500])


# Global worker instance (singleton)
_worker_instance: ClassificationWorker | None = None


def get_worker() -> ClassificationWorker:
    """Get or create the global worker instance."""
    global _worker_instance
    if _worker_instance is None:
        _worker_instance = ClassificationWorker()
    return _worker_instance
