"""Fixtures DB mutualisées des tests media-eval.

Répare le bug latent PR 1 : les signaux/évaluations portent une FK
``run_id`` → ``media_eval_runs`` que rien ne peuplait (les tests passaient
sur un conteneur test « sale »). ``run_test`` crée la ligne run, et
``media_cnews`` / ``media_reporterre`` en dépendent : toute insertion de
signal a un run parent sur DB propre.

``date_reference`` = 2026-07-08 : cohérente avec les débunkages figés
(``debunkages_cnews.json`` : 2025-11-12 et 2026-02-03 → tous deux < 730 j).
"""

from __future__ import annotations

from datetime import date

import pytest

from app.models.media_eval import MediaEvalMedia, MediaEvalRun, TypeMedia
from scripts.media_eval.schemas import CRITERES_VAGUE_1, VERSION_METHODO

RUN_ID = "run-test"
DATE_REFERENCE = date(2026, 7, 8)


@pytest.fixture
async def run_test(db_session) -> MediaEvalRun:
    run = MediaEvalRun(
        run_id=RUN_ID,
        libelle="Run de test",
        version_methodo=VERSION_METHODO,
        date_reference=DATE_REFERENCE,
        perimetre={
            "medias": ["cnews.fr", "reporterre.net"],
            "criteres": list(CRITERES_VAGUE_1),
        },
    )
    db_session.add(run)
    await db_session.commit()
    return run


@pytest.fixture
async def media_cnews(db_session, run_test) -> MediaEvalMedia:
    media = MediaEvalMedia(
        nom="CNEWS", domaine="cnews.fr", type_media=TypeMedia.AUDIOVISUEL
    )
    db_session.add(media)
    await db_session.commit()
    return media


@pytest.fixture
async def media_reporterre(db_session, run_test) -> MediaEvalMedia:
    media = MediaEvalMedia(
        nom="Reporterre",
        domaine="reporterre.net",
        type_media=TypeMedia.PRESSE_EN_LIGNE,
    )
    db_session.add(media)
    await db_session.commit()
    return media
