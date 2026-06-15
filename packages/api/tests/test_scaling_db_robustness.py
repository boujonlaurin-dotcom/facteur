"""Tests robustesse DB (scaling phase 2) : sessions courtes du worker de
classification + purge des lignes terminées de classification_queue."""

from datetime import datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest


class _SessionTracker:
    """Compte les sessions ouvertes pour vérifier qu'aucune ne couvre les LLM."""

    def __init__(self, session_factory):
        self.open_count = 0
        self.sessions: list = []
        self._session_factory = session_factory

    def make_maker(self):
        tracker = self

        def maker():
            session = tracker._session_factory()
            tracker.sessions.append(session)

            class _Ctx:
                async def __aenter__(self):
                    tracker.open_count += 1
                    return session

                async def __aexit__(self, *args):
                    tracker.open_count -= 1
                    return False

            return _Ctx()

        return maker


def _fake_content(content_id, source_id=None, title="Titre", description="Desc"):
    content = MagicMock()
    content.id = content_id
    content.source_id = source_id
    content.title = title
    content.description = description
    return content


def _fake_item(content_id, retry_count=0):
    item = MagicMock()
    item.id = uuid4()
    item.content_id = content_id
    item.retry_count = retry_count
    return item


@pytest.mark.asyncio
async def test_process_batch_holds_no_session_during_llm_calls():
    """La cause racine des IdleInTransactionSessionTimeout : aucune session DB
    ne doit être ouverte pendant les appels Mistral (90-180 s au pire)."""
    from app.workers.classification_worker import ClassificationWorker

    content_id = uuid4()
    source_id = uuid4()
    item = _fake_item(content_id)
    content = _fake_content(content_id, source_id=source_id)
    source = MagicMock()
    source.id = source_id
    source.name = "Le Monde"

    def session_factory():
        session = MagicMock()
        contents_result = MagicMock()
        contents_result.scalars.return_value = [content]
        sources_result = MagicMock()
        sources_result.scalars.return_value = [source]
        session.execute = AsyncMock(side_effect=[contents_result, sources_result])
        return session

    tracker = _SessionTracker(session_factory)

    open_during_llm: list[int] = []

    async def classify_batch(batch_items):
        open_during_llm.append(tracker.open_count)
        return [{"topics": ["politique"], "serene": False, "is_ad": False}]

    async def extract_entities(batch_items):
        open_during_llm.append(tracker.open_count)
        return [[{"text": "Macron", "label": "PER"}]]

    classifier = MagicMock()
    classifier.is_ready.return_value = True
    classifier.classify_batch_async = AsyncMock(side_effect=classify_batch)
    classifier.extract_entities_batch_async = AsyncMock(side_effect=extract_entities)

    service = MagicMock()
    service.dequeue_batch = AsyncMock(return_value=[item])
    service.mark_completed_with_entities = AsyncMock()
    service.mark_failed = AsyncMock()

    with patch.object(ClassificationWorker, "__init__", lambda self: None):
        worker = ClassificationWorker()
    worker.batch_size = 5
    worker.session_maker = tracker.make_maker()
    worker._classifier = classifier
    worker._good_news_classifier = MagicMock(is_ready=MagicMock(return_value=False))

    with patch(
        "app.workers.classification_worker.ClassificationQueueService",
        return_value=service,
    ):
        await worker._process_batch()

    # Les 2 appels LLM ont eu lieu, tous hors session DB.
    assert open_during_llm == [0, 0]
    # Le résultat a bien été écrit (phase 3).
    service.mark_completed_with_entities.assert_awaited_once()
    args, kwargs = service.mark_completed_with_entities.await_args
    assert args[0] == item.id
    assert args[1] == ["politique"]
    # 2 sessions courtes : lecture (phase 1) + écriture (phase 3).
    assert len(tracker.sessions) == 2
    assert tracker.open_count == 0


@pytest.mark.asyncio
async def test_process_batch_empty_topics_requeues_via_mark_failed():
    """Un article sans topics après retry doit repartir en mark_failed (<2 retries)."""
    from app.workers.classification_worker import ClassificationWorker

    content_id = uuid4()
    item = _fake_item(content_id, retry_count=0)
    content = _fake_content(content_id)

    def session_factory():
        session = MagicMock()
        contents_result = MagicMock()
        contents_result.scalars.return_value = [content]
        session.execute = AsyncMock(return_value=contents_result)
        return session

    tracker = _SessionTracker(session_factory)

    classifier = MagicMock()
    classifier.is_ready.return_value = True
    classifier.classify_batch_async = AsyncMock(return_value=[{"topics": []}])
    classifier.classify_async = AsyncMock(return_value={"topics": []})
    classifier.extract_entities_batch_async = AsyncMock(return_value=[[]])

    service = MagicMock()
    service.dequeue_batch = AsyncMock(return_value=[item])
    service.mark_completed_with_entities = AsyncMock()
    service.mark_failed = AsyncMock()

    with patch.object(ClassificationWorker, "__init__", lambda self: None):
        worker = ClassificationWorker()
    worker.batch_size = 5
    worker.session_maker = tracker.make_maker()
    worker._classifier = classifier
    worker._good_news_classifier = MagicMock(is_ready=MagicMock(return_value=False))

    with patch(
        "app.workers.classification_worker.ClassificationQueueService",
        return_value=service,
    ):
        await worker._process_batch()

    service.mark_failed.assert_awaited_once_with(item.id, "empty_classification")
    service.mark_completed_with_entities.assert_not_awaited()


@pytest.mark.asyncio
async def test_purge_finished_classification_queue_deletes_and_commits():
    from app.workers.storage_cleanup import purge_finished_classification_queue

    mock_session = AsyncMock()
    delete_result = MagicMock()
    delete_result.rowcount = 42
    mock_session.execute = AsyncMock(return_value=delete_result)

    maker = MagicMock()
    maker.return_value.__aenter__ = AsyncMock(return_value=mock_session)
    maker.return_value.__aexit__ = AsyncMock(return_value=False)

    with patch("app.workers.storage_cleanup.safe_async_session", maker):
        deleted = await purge_finished_classification_queue()

    assert deleted == 42
    mock_session.commit.assert_awaited_once()
    # La clause where cible les statuts terminés et un cutoff de rétention.
    stmt = mock_session.execute.await_args.args[0]
    compiled = str(stmt.compile(compile_kwargs={"literal_binds": False}))
    assert "classification_queue" in compiled
    assert "status" in compiled
    assert "updated_at" in compiled


@pytest.mark.asyncio
async def test_purge_finished_classification_queue_never_raises():
    from app.workers.storage_cleanup import purge_finished_classification_queue

    maker = MagicMock(side_effect=RuntimeError("db down"))
    with patch("app.workers.storage_cleanup.safe_async_session", maker):
        deleted = await purge_finished_classification_queue()
    assert deleted == 0
