"""Tests du module commun voie A (collect_common.py).

Couvre : ``require_run`` lève sur run absent ; dédupe applicative des
snapshots ; dédupe + validation des signaux voie CODE ; **collision voie A/B**
(D2) — même quadruplet ⇒ 2 clés ⇒ 2 lignes (le préfixe ``code|`` empêche
qu'un signal agent supprime un signal code, et réciproquement).
"""

from __future__ import annotations

import pytest
from sqlalchemy import func, select

from app.models.media_eval import (
    MediaEvalSignal,
    MediaEvalSnapshot,
    StatutSignal,
    TypePage,
    VoieCollecte,
)
from scripts.media_eval.collect_common import (
    CollecteError,
    dedupe_key_signal_code,
    ouvrir_collecteur,
    require_run,
)
from scripts.media_eval.ingest_artifacts import dedupe_key_signal
from scripts.media_eval.schemas import SignalArtifact

COLLECTEUR = "code:collect_test@v1"


async def _count(db_session, model) -> int:
    return (await db_session.execute(select(func.count()).select_from(model))).scalar()


class TestRequireRun:
    async def test_leve_si_absent(self, db_session):
        with pytest.raises(CollecteError, match="run inconnu"):
            await require_run(db_session, "run-absent")

    async def test_retourne_run(self, db_session, run_test):
        run = await require_run(db_session, run_test.run_id)
        assert run.run_id == run_test.run_id


class TestDedupeKeyVoieAB:
    def test_prefixe_code_distinct_de_voie_b(self):
        """Même quadruplet → clé voie A ≠ clé voie B (D2)."""
        item = SignalArtifact(
            media_domaine="cnews.fr",
            critere="C8",
            type_signal="charte_deontologique",
            statut="present",
            valeur={"url": "https://cnews.fr/charte"},
            source_urls=["https://cnews.fr/charte"],
        )
        assert dedupe_key_signal_code(item) != dedupe_key_signal(item)


class TestSnapshotDedupe:
    async def test_meme_url_hash_reutilise(self, db_session, media_cnews, run_test):
        c = await ouvrir_collecteur(db_session, media_cnews, run_test, COLLECTEUR)
        s1 = await c.snapshot(
            url="https://cnews.fr/a", type_page=TypePage.A_PROPOS, contenu="x"
        )
        s2 = await c.snapshot(
            url="https://cnews.fr/a", type_page=TypePage.A_PROPOS, contenu="x"
        )
        assert s1.id == s2.id
        assert c.stats.snapshots == 1
        await db_session.commit()
        assert await _count(db_session, MediaEvalSnapshot) == 1

    async def test_contenu_different_nouveau_snapshot(
        self, db_session, media_cnews, run_test
    ):
        c = await ouvrir_collecteur(db_session, media_cnews, run_test, COLLECTEUR)
        await c.snapshot(
            url="https://cnews.fr/a", type_page=TypePage.A_PROPOS, contenu="x"
        )
        await c.snapshot(
            url="https://cnews.fr/a", type_page=TypePage.A_PROPOS, contenu="y"
        )
        assert c.stats.snapshots == 2


class TestSignalCode:
    async def test_insertion_voie_code(self, db_session, media_cnews, run_test):
        c = await ouvrir_collecteur(db_session, media_cnews, run_test, COLLECTEUR)
        signal = await c.signal(
            critere="C5",
            type_signal="mentions_legales",
            statut=StatutSignal.PRESENT,
            valeur={"complet": True},
            source_urls=["https://cnews.fr/mentions-legales"],
        )
        await db_session.commit()
        assert signal is not None
        assert signal.voie == VoieCollecte.CODE
        assert signal.collecteur == COLLECTEUR
        assert c.stats.inseres == 1

    async def test_dedupe_meme_signal(self, db_session, media_cnews, run_test):
        c = await ouvrir_collecteur(db_session, media_cnews, run_test, COLLECTEUR)
        kw = {
            "critere": "C5",
            "type_signal": "mentions_legales",
            "statut": StatutSignal.PRESENT,
            "source_urls": ["https://cnews.fr/mentions-legales"],
        }
        assert await c.signal(**kw) is not None
        assert await c.signal(**kw) is None  # doublon
        assert (c.stats.inseres, c.stats.doublons) == (1, 1)

    async def test_validation_present_sans_source_leve(
        self, db_session, media_cnews, run_test
    ):
        c = await ouvrir_collecteur(db_session, media_cnews, run_test, COLLECTEUR)
        with pytest.raises(CollecteError, match="signal invalide"):
            await c.signal(
                critere="C5",
                type_signal="mentions_legales",
                statut=StatutSignal.PRESENT,
                source_urls=[],  # present sans source → rejet
            )

    async def test_bloque_jamais_silencieux(self, db_session, media_cnews, run_test):
        c = await ouvrir_collecteur(db_session, media_cnews, run_test, COLLECTEUR)
        signal = await c.bloque(
            critere="C1",
            type_signal="sanction_arcom",
            url="https://www.arcom.fr/recherche",
            raison="anti-bot 403 après repli curl_cffi",
        )
        await db_session.commit()
        assert signal is not None
        assert signal.statut == StatutSignal.BLOQUE_ACCES
        assert c.stats.bloques == 1

    async def test_collision_voie_a_b_deux_lignes(
        self, db_session, media_cnews, run_test
    ):
        """Un signal voie A (code) et un signal voie B (agent) sur le même
        quadruplet coexistent — le préfixe ``code|`` les distingue (D2)."""
        # Signal voie B (agent) inséré directement avec la clé voie B.
        item = SignalArtifact(
            media_domaine="cnews.fr",
            critere="C8",
            type_signal="charte_deontologique",
            statut="present",
            valeur={"substance": "charte détaillée, 12 principes"},
            source_urls=["https://cnews.fr/charte"],
        )
        db_session.add(
            MediaEvalSignal(
                media_id=media_cnews.id,
                critere="C8",
                type_signal="charte_deontologique",
                statut=StatutSignal.PRESENT,
                valeur=item.valeur,
                voie=VoieCollecte.AGENT,
                collecteur="agent:media-eval-collecteur-gouvernance@v1",
                source_urls=item.source_urls,
                run_id=run_test.run_id,
                dedupe_key=dedupe_key_signal(item),
            )
        )
        await db_session.commit()

        # Signal voie A (code) sur le MÊME quadruplet — ne doit pas être droppé.
        c = await ouvrir_collecteur(db_session, media_cnews, run_test, COLLECTEUR)
        signal_code = await c.signal(
            critere="C8",
            type_signal="charte_deontologique",
            statut=StatutSignal.PRESENT,
            valeur={"url": "https://cnews.fr/charte", "detection": "page_type"},
            source_urls=["https://cnews.fr/charte"],
        )
        await db_session.commit()
        assert signal_code is not None
        assert await _count(db_session, MediaEvalSignal) == 2
