"""Tests de la construction des entrées évaluateur (build_eval_input.py).

Se concentre sur l'ajout de la **substance** : quand un signal porte un
``snapshot_id``, l'entrée évaluateur doit joindre ``snapshot_extrait`` (borné)
et ``snapshot_url`` — l'évaluateur voit ce que dit la page, pas juste qu'elle
existe (hand-off pilote-2026-07b).
"""

from __future__ import annotations

import uuid
from datetime import datetime

from app.models.media_eval import (
    MediaEvalSignal,
    MediaEvalSnapshot,
    ModeAcces,
    StatutSignal,
    TypePage,
    VoieCollecte,
)
from scripts.media_eval.build_eval_input import (
    SNAPSHOT_EXTRAIT_MAX,
    _charger_snapshots,
    _signaux_du_critere,
    serialiser_signal,
)


def _signal(**kw) -> MediaEvalSignal:
    base = {
        "id": uuid.uuid4(),
        "type_signal": "mentions_legales",
        "statut": StatutSignal.PRESENT,
        "valeur": {"url": "https://cnews.fr/mentions-legales"},
        "citation": None,
        "source_urls": ["https://cnews.fr/mentions-legales"],
        "sources_consultees": [],
        "voie": VoieCollecte.CODE,
        "collecte_at": datetime(2026, 7, 13, 8, 0, 0),
        "snapshot_id": None,
    }
    base.update(kw)
    return MediaEvalSignal(**base)


class TestSerialiserSignal:
    def test_sans_snapshot_pas_de_cle(self):
        data = serialiser_signal(_signal())
        assert "snapshot_extrait" not in data
        assert "snapshot_url" not in data

    def test_avec_snapshot_joint_substance(self):
        snap_id = uuid.uuid4()
        snap = MediaEvalSnapshot(
            id=snap_id,
            url="https://cnews.fr/mentions-legales",
            type_page=TypePage.MENTIONS_LEGALES,
            contenu="Editeur du site SESI SNC au capital de 7 500 euros...",
            mode_acces=ModeAcces.LIBRE,
        )
        data = serialiser_signal(_signal(snapshot_id=snap_id), snap)
        assert data["snapshot_url"] == "https://cnews.fr/mentions-legales"
        assert data["snapshot_extrait"].startswith("Editeur du site SESI SNC")

    def test_extrait_borne(self):
        snap_id = uuid.uuid4()
        snap = MediaEvalSnapshot(
            id=snap_id,
            url="https://ex.fr/p",
            type_page=TypePage.MENTIONS_LEGALES,
            contenu="x" * (SNAPSHOT_EXTRAIT_MAX + 5000),
            mode_acces=ModeAcces.LIBRE,
        )
        data = serialiser_signal(_signal(snapshot_id=snap_id), snap)
        assert len(data["snapshot_extrait"]) == SNAPSHOT_EXTRAIT_MAX

    def test_snapshot_id_non_concordant_ignore(self):
        # Un snapshot d'un autre signal ne doit pas être joint par erreur.
        autre = MediaEvalSnapshot(
            id=uuid.uuid4(),
            url="https://ex.fr/autre",
            type_page=TypePage.AUTRE,
            contenu="autre",
            mode_acces=ModeAcces.LIBRE,
        )
        data = serialiser_signal(_signal(snapshot_id=uuid.uuid4()), autre)
        assert "snapshot_extrait" not in data


class TestChargerSnapshots:
    async def test_join_bout_en_bout(self, db_session, media_cnews, run_test):
        snap = MediaEvalSnapshot(
            media_id=media_cnews.id,
            run_id=run_test.run_id,
            url="https://cnews.fr/mentions-legales",
            type_page=TypePage.MENTIONS_LEGALES,
            contenu="RCS Nanterre 412 916 215 — SESI SNC",
            hash="h",
            http_status=200,
            mode_acces=ModeAcces.LIBRE,
        )
        db_session.add(snap)
        await db_session.flush()
        db_session.add(
            MediaEvalSignal(
                media_id=media_cnews.id,
                critere="C5",
                type_signal="mentions_legales",
                statut=StatutSignal.PRESENT,
                valeur={"url": snap.url},
                voie=VoieCollecte.CODE,
                collecteur="code:collect_pages_types@v1",
                source_urls=[snap.url],
                snapshot_id=snap.id,
                run_id=run_test.run_id,
                dedupe_key="k-mentions",
            )
        )
        await db_session.commit()

        rows = await _signaux_du_critere(
            db_session, media_cnews.id, run_test.run_id, "C5"
        )
        snaps = await _charger_snapshots(db_session, rows)
        serialise = [serialiser_signal(s, snaps.get(s.snapshot_id)) for s in rows]
        assert serialise[0]["snapshot_extrait"] == "RCS Nanterre 412 916 215 — SESI SNC"
        assert serialise[0]["snapshot_url"] == "https://cnews.fr/mentions-legales"
