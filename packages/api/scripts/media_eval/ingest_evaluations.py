#!/usr/bin/env python3
"""Ingestion des sorties évaluateurs — garde-fous aval, SANS LLM.

Valide les artefacts ``evaluations_*.json`` (`EvaluationBatchArtifact`) puis
applique les règles mécaniques AVANT toute écriture :

- chaque ``signal_id`` cité doit **exister**, appartenir au **bon média** et
  au **bon critère** — sinon rejet de l'artefact (exit non-zéro, rien d'écrit) ;
- le **score faisant foi est dérivé par code** (`derive_score`) depuis les
  ``determinations`` — jamais lu depuis l'artefact ;
- **corroboration** (§5.2) : score plein avec < 2 sources indépendantes →
  plafonné au palier inférieur + flag ``corroboration_insuffisante`` ;
- ``bloque_acces`` seul → statut ``revue_requise``, score NULL — **jamais 0** ;
- ``donnees_insuffisantes`` → ``non_applicable``, score NULL.

Idempotent : une éval existante (media, critère, évaluateur, run) est ignorée.
**Dry-run par défaut**, ``--apply`` gardé (``--allow-prod`` hors DB test).

Usage :
    cd packages/api
    python3 scripts/media_eval/ingest_evaluations.py --artifact <fichier|dossier> [--apply]
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import (
    MediaEvalEvaluation,
    MediaEvalRun,
    MediaEvalSignal,
    StatutEvaluation,
)
from scripts.cleanup_orphan_sources import _is_test_db
from scripts.media_eval.build_eval_input import serialiser_signal
from scripts.media_eval.garde_fous import (
    appliquer_corroboration,
    statut_evaluation,
)
from scripts.media_eval.ingest_artifacts import IngestError, resoudre_media
from scripts.media_eval.schemas import (
    VERSION_METHODO,
    EvaluationBatchArtifact,
    EvaluationOutput,
    grille,
)


@dataclass
class EvaluationPreparee:
    """Ligne prête à insérer, après garde-fous aval — pur, testable."""

    statut: str
    score: float | None
    niveau: int | None
    flags: list[str] = field(default_factory=list)


def preparer_evaluation(
    item: EvaluationOutput,
    signaux_cites: list[dict],
    version: str = VERSION_METHODO,
) -> EvaluationPreparee:
    """Applique les garde-fous aval à une sortie évaluateur validée."""
    statut = statut_evaluation(item.flags, signaux_cites)
    if statut != StatutEvaluation.EVALUEE.value:
        # N/A ou revue_requise : score NULL — jamais 0 (arbitrage n°3).
        return EvaluationPreparee(
            statut=statut, score=None, niveau=None, flags=list(item.flags)
        )
    score, niveau = item.score_derive()
    score, flags_corro = appliquer_corroboration(
        item.critere, score, signaux_cites, version
    )
    return EvaluationPreparee(
        statut=statut,
        score=score,
        niveau=niveau,
        flags=list(item.flags) + flags_corro,
    )


async def _signaux_cites(session, item: EvaluationOutput, media_id) -> list[dict]:
    """Charge et contrôle les signaux cités — lève IngestError sinon."""
    ids = [UUID(s) for s in item.signal_ids_cites]
    if not ids:
        return []
    rows = await session.execute(
        select(MediaEvalSignal).where(MediaEvalSignal.id.in_(ids))
    )
    signaux = {s.id: s for s in rows.scalars()}
    for signal_id in ids:
        signal = signaux.get(signal_id)
        if signal is None:
            raise IngestError(
                f"{item.critere}/{item.media_domaine}: signal cité inexistant {signal_id}"
            )
        if signal.media_id != media_id:
            raise IngestError(
                f"{item.critere}/{item.media_domaine}: signal {signal_id} "
                "appartient à un autre média"
            )
        if signal.critere != item.critere:
            raise IngestError(
                f"{item.critere}/{item.media_domaine}: signal {signal_id} "
                f"appartient au critère {signal.critere}"
            )
    return [serialiser_signal(signaux[i]) for i in ids]


async def ingester_evaluations(
    session, batch: EvaluationBatchArtifact
) -> tuple[int, int]:
    """Valide TOUT le batch puis insère. Retourne (insérées, ignorées).

    La grille est celle du **run** (``media_eval_runs.version_methodo``) : le
    batch doit la déclarer à l'identique, sinon rejet (garantit que l'évaluateur
    a bien lu la rubrique de la bonne version).
    """
    run = (
        await session.execute(
            select(MediaEvalRun).where(MediaEvalRun.run_id == batch.run_id)
        )
    ).scalar_one_or_none()
    if run is None:
        raise IngestError(
            f"run inconnu : {batch.run_id!r} — le créer d'abord (create_run.py)."
        )
    version = run.version_methodo
    if batch.version_methodo != version:
        raise IngestError(
            f"batch {batch.run_id}: version_methodo artefact "
            f"{batch.version_methodo!r} ≠ run {version!r}"
        )
    g = grille(version)

    preparees: list[tuple[EvaluationOutput, EvaluationPreparee, UUID]] = []
    for item in batch.items:
        media = await resoudre_media(session, item.media_domaine)
        signaux_cites = await _signaux_cites(session, item, media.id)
        preparees.append(
            (item, preparer_evaluation(item, signaux_cites, version), media.id)
        )

    inserees, ignorees = 0, 0
    for item, prep, media_id in preparees:
        existante = (
            await session.execute(
                select(MediaEvalEvaluation.id).where(
                    MediaEvalEvaluation.media_id == media_id,
                    MediaEvalEvaluation.critere == item.critere,
                    MediaEvalEvaluation.evaluateur == batch.agent,
                    MediaEvalEvaluation.run_id == batch.run_id,
                )
            )
        ).scalar_one_or_none()
        if existante is not None:
            ignorees += 1
            continue
        session.add(
            MediaEvalEvaluation(
                media_id=media_id,
                critere=item.critere,
                score=prep.score,
                score_max=float(g.baremes[item.critere]),
                niveau=prep.niveau,
                statut=StatutEvaluation(prep.statut),
                justification=item.justification,
                signal_ids=[UUID(s) for s in item.signal_ids_cites],
                flags=prep.flags,
                evaluateur=batch.agent,
                version_methodo=version,
                version_prompt=batch.version_prompt or "",
                run_id=batch.run_id,
            )
        )
        inserees += 1
    return inserees, ignorees


def _collecter_paths(artifact: Path) -> list[Path]:
    if artifact.is_dir():
        paths = sorted(artifact.glob("evaluations_*.json"))
        if not paths:
            raise IngestError(f"aucun artefact evaluations_*.json dans {artifact}")
        return paths
    return [artifact]


async def run(artifact: Path, apply: bool, allow_prod: bool) -> int:
    settings = get_settings()
    db_url = settings.database_url or ""
    is_test = _is_test_db(db_url)
    print(
        f"DB cible : {db_url.split('@')[-1] if '@' in db_url else db_url}  (test={is_test})"
    )
    if apply and not is_test and not allow_prod:
        print("\nABORT : --apply contre une DB non-test sans --allow-prod (gated PO).")
        return 2

    try:
        paths = _collecter_paths(artifact)
        batches = [
            EvaluationBatchArtifact.model_validate(json.loads(p.read_text()))
            for p in paths
        ]
    except IngestError as exc:
        print(f"REJET : {exc}")
        return 1

    async with async_session_maker() as session:
        try:
            total_ins, total_ign = 0, 0
            for batch in batches:
                ins, ign = await ingester_evaluations(session, batch)
                total_ins += ins
                total_ign += ign
            print(
                f"Artefacts : {len(paths)} | à insérer : {total_ins} | "
                f"déjà présentes (ignorées) : {total_ign}"
            )
            if not apply:
                await session.rollback()
                print("(dry-run — aucune mutation. Relance avec --apply.)")
                return 0
            await session.commit()
            print(f"APPLIQUÉ : {total_ins} évaluations écrites.")
            return 0
        except IngestError as exc:
            await session.rollback()
            print(f"REJET : {exc} — rien n'a été écrit.")
            return 1
        except Exception:
            await session.rollback()
            raise
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--artifact",
        type=Path,
        required=True,
        help="fichier evaluations_*.json ou dossier",
    )
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
    )
    parser.add_argument(
        "--allow-prod", action="store_true", help="autorise --apply en prod"
    )
    args = parser.parse_args()
    sys.exit(
        asyncio.run(run(args.artifact, apply=args.apply, allow_prod=args.allow_prod))
    )


if __name__ == "__main__":
    main()
