#!/usr/bin/env python3
"""Export des entrées évaluateur `eval_inputs/<media>_<critere>.json`.

Pour chaque critère vague 1 : signaux du data store (média, run) + barème
**verbatim** (rubrique `docs/media-eval/rubrics/C<k>.md`) + contrat commun
(`_common.md`). ``version_prompt`` = sha256 du fichier rubrique.

Garde-fous **amont** (codés en dur, `scripts/media_eval/garde_fous.py`) :
- **fraîcheur** : signaux événementiels > 730 j exclus (journalisés) ;
- **raccourci JTI** : certification valide → écrit directement l'éval C8
  pleine (``evaluateur='code:jti_shortcut'``), pas d'agent ; l'entrée C8
  n'est pas générée ;
- **fallback C1** : < 3 débunkages / 2 ans → ``pre_flags:
  ["fallback_c1_declenche"]`` (l'évaluateur rendra N/A en V0).

Les fichiers d'entrée sont toujours écrits (pas une mutation DB) ; seule
l'éval JTI passe par ``--apply`` (+ ``--allow-prod`` hors DB test).

Usage :
    cd packages/api
    python3 scripts/media_eval/build_eval_input.py --media cnews.fr --run-id pilote-2026-07
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import sys
from datetime import date
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import (
    MediaEvalCorpusArticle,
    MediaEvalDebunkage,
    MediaEvalEvaluation,
    MediaEvalSignal,
    MediaEvalSnapshot,
    StatutEvaluation,
)
from scripts.cleanup_orphan_sources import _is_test_db
from scripts.media_eval.collect_common import require_run
from scripts.media_eval.garde_fous import (
    detecter_jti_valide,
    fallback_c1_requis,
    filtrer_fraicheur,
)
from scripts.media_eval.ingest_artifacts import IngestError, resoudre_media
from scripts.media_eval.schemas import (
    FLAG_FALLBACK_C1,
    VERSION_METHODO,
    cle_affaire_signal,
    grille,
)

_REPO_ROOT = Path(__file__).resolve().parents[4]
RUBRICS_DIR = _REPO_ROOT / "docs" / "media-eval" / "rubrics"
DEFAULT_OUT_ROOT = _REPO_ROOT / ".context" / "media_eval"

# Substance de la page jointe au signal pour que l'évaluateur voie ce que dit
# la page (pas seulement qu'elle existe) — cf. hand-off « mini-filtre ».
SNAPSHOT_EXTRAIT_MAX = 4000

# Bloc corpus (§5.4) joint aux critères sur échantillon (C2/C3/C4/C5/C7) : les
# articles instrumentés par collect_corpus_articles sont un **contexte** que
# l'évaluateur vérifie ; l'ancre citable reste le signal `articles` (voie B).
CORPUS_EXTRAIT_MAX = 2000  # extrait par article (l'agent voie B a le texte plein)
CORPUS_ARTICLES_MAX = 40  # plafond §5.4 (20-40 articles informatifs)


def rubrics_dir(version: str) -> Path:
    """Répertoire des rubriques d'une version (v1.2 : plat ; v1.3 : sous-dossier)."""
    return RUBRICS_DIR / "v1.3" if version == "v1.3" else RUBRICS_DIR


def rubrique_path(critere: str, version: str = VERSION_METHODO) -> Path:
    return rubrics_dir(version) / f"{critere}.md"


def version_prompt(critere: str, version: str = VERSION_METHODO) -> str:
    """sha256 du fichier rubrique — toute retouche invalide la comparabilité."""
    return hashlib.sha256(rubrique_path(critere, version).read_bytes()).hexdigest()


def serialiser_signal(
    signal: MediaEvalSignal, snapshot: MediaEvalSnapshot | None = None
) -> dict:
    """Sérialise un signal ; joint la substance du snapshot si fourni.

    La voie A capture jusqu'à 20 000 caractères par page mais n'expose que
    ``{url, detection}`` : sans le contenu, l'évaluateur voit qu'une page existe
    sans savoir ce qu'elle dit. On joint donc un extrait (``snapshot_extrait``)
    et l'URL (``snapshot_url``) quand le signal porte un ``snapshot_id``.
    """
    data = {
        "id": str(signal.id),
        "type_signal": signal.type_signal,
        "statut": signal.statut.value
        if hasattr(signal.statut, "value")
        else signal.statut,
        "valeur": signal.valeur,
        "citation": signal.citation,
        "source_urls": list(signal.source_urls or []),
        "sources_consultees": list(signal.sources_consultees or []),
        "voie": signal.voie.value if hasattr(signal.voie, "value") else signal.voie,
        "collecte_at": signal.collecte_at.isoformat() if signal.collecte_at else None,
    }
    if snapshot is not None and signal.snapshot_id == snapshot.id:
        data["snapshot_url"] = snapshot.url
        data["snapshot_extrait"] = (snapshot.contenu or "")[:SNAPSHOT_EXTRAIT_MAX]
    return data


