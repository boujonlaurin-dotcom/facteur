"""Tests DB de l'ingestion d'artefacts collecteurs (ingest_artifacts.py).

Couvre : domaine inconnu → erreur ; idempotence par dedupe_key ; couple
signal C1 + débunkage avec poids dérivé par code ; dry-run (rollback) n'écrit
rien. Fixtures savepoint du conftest (`db_session`).
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from sqlalchemy import func, select

from app.models.media_eval import (
    MediaEvalDebunkage,
    MediaEvalSignal,
    StatutSignal,
    VoieCollecte,
)
from scripts.media_eval.ingest_artifacts import (
    IngestError,
    charger_artifact,
    ingester,
    inserer_debunkages,
    inserer_signaux,
    rapport_couverture,
)
from scripts.media_eval.schemas import DebunkageBatchArtifact, SignalBatchArtifact

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "media_eval"


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
        # cle_affaire non qualifiée dans la fixture → repli sur l'URL (dédup §5.2.1).
        assert signal.valeur["cle_affaire"] == arcom.url_debunkage

    async def test_idempotence(self, db_session, media_cnews):
        await inserer_debunkages(db_session, _debunkages_batch())
        await db_session.commit()
        second = await inserer_debunkages(db_session, _debunkages_batch())
        await db_session.commit()
        assert second.inseres == 0 and second.doublons == 2
        assert await _count(db_session, MediaEvalDebunkage) == 2


class TestVoieEtHorodatage:
    async def test_voie_agent_par_defaut(self, db_session, media_cnews):
        await inserer_signaux(db_session, _signaux_batch())
        await db_session.commit()
        signal = (
            (await db_session.execute(select(MediaEvalSignal).limit(1)))
            .scalars()
            .first()
        )
        assert signal.voie == VoieCollecte.AGENT

    async def test_collecte_at_egale_genere_at(self, db_session, media_cnews):
        batch = _signaux_batch()
        await inserer_signaux(db_session, batch)
        await db_session.commit()
        signal = (
            (await db_session.execute(select(MediaEvalSignal).limit(1)))
            .scalars()
            .first()
        )
        # collecte_at = moment réel de collecte (≠ ingere_at = écriture DB).
        assert signal.collecte_at == batch.genere_at
        assert signal.version_prompt_collecteur == batch.version_prompt

    async def test_voie_humain_par_prefixe(self, db_session, media_cnews):
        """D6 : agent ``humain:…`` → VoieCollecte.HUMAIN (ouvre la voie C)."""
        batch = _signaux_batch()
        batch.agent = "humain:laurin"
        await inserer_signaux(db_session, batch)
        await db_session.commit()
        signal = (
            (await db_session.execute(select(MediaEvalSignal).limit(1)))
            .scalars()
            .first()
        )
        assert signal.voie == VoieCollecte.HUMAIN
        assert signal.collecteur == "humain:laurin"


class TestCouverture:
    async def test_types_manquants_signales(self, db_session, media_cnews):
        # Un seul type gouvernance présent → les autres sont « manquants ».
        db_session.add(
            MediaEvalSignal(
                media_id=media_cnews.id,
                critere="C8",
                type_signal="charte_deontologique",
                statut=StatutSignal.PRESENT,
                valeur={"url": "https://cnews.fr/charte"},
                voie=VoieCollecte.CODE,
                collecteur="code:collect_pages_types@v1",
                source_urls=["https://cnews.fr/charte"],
                run_id="run-test",
                dedupe_key="k-charte",
            )
        )
        await db_session.commit()
        batch = SignalBatchArtifact.model_validate(
            {
                "run_id": "run-test",
                "agent": "agent:media-eval-collecteur-gouvernance@v1",
                "genere_at": "2026-07-13T08:00:00",
                "items": [
                    {
                        "media_domaine": "cnews.fr",
                        "critere": "C8",
                        "type_signal": "charte_deontologique",
                        "statut": "present",
                        "source_urls": ["https://cnews.fr/charte"],
                    }
                ],
            }
        )
        manquants = await rapport_couverture(db_session, [batch])
        # Le type présent n'est pas listé…
        assert not any("charte_deontologique" in m for m in manquants)
        # …mais les silences le sont (C9 société des journalistes, C7 politique).
        assert any("C9/societe_journalistes" in m for m in manquants)
        assert any("C7/politique_publicitaire" in m for m in manquants)

    async def test_couverture_v13_suit_la_grille_du_batch(
        self, db_session, media_cnews
    ):
        # Batch v1.3 (run non enregistré → repli sur la version du batch) : les
        # manquants citent la gouvernance v1.3 (C6/C10), jamais C5/C11 (v1.2).
        batch = SignalBatchArtifact.model_validate(
            {
                "run_id": "run-test-v13",
                "agent": "agent:media-eval-collecteur-gouvernance@v1",
                "genere_at": "2026-07-20T08:00:00",
                "version_methodo": "v1.3",
                "items": [
                    {
                        "media_domaine": "cnews.fr",
                        "critere": "C9",
                        "type_signal": "charte_deontologique",
                        "statut": "present",
                        "source_urls": ["https://cnews.fr/charte"],
                    }
                ],
            }
        )
        manquants = await rapport_couverture(db_session, [batch])
        assert any("C6/identification_proprietaire" in m for m in manquants)
        assert any("C10/societe_journalistes" in m for m in manquants)
        assert not any("C5/" in m or "C11/" in m for m in manquants)


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
