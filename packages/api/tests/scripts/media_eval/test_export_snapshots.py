"""Tests de l'export des snapshots (export_snapshots.py).

Couvre : nom de fichier déterministe + suffixe anti-collision ; en-tête de
provenance ; lecture DB filtrée par run/média (voie A → fichiers pour la
voie B, hand-off pilote-2026-07b).
"""

from __future__ import annotations

from datetime import datetime

from app.models.media_eval import MediaEvalSnapshot, ModeAcces, TypePage
from scripts.media_eval.export_snapshots import (
    charger_snapshots,
    nom_fichier,
    rendre_fichier,
    slug,
)


class TestPur:
    def test_slug(self):
        assert slug("cnews.fr") == "cnews_fr"

    def test_nom_fichier_collision(self):
        vus: set[str] = set()
        assert nom_fichier("cnews.fr", TypePage.AUTRE, vus) == "cnews_fr__autre.txt"
        assert nom_fichier("cnews.fr", TypePage.AUTRE, vus) == "cnews_fr__autre__2.txt"
        assert nom_fichier("cnews.fr", TypePage.AUTRE, vus) == "cnews_fr__autre__3.txt"

    def test_rendre_fichier_entete(self):
        snap = MediaEvalSnapshot(
            url="https://cnews.fr/mentions-legales",
            type_page=TypePage.MENTIONS_LEGALES,
            contenu="Editeur du site SESI SNC ... RCS Nanterre 412 916 215",
            hash="abc123",
            http_status=200,
            mode_acces=ModeAcces.LIBRE,
            capture_at=datetime(2026, 7, 13, 8, 0, 0),
        )
        texte = rendre_fichier(snap)
        assert "url: https://cnews.fr/mentions-legales" in texte
        assert "type_page: mentions_legales" in texte
        assert "http_status: 200" in texte
        assert "mode_acces: libre" in texte
        assert "hash: abc123" in texte
        assert texte.rstrip().endswith("RCS Nanterre 412 916 215")


class TestChargerSnapshots:
    async def test_lecture_filtre_run(self, db_session, media_cnews, run_test):
        db_session.add_all(
            [
                MediaEvalSnapshot(
                    media_id=media_cnews.id,
                    run_id=run_test.run_id,
                    url="https://cnews.fr/",
                    type_page=TypePage.AUTRE,
                    contenu="home",
                    hash="h1",
                    http_status=200,
                    mode_acces=ModeAcces.LIBRE,
                ),
                MediaEvalSnapshot(
                    media_id=media_cnews.id,
                    run_id=run_test.run_id,
                    url="https://cnews.fr/mentions-legales",
                    type_page=TypePage.MENTIONS_LEGALES,
                    contenu="mentions",
                    hash="h2",
                    http_status=200,
                    mode_acces=ModeAcces.LIBRE,
                ),
            ]
        )
        await db_session.commit()

        snaps = await charger_snapshots(db_session, run_test.run_id, "cnews.fr")
        assert len(snaps) == 2
        assert all(domaine == "cnews.fr" for domaine, _ in snaps)
        # Tri par url : la home (« / ») précède « /mentions-legales ».
        assert snaps[0][1].url == "https://cnews.fr/"

        vide = await charger_snapshots(db_session, "run-inexistant", None)
        assert vide == []