def construire_eval_input(
    media: dict,
    critere: str,
    signaux: list[dict],
    *,
    run_id: str,
    date_reference: date,
    version_methodo: str,
    bareme_verbatim: str,
    contrat_commun: str,
    version_prompt_sha: str,
    pre_flags: list[str],
    corpus_articles: list[dict] | None = None,
) -> dict:
    """Payload lu par l'agent évaluateur — pur, testable sans DB.

    ``corpus_articles`` (critères sur corpus §5.4) est un **contexte** non
    citable : l'évaluateur note d'après le signal ``articles`` (métriques
    agrégées) et vérifie ses affirmations sur cet échantillon. Absent pour les
    critères hors corpus.
    """
    payload = {
        "media": media,
        "critere": critere,
        "run_id": run_id,
        "date_reference": date_reference.isoformat(),
        "version_methodo": version_methodo,
        "version_prompt": version_prompt_sha,
        "score_max": grille(version_methodo).baremes[critere],
        "contrat_commun": contrat_commun,
        "bareme_verbatim": bareme_verbatim,
        "pre_flags": pre_flags,
        "signaux": signaux,
    }
    if corpus_articles is not None:
        payload["corpus_articles"] = corpus_articles
    return payload


async def _signaux_du_critere(session, media_id, run_id: str, critere: str):
    rows = await session.execute(
        select(MediaEvalSignal)
        .where(
            MediaEvalSignal.media_id == media_id,
            MediaEvalSignal.run_id == run_id,
            MediaEvalSignal.critere == critere,
        )
        .order_by(MediaEvalSignal.collecte_at)
    )
    return list(rows.scalars())


async def _charger_snapshots(
    session, signaux: list[MediaEvalSignal]
) -> dict[UUID, MediaEvalSnapshot]:
    """Snapshots référencés par les signaux (par id), pour joindre la substance."""
    ids = {s.snapshot_id for s in signaux if s.snapshot_id is not None}
    if not ids:
        return {}
    rows = await session.execute(
        select(MediaEvalSnapshot).where(MediaEvalSnapshot.id.in_(ids))
    )
    return {snap.id: snap for snap in rows.scalars()}


async def _nb_debunkages_frais(
    session, media_id, run_id: str, aujourd_hui: date, version: str
) -> int:
    """Nombre d'**affaires** distinctes débunkées dans la fenêtre (fallback C1).

    Dédup par clé d'affaire (§5.2.1) : plusieurs débunkages d'un même événement
    comptent pour un seul litige. Sans clé d'affaire qualifiée, le repli sur
    l'URL préserve le comptage un-par-débunkage.
    """
    fenetre = grille(version).fraicheur_max_jours
    rows = await session.execute(
        select(MediaEvalDebunkage.publie_at, MediaEvalSignal.valeur)
        .join(MediaEvalSignal, MediaEvalSignal.id == MediaEvalDebunkage.signal_id)
        .where(
            MediaEvalDebunkage.media_id == media_id,
            MediaEvalSignal.run_id == run_id,
        )
    )
    affaires: set[str] = set()
    for publie_at, valeur in rows:
        if (aujourd_hui - publie_at).days > fenetre:
            continue
        affaires.add(cle_affaire_signal(valeur) or str(publie_at))
    return len(affaires)


async def _charger_corpus_articles(
    session, media_id, run_id: str
) -> list[dict]:
    """Échantillon d'articles instrumenté (§5.4), joint comme contexte corpus."""
    rows = await session.execute(
        select(MediaEvalCorpusArticle)
        .where(
            MediaEvalCorpusArticle.media_id == media_id,
            MediaEvalCorpusArticle.run_id == run_id,
        )
        .order_by(MediaEvalCorpusArticle.date_pub.desc().nullslast())
        .limit(CORPUS_ARTICLES_MAX)
    )
    return [
        {
            "url": a.url,
            "titre": a.titre,
            "date_pub": a.date_pub.isoformat() if a.date_pub else None,
            "rubrique": a.rubrique,
            "mode_acquisition": a.mode_acquisition,
            "pre_metriques": a.pre_metriques,
            "extrait": (a.texte or "")[:CORPUS_EXTRAIT_MAX],
        }
        for a in rows.scalars()
    ]


async def ecrire_eval_jti(
    session, media_id, run_id: str, signal_jti: dict, version: str = VERSION_METHODO
) -> MediaEvalEvaluation:
    """Raccourci JTI : éval C8 pleine écrite par code, sans agent (v1.2 seul)."""
    plein = float(grille(version).baremes["C8"])
    evaluation = MediaEvalEvaluation(
        media_id=media_id,
        critere="C8",
        score=plein,
        score_max=plein,
        statut=StatutEvaluation.EVALUEE,
        justification=(
            "Certification JTI en cours de validité (raccourci automatique "
            "v1.2 : score plein C8 sans examen complémentaire)."
        ),
        signal_ids=[UUID(signal_jti["id"])],
        flags=[],
        evaluateur="code:jti_shortcut",
        version_methodo=version,
        version_prompt=version_prompt("C8", version),
        run_id=run_id,
    )
    session.add(evaluation)
    return evaluation


