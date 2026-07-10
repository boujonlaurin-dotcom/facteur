"""Tests de la gate d'accumulation du ClassificationWorker (LR-1 PR 2).

Le worker ne traite un lot que si la file atteint `min_batch_size` OU si le
plus vieux pending dépasse `max_wait_s`. Économie de coût Mistral : le gros
prompt système (taxonomie 51 topics) est refacturé moins souvent.
"""

from contextlib import asynccontextmanager
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.workers.classification_worker import ClassificationWorker


def _make_worker(min_batch_size: int, max_wait_s: int, stats: tuple) -> ClassificationWorker:
    """Worker minimal (sans engine réel) dont la file renvoie `stats`."""
    with patch.object(ClassificationWorker, "__init__", lambda self: None):
        worker = ClassificationWorker()
    worker.min_batch_size = min_batch_size
    worker.max_wait_s = max_wait_s

    service = MagicMock()
    service.get_pending_stats = AsyncMock(return_value=stats)

    @asynccontextmanager
    async def fake_maker():
        yield MagicMock()

    worker.session_maker = fake_maker
    worker._service_patch = patch(
        "app.workers.classification_worker.ClassificationQueueService",
        return_value=service,
    )
    return worker


@pytest.mark.asyncio
async def test_processes_when_min_batch_reached():
    """pending >= min_batch_size ⇒ on traite (lot plein), même si jeune."""
    worker = _make_worker(min_batch_size=8, max_wait_s=300, stats=(8, 5.0))
    with worker._service_patch:
        assert await worker._should_process() is True


@pytest.mark.asyncio
async def test_waits_below_min_batch_and_under_max_wait():
    """pending < min_batch et plus vieux pending récent ⇒ on attend."""
    worker = _make_worker(min_batch_size=8, max_wait_s=300, stats=(3, 12.0))
    with worker._service_patch:
        assert await worker._should_process() is False


@pytest.mark.asyncio
async def test_processes_when_oldest_exceeds_max_wait():
    """Sous le seuil mais le plus vieux pending a trop attendu ⇒ anti-famine."""
    worker = _make_worker(min_batch_size=8, max_wait_s=300, stats=(3, 301.0))
    with worker._service_patch:
        assert await worker._should_process() is True


@pytest.mark.asyncio
async def test_empty_queue_does_not_process():
    """File vide ⇒ jamais de traitement (pas d'appel Mistral à vide)."""
    worker = _make_worker(min_batch_size=8, max_wait_s=300, stats=(0, None))
    with worker._service_patch:
        assert await worker._should_process() is False


@pytest.mark.asyncio
async def test_rollback_config_processes_immediately():
    """Rollback env-only (min_batch=1, max_wait=0) ⇒ traite dès 1 pending."""
    worker = _make_worker(min_batch_size=1, max_wait_s=0, stats=(1, 0.0))
    with worker._service_patch:
        assert await worker._should_process() is True
