"""Tests pour le pilotage manuel du worker de classification (`drive_once`).

`drive_once()` traite un lot hors run-loop pour le diagnostic post-deploy et
renvoie le nombre d'items dequeués (contrat consommé par l'endpoint admin
force-drive). Ici on vérifie la délégation ; l'exécution réelle du batch est
couverte par les tests d'intégration du worker.
"""

from unittest.mock import AsyncMock

import pytest

from app.workers.classification_worker import ClassificationWorker


@pytest.mark.asyncio
async def test_drive_once_delegates_to_process_batch_and_returns_count():
    worker = ClassificationWorker()
    worker._process_batch = AsyncMock(return_value=3)

    result = await worker.drive_once()

    assert result == 3
    worker._process_batch.assert_awaited_once()
