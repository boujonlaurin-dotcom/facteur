"""Tests DB de l'ingestion des évaluations (ingest_evaluations.py).

Couvre : rejet d'un signal_id inexistant / d'un autre média / d'un autre
critère ; score dérivé par code ; corroboration plafonnée ; `bloque_acces` →
`revue_requise` (jamais 0) ; N/A ; idempotence ; dry-run n'écrit rien.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from sqlalchemy import func, select

from app.models.media_eval import (
    MediaEvalEvaluation,
    MediaEvalMedia,
    MediaEvalSignal,
    StatutSignal,
    TypeMedia,
    VoieCollecte,
)
from scripts.media_eval.ingest_artifacts import IngestError
from scripts.media_eval.ingest_evaluations import (
    ingester_evaluations,
    preparer_evaluation,
)
from scripts.media_eval.schemas import (
    EvaluationBatchArtifact,
    EvaluationOutput,
)

RUN_ID = "run-test"


@pytest.fixture
async def media_cnews(db_session) -> MediaEvalMedia:
    media = MediaEvalMedia(
        nom="CNEWS", domaine="cnews.fr", type_media=TypeMedia.AUDIOVISUEL
    )
    db_session.add(media)
    await db_session.commit()
    return media


@pytest.fixture
async def media_reporterre(db_session) -> MediaEvalMedia:
    media = MediaEvalMedia(
        nom="Reporterre", domaine="reporterre.net", type_media=TypeMedia.PRESSE_EN_LIGNE
    )
    db_session.add(media)
    await db_session.commit()
    return media


async def make_signal(
    db_session,
    media: MediaEvalMedia,
    critere: str = "C5",
    type_signal: str = "mentions_legales",
    statut: StatutSignal = StatutSignal.PRESENT,
    source_urls: list[str] | None = None,
    dedupe_suffix: str = "",
) -> MediaEvalSignal:
    signal = MediaEvalSignal(
        media_id=media.id,
        critere=critere,
        type_signal=type_signal,
        statut=statut,
        valeur={},
        voie=VoieCollecte.AGENT,
        collecteur="agent:test",
        source_urls=source_urls or [f"https://{media.domaine}/page"],
        run_id=RUN_ID,
        dedupe_key=f"k-{critere}-{type_signal}-{dedupe_suffix}",
    )
    db_session.add(signal)
    await db_session.commit()
    return signal


def make_batch(*items: dict) -> EvaluationBatchArtifact:
    return EvaluationBatchArtifact(
        run_id=RUN_ID,
        agent="agent:media-eval-evaluateur@v1",
        genere_at=datetime.now(UTC),
        version_prompt="sha-test",
        items=[EvaluationOutput.model_validate(i) for i in items],
    )


def item_c5(signal_ids: list[str], **kw) -> dict:
    base = {
        "media_domaine": "cnews.fr",
        "critere": "C5",
        "determinations": {"profil_signaux": "mixtes"},
        "justification": "Transparence partielle.",
        "signal_ids_cites": signal_ids,
        "flags": [],
    }
    base.update(kw)
    return base


class TestGardeFousAval:
    async def test_signal_inexistant_rejet(self, db_session, media_cnews):
        batch = make_batch(item_c5(["00000000-0000-0000-0000-00000000dead"]))
        with pytest.raises(IngestError, match="inexistant"):
            await ingester_evaluations(db_session, batch)

    async def test_signal_autre_media_rejet(
        self, db_session, media_cnews, media_reporterre
    ):
        etranger = await make_signal(db_session, media_reporterre)
        batch = make_batch(item_c5([str(etranger.id)]))
        with pytest.raises(IngestError, match="autre média"):
            await ingester_evaluations(db_session, batch)

    async def test_signal_autre_critere_rejet(self, db_session, media_cnews):
        c9 = await make_signal(
            db_session, media_cnews, critere="C9", type_signal="charte_independance"
        )
        batch = make_batch(item_c5([str(c9.id)]))
        with pytest.raises(IngestError, match="critère C9"):
            await ingester_evaluations(db_session, batch)

    async def test_rejet_ne_laisse_rien(self, db_session, media_cnews):
        ok = await make_signal(db_session, media_cnews)
        batch = make_batch(
            item_c5([str(ok.id)]),
            item_c5(["00000000-0000-0000-0000-00000000dead"]),
        )
        with pytest.raises(IngestError):
            await ingester_evaluations(db_session, batch)
        await db_session.rollback()
        n = (
            await db_session.execute(
                select(func.count()).select_from(MediaEvalEvaluation)
            )
        ).scalar()
        assert n == 0


class TestScoreDeriveEtCorroboration:
    async def test_score_derive_par_code(self, db_session, media_cnews):
        s1 = await make_signal(db_session, media_cnews, dedupe_suffix="1")
        batch = make_batch(item_c5([str(s1.id)]))
        ins, _ = await ingester_evaluations(db_session, batch)
        await db_session.commit()
        assert ins == 1
        ev = (await db_session.execute(select(MediaEvalEvaluation))).scalar_one()
        assert ev.score == 5.0  # mixtes -> 50 % de 10, dérivé par code
        assert ev.statut == "evaluee"
        assert ev.score_max == 10.0

    async def test_corroboration_plafonne_score_plein(self, db_session, media_cnews):
        # 1 seul domaine source -> score plein 10 plafonné à 5 + flag.
        s1 = await make_signal(
            db_session,
            media_cnews,
            source_urls=["https://cnews.fr/mentions-legales"],
            dedupe_suffix="1",
        )
        batch = make_batch(
            item_c5(
                [str(s1.id)],
                determinations={"profil_signaux": "positifs_majoritaires"},
            )
        )
        await ingester_evaluations(db_session, batch)
        await db_session.commit()
        ev = (await db_session.execute(select(MediaEvalEvaluation))).scalar_one()
        assert ev.score == 5.0
        assert "corroboration_insuffisante" in ev.flags

    async def test_score_plein_corrobore_intact(self, db_session, media_cnews):
        s1 = await make_signal(
            db_session,
            media_cnews,
            source_urls=["https://cnews.fr/mentions-legales"],
            dedupe_suffix="1",
        )
        s2 = await make_signal(
            db_session,
            media_cnews,
            type_signal="structure_actionnariat",
            source_urls=["https://pappers.fr/entreprise/sesi"],
            dedupe_suffix="2",
        )
        batch = make_batch(
            item_c5(
                [str(s1.id), str(s2.id)],
                determinations={"profil_signaux": "positifs_majoritaires"},
            )
        )
        await ingester_evaluations(db_session, batch)
        await db_session.commit()
        ev = (await db_session.execute(select(MediaEvalEvaluation))).scalar_one()
        assert ev.score == 10.0
        assert ev.flags == []


class TestStatuts:
    async def test_bloque_acces_revue_requise_jamais_zero(
        self, db_session, media_cnews
    ):
        bloque = await make_signal(
            db_session,
            media_cnews,
            statut=StatutSignal.BLOQUE_ACCES,
            dedupe_suffix="b",
        )
        batch = make_batch(item_c5([str(bloque.id)]))
        await ingester_evaluations(db_session, batch)
        await db_session.commit()
        ev = (await db_session.execute(select(MediaEvalEvaluation))).scalar_one()
        assert ev.statut == "revue_requise"
        assert ev.score is None  # jamais 0

    async def test_donnees_insuffisantes_na(self, db_session, media_cnews):
        batch = make_batch(
            {
                "media_domaine": "cnews.fr",
                "critere": "C1",
                "determinations": {},
                "justification": "Fallback déclenché, pas de corpus en V0.",
                "signal_ids_cites": [],
                "flags": ["donnees_insuffisantes"],
            }
        )
        await ingester_evaluations(db_session, batch)
        await db_session.commit()
        ev = (await db_session.execute(select(MediaEvalEvaluation))).scalar_one()
        assert ev.statut == "non_applicable"
        assert ev.score is None

    async def test_niveau_persiste_c9(self, db_session, media_cnews):
        s = await make_signal(
            db_session,
            media_cnews,
            critere="C9",
            type_signal="charte_independance",
            dedupe_suffix="9",
        )
        batch = make_batch(
            {
                "media_domaine": "cnews.fr",
                "critere": "C9",
                "determinations": {"niveau": 1},
                "justification": "Charte déclarative sans mécanisme contraignant.",
                "signal_ids_cites": [str(s.id)],
                "flags": ["revue_humaine_requise"],
            }
        )
        await ingester_evaluations(db_session, batch)
        await db_session.commit()
        ev = (await db_session.execute(select(MediaEvalEvaluation))).scalar_one()
        assert (ev.score, ev.niveau) == (5.0, 1)
        assert "revue_humaine_requise" in ev.flags


class TestIdempotence:
    async def test_reingestion_ignoree(self, db_session, media_cnews):
        s1 = await make_signal(db_session, media_cnews, dedupe_suffix="1")
        batch = make_batch(item_c5([str(s1.id)]))
        ins1, ign1 = await ingester_evaluations(db_session, batch)
        await db_session.commit()
        ins2, ign2 = await ingester_evaluations(db_session, batch)
        await db_session.commit()
        assert (ins1, ign1) == (1, 0)
        assert (ins2, ign2) == (0, 1)


class TestPreparerEvaluation:
    def test_pur_sans_db(self):
        item = EvaluationOutput.model_validate(
            item_c5(["3f0a5b1e-0000-0000-0000-000000000001"])
        )
        prep = preparer_evaluation(
            item, [{"statut": "present", "source_urls": ["https://cnews.fr/a"]}]
        )
        assert prep.statut == "evaluee"
        assert prep.score == 5.0
