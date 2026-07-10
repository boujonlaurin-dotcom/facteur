"""Tests DB de l'ingestion d'artefacts collecteurs (ingest_artifacts.py).

Couvre : domaine inconnu → erreur ; idempotence par dedupe_key ; couple
signal C1 + débunkage avec poids dérivé par code ; dry-run (rollback) n'écrit
rien. Fixtures savepoint du conftest (`db_session`).
"""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path

import pytest
from sqlalchemy import func, select

from app.models.media_eval import (
    MediaEvalDebunkage,
    MediaEvalMedia,
    MediaEvalRun,
    MediaEvalSignal,
    TypeMedia,
)
from scripts.media_eval.ingest_artifacts import (
    IngestError,
    charger_artifact,
    ingester,
    inserer_debunkages,
    inserer_signaux,
)
from scripts.media_eval.schemas import DebunkageBatchArtifact, SignalBatchArtifact

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "media_eval"


@pytest.fixture
async def media_cnews(db_session) -> MediaEvalMedia:
    db_session.add(
        MediaEvalRun(
            run_id="run-test", version_methodo="v1.2", date_reference=date(2026, 1, 1)
        )
    )
    media = MediaEvalMedia(
        nom="CNEWS", domaine="cnews.fr", type_media=TypeMedia.AUDIOVISUEL
    )
    db_session.add(media)
    await db_session.commit()
    return media


def _signaux_batch() -> SignalBatchArtifact:
    return SignalBatchArtifact.model_validate(
        json.loads((FIXTURES / "signaux_cnews.json").read_text())
    )


def _debunkages_batch() -> DebunkageBatchArtifact:
    return DebunkageBatchArtifact.model_validate(
        json.loads((FIXTURES / "debunkages_cnews.json").read_text())
    )


async def _count(db_session, model) -> int:
    return (await db_session.execute(select(func.count()).select_from(model))).scalar()


class TestChargerArtifact:
    def test_detection_type(self):
        assert isinstance(
            charger_artifact(FIXTURES / "signaux_cnews.json"), SignalBatchArtifact
        )
        assert isinstance(
            charger_artifact(FIXTURES / "debunkages_cnews.json"),
            DebunkageBatchArtifact,
        )


class TestInsererSignaux:
    async def test_domaine_inconnu_erreur(self, db_session, media_cnews):
        batch = _signaux_batch()
        batch.items[0].media_domaine = "inconnu.fr"
        with pytest.raises(IngestError, match="média inconnu"):
            await inserer_signaux(db_session, batch)

    async def test_insertion_et_idempotence(self, db_session, media_cnews):
        batch = _signaux_batch()
        premier = await inserer_signaux(db_session, batch)
        await db_session.commit()
        assert premier.inseres == 3 and premier.doublons == 0
        assert await _count(db_session, MediaEvalSignal) == 3

        second = await inserer_signaux(db_session, batch)
        await db_session.commit()
        assert second.inseres == 0 and second.doublons == 3
        assert await _count(db_session, MediaEvalSignal) == 3

    async def test_champs_conserves(self, db_session, media_cnews):
        await inserer_signaux(db_session, _signaux_batch())
        await db_session.commit()
        absent = (
            await db_session.execute(
                select(MediaEvalSignal).where(
                    MediaEvalSignal.statut == "absent_verifie"
                )
            )
        ).scalar_one()
        assert absent.critere == "C9"
        assert absent.sources_consultees  # preuve de recherche conservée
        assert absent.collecteur == "agent:media-eval-collecteur-gouvernance@v1"
        assert absent.run_id == "run-test"


class TestInsererDebunkages:
    async def test_couple_signal_debunkage(self, db_session, media_cnews):
        result = await inserer_debunkages(db_session, _debunkages_batch())
        await db_session.commit()
        assert result.inseres == 2
        assert await _count(db_session, MediaEvalSignal) == 2
        assert await _count(db_session, MediaEvalDebunkage) == 2

        arcom = (
            await db_session.execute(
                select(MediaEvalDebunkage).where(MediaEvalDebunkage.emetteur == "arcom")
            )
        ).scalar_one()
        # Poids dérivé par code, pas fourni par l'agent.
        assert arcom.poids_emetteur == "fort"
        signal = (
            await db_session.execute(
                select(MediaEvalSignal).where(MediaEvalSignal.id == arcom.signal_id)
            )
        ).scalar_one()
        assert signal.critere == "C1"
        assert signal.type_signal == "sanction_arcom"
        assert signal.valeur["poids_emetteur"] == "fort"

    async def test_idempotence(self, db_session, media_cnews):
        await inserer_debunkages(db_session, _debunkages_batch())
        await db_session.commit()
        second = await inserer_debunkages(db_session, _debunkages_batch())
        await db_session.commit()
        assert second.inseres == 0 and second.doublons == 2
        assert await _count(db_session, MediaEvalDebunkage) == 2


class TestDryRun:
    async def test_rollback_n_ecrit_rien(self, db_session, media_cnews):
        result = await ingester(
            db_session,
            [FIXTURES / "signaux_cnews.json", FIXTURES / "debunkages_cnews.json"],
        )
        assert result.inseres == 5
        await db_session.rollback()  # équivalent du dry-run CLI
        assert await _count(db_session, MediaEvalSignal) == 0
        assert await _count(db_session, MediaEvalDebunkage) == 0
