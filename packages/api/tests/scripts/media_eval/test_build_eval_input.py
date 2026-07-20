"""Tests de la construction des entrées évaluateur (build_eval_input.py).

Se concentre sur l'ajout de la **substance** : quand un signal porte un
``snapshot_id``, l'entrée évaluateur doit joindre ``snapshot_extrait`` (borné)
et ``snapshot_url`` — l'évaluateur voit ce que dit la page, pas juste qu'elle
existe (hand-off pilote-2026-07b).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from app.models.media_eval import (
    GraviteDebunkage,
    MediaEvalCorpusArticle,
    MediaEvalDebunkage,
    MediaEvalSignal,
    MediaEvalSnapshot,
    ModeAcces,
    PoidsEmetteur,
    StatutSignal,
    SuiteDonnee,
    TypePage,
    VoieCollecte,
)
from scripts.media_eval.build_eval_input import (
    CORPUS_EXTRAIT_MAX,
    SNAPSHOT_EXTRAIT_MAX,
    _charger_corpus_articles,
    _charger_snapshots,
    _nb_debunkages_frais,
    _signaux_du_critere,
    construire_eval_input,
    serialiser_signal,
)
from scripts.media_eval.schemas import cle_affaire_signal


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


class TestCleAffaireSignal:
    def test_priorite_cle_affaire(self):
        assert cle_affaire_signal({"cle_affaire": "a", "url": "u"}) == "a"

    def test_repli_url(self):
        assert cle_affaire_signal({"url": "https://x"}) == "https://x"

    def test_vide(self):
        assert cle_affaire_signal(None) is None
        assert cle_affaire_signal({}) is None


class TestCorpusBloc:
    def test_corpus_joint_pour_critere_corpus(self):
        payload = construire_eval_input(
            {"nom": "CNEWS", "domaine": "cnews.fr", "type_media": "audiovisuel"},
            "C2",
            [],
            run_id="r",
            date_reference=date(2026, 8, 1),
            version_methodo="v1.3",
            bareme_verbatim="x",
            contrat_commun="c",
            version_prompt_sha="sha",
            pre_flags=[],
            corpus_articles=[{"url": "https://cnews.fr/a1"}],
        )
        assert payload["corpus_articles"] == [{"url": "https://cnews.fr/a1"}]

    def test_pas_de_corpus_pour_critere_hors_corpus(self):
        payload = construire_eval_input(
            {"nom": "CNEWS", "domaine": "cnews.fr", "type_media": "audiovisuel"},
            "C1",
            [],
            run_id="r",
            date_reference=date(2026, 8, 1),
            version_methodo="v1.3",
            bareme_verbatim="x",
            contrat_commun="c",
            version_prompt_sha="sha",
            pre_flags=[],
            corpus_articles=None,
        )
        assert "corpus_articles" not in payload


class TestChargerCorpusArticles:
    async def test_lecture_et_extrait_borne(self, db_session, media_cnews, run_test):
        db_session.add_all(
            [
                MediaEvalCorpusArticle(
                    media_id=media_cnews.id,
                    run_id=run_test.run_id,
                    url="https://cnews.fr/2026/07/a1",
                    titre="Titre 1",
                    date_pub=date(2026, 7, 1),
                    rubrique="politique",
                    texte="y" * (CORPUS_EXTRAIT_MAX + 500),
                    mode_acquisition="http",
                    pre_metriques={"a_signature_html": True},
                ),
                MediaEvalCorpusArticle(
                    media_id=media_cnews.id,
                    run_id=run_test.run_id,
                    url="https://cnews.fr/2026/06/a2",
                    titre="Titre 2",
                    date_pub=date(2026, 6, 1),
                    rubrique="international",
                    texte="court",
                ),
            ]
        )
        await db_session.commit()
        arts = await _charger_corpus_articles(
            db_session, media_cnews.id, run_test.run_id
        )
        assert len(arts) == 2
        # Tri par date décroissante : le plus récent d'abord.
        assert arts[0]["url"].endswith("a1")
        assert len(arts[0]["extrait"]) == CORPUS_EXTRAIT_MAX
        assert arts[0]["pre_metriques"] == {"a_signature_html": True}


class TestNbDebunkagesFraisDedupAffaire:
    async def _debunkage(self, db_session, media, run, *, cle, url, publie):
        signal = MediaEvalSignal(
            media_id=media.id,
            critere="C1",
            type_signal="debunkage",
            statut=StatutSignal.PRESENT,
            valeur={"url": url, "cle_affaire": cle},
            voie=VoieCollecte.AGENT,
            collecteur="agent:x@v1",
            source_urls=[url],
            run_id=run.run_id,
            dedupe_key=f"k-{url}",
        )
        db_session.add(signal)
        await db_session.flush()
        db_session.add(
            MediaEvalDebunkage(
                media_id=media.id,
                signal_id=signal.id,
                url_debunkage=url,
                emetteur="les_decodeurs",
                poids_emetteur=PoidsEmetteur.MOYEN,
                gravite=GraviteDebunkage.SIGNIFICATIVE,
                suite_donnee=SuiteDonnee.AUCUNE,
                publie_at=publie,
            )
        )

    async def test_dedup_par_affaire(self, db_session, media_cnews, run_test):
        # 3 débunkages, dont 2 pour la même affaire → 2 litiges distincts.
        await self._debunkage(
            db_session, media_cnews, run_test,
            cle="affaire_x", url="https://d1", publie=date(2026, 1, 1),
        )
        await self._debunkage(
            db_session, media_cnews, run_test,
            cle="affaire_x", url="https://d2", publie=date(2026, 2, 1),
        )
        await self._debunkage(
            db_session, media_cnews, run_test,
            cle="affaire_y", url="https://d3", publie=date(2026, 3, 1),
        )
        await db_session.commit()
        n = await _nb_debunkages_frais(
            db_session, media_cnews.id, run_test.run_id, date(2026, 7, 8), "v1.2"
        )
        assert n == 2