async def run(
    domaine: str,
    run_id: str,
    out_root: Path,
    apply: bool,
    allow_prod: bool,
) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(
        f"DB cible : {db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})"
    )
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    out_dir = out_root / run_id / "eval_inputs"

    async with async_session_maker() as session:
        try:
            # date_reference du run pilote la fraîcheur (jamais now()) : un run
            # rejoué plus tard produit les mêmes entrées évaluateur.
            run_row = await require_run(session, run_id)
            aujourd_hui = run_row.date_reference
            version = run_row.version_methodo
            grille_run = grille(version)  # lève si version inconnue
            contrat_commun = (rubrics_dir(version) / "_common.md").read_text()
            print(f"date_reference : {aujourd_hui.isoformat()} · methodo {version}")
            media = await resoudre_media(session, domaine)
            media_dict = {
                "nom": media.nom,
                "domaine": media.domaine,
                "type_media": media.type_media.value
                if hasattr(media.type_media, "value")
                else media.type_media,
            }

            nb_debunkages = await _nb_debunkages_frais(
                session, media.id, run_id, aujourd_hui, version
            )
            corpus_articles = None
            if grille_run.criteres_corpus:
                corpus_articles = await _charger_corpus_articles(
                    session, media.id, run_id
                )
                print(
                    f"corpus §5.4 : {len(corpus_articles)} article(s) instrumenté(s) "
                    f"joints aux critères {', '.join(grille_run.criteres_corpus)}"
                )
            ecrits: list[Path] = []
            jti_applique = False

            for critere in grille_run.criteres_vague_1:
                rows = await _signaux_du_critere(session, media.id, run_id, critere)
                snaps = await _charger_snapshots(session, rows)
                signaux = [serialiser_signal(s, snaps.get(s.snapshot_id)) for s in rows]
                frais, exclus = filtrer_fraicheur(signaux, aujourd_hui, version)
                for s in exclus:
                    print(
                        f"  ! {critere}: signal {s['type_signal']} exclu "
                        f"(fraîcheur > {grille_run.fraicheur_max_jours} j "
                        "ou date manquante)"
                    )

                # Raccourci JTI = v1.2 uniquement (C8 = engagement déontologique).
                # En v1.3, JTI est un signal du C9 fusionné (pas de raccourci).
                if version == "v1.2" and critere == "C8":
                    signal_jti = detecter_jti_valide(frais)
                    if signal_jti is not None:
                        print(
                            "  ★ C8: certification JTI valide → raccourci "
                            "code:jti_shortcut (pas d'agent)"
                        )
                        if apply:
                            await ecrire_eval_jti(
                                session, media.id, run_id, signal_jti, version
                            )
                            jti_applique = True
                        else:
                            print("    (dry-run — éval C8 non écrite)")
                        continue  # pas d'entrée évaluateur pour C8

                pre_flags: list[str] = []
                if critere == "C1" and fallback_c1_requis(nb_debunkages):
                    pre_flags.append(FLAG_FALLBACK_C1)
                    print(
                        f"  ⚑ C1: fallback déclenché ({nb_debunkages} débunkage(s) "
                        "frais < 3) — l'évaluateur rendra N/A en V0"
                    )

                payload = construire_eval_input(
                    media_dict,
                    critere,
                    frais,
                    run_id=run_id,
                    date_reference=aujourd_hui,
                    version_methodo=version,
                    bareme_verbatim=rubrique_path(critere, version).read_text(),
                    contrat_commun=contrat_commun,
                    version_prompt_sha=version_prompt(critere, version),
                    pre_flags=pre_flags,
                    corpus_articles=(
                        corpus_articles
                        if critere in grille_run.criteres_corpus
                        else None
                    ),
                )
                out_dir.mkdir(parents=True, exist_ok=True)
                out_path = out_dir / f"{media.domaine.replace('.', '_')}_{critere}.json"
                out_path.write_text(
                    json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
                )
                ecrits.append(out_path)
                affiche = (
                    out_path.relative_to(_REPO_ROOT)
                    if out_path.is_relative_to(_REPO_ROOT)
                    else out_path
                )
                print(f"  → {affiche} ({len(frais)} signaux)")

            if jti_applique:
                await session.commit()
                print("APPLIQUÉ : éval C8 (code:jti_shortcut) écrite.")
            else:
                await session.rollback()
            print(f"Entrées évaluateur écrites : {len(ecrits)}")
            return 0
        except IngestError as exc:
            await session.rollback()
            print(f"REJET : {exc}")
            return 1
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--media", required=True, help="domaine (ex. cnews.fr)")
    parser.add_argument("--run-id", required=True, help="ex. pilote-2026-07")
    parser.add_argument(
        "--out-root",
        type=Path,
        default=DEFAULT_OUT_ROOT,
        help="racine des artefacts (défaut .context/media_eval)",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="écrit l'éval C8 du raccourci JTI en DB (défaut: dry-run)",
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    args = parser.parse_args()
    sys.exit(
        asyncio.run(
            run(
                args.media,
                args.run_id,
                args.out_root,
                apply=args.apply,
                allow_prod=args.allow_prod,
            )
        )
    )


if __name__ == "__main__":
    main()
