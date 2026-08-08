#!/usr/bin/env python3
"""Synthèse de la fiche média — pur calcul (architecture §6), SANS LLM.

Depuis les évaluations d'un (média, run) :
- ``score_renormalise = score_brut / score_max_applicable × 100`` où
  ``score_max_applicable = Σ barèmes[critères vague 1 évalués]`` de la grille
  du run (`media_eval_runs.version_methodo`) (les N/A et
  ``revue_requise`` sont exclus du dénominateur — CNEWS : 54 ; Reporterre si
  C1 N/A : 34) ;
- lettre A–E (`LETTRES`) ;
- confiance : ``haute`` = 0 N/A et 0 flag bloquant ; ``moyenne`` = ≤ 2 N/A ou
  ``signaux_contradictoires`` ; ``basse`` = > 2 N/A ou ``revue_humaine_requise``
  (ou critère en ``revue_requise``).

Sortie : ligne `media_eval_fiches` (upsert par (media, run), ``--apply``
gardé) + fiche markdown. **Dry-run par défaut.**

Usage :
    cd packages/api
    python3 scripts/media_eval/synthese_fiche.py --media cnews.fr --run-id pilote-2026-07
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import (
    ConfianceFiche,
    MediaEvalEvaluation,
    MediaEvalFiche,
    MediaEvalRun,
    StatutEvaluation,
)
from scripts.cleanup_orphan_sources import _is_test_db
from scripts.media_eval.ingest_artifacts import IngestError, resoudre_media
from scripts.media_eval.schemas import grille

_REPO_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_FICHES_DIR = _REPO_ROOT / "docs" / "media-eval" / "fiches"

_FLAGS_BLOQUANTS = {
    "signaux_contradictoires",
    "corroboration_insuffisante",
    "revue_humaine_requise",
    "bloque_acces",
}


def lettre_pour(score_renormalise: float, lettres: list[tuple[int, str]]) -> str:
    for seuil, lettre in lettres:
        if score_renormalise >= seuil:
            return lettre
    return lettres[-1][1]


def _meilleure_par_critere(evaluations: list[dict]) -> dict[str, dict]:
    """Une éval par critère : le raccourci code: prime sur l'agent."""
    par_critere: dict[str, dict] = {}
    for ev in evaluations:
        critere = ev["critere"]
        actuel = par_critere.get(critere)
        if actuel is None or (
            str(ev.get("evaluateur", "")).startswith("code:")
            and not str(actuel.get("evaluateur", "")).startswith("code:")
        ):
            par_critere[critere] = ev
    return par_critere


def compute_fiche(evaluations: list[dict], version: str) -> dict:
    """Calcule la fiche — pur, testable sans DB.

    ``evaluations`` : dicts {critere, statut, score, flags, evaluateur, niveau}.
    ``version`` : version méthodo du run (`media_eval_runs.version_methodo`).
    """
    g = grille(version)
    par_critere = _meilleure_par_critere(evaluations)

    criteres_evalues, criteres_na, criteres_revue = [], [], []
    flags_toutes: set[str] = set()
    score_brut = 0.0
    for critere in g.criteres_vague_1:
        ev = par_critere.get(critere)
        if ev is None:
            continue
        flags_toutes.update(ev.get("flags") or [])
        statut = ev["statut"]
        if statut == StatutEvaluation.EVALUEE.value:
            criteres_evalues.append(critere)
            score_brut += float(ev["score"])
        elif statut == StatutEvaluation.NON_APPLICABLE.value:
            criteres_na.append(critere)
        else:
            criteres_revue.append(critere)

    score_max_applicable = float(sum(g.baremes[c] for c in criteres_evalues))
    score_renormalise = (
        round(score_brut / score_max_applicable * 100, 1)
        if score_max_applicable
        else 0.0
    )

    n_na = len(criteres_na)
    if n_na > 2 or "revue_humaine_requise" in flags_toutes or criteres_revue:
        confiance = ConfianceFiche.BASSE.value
    elif n_na == 0 and not (flags_toutes & _FLAGS_BLOQUANTS):
        confiance = ConfianceFiche.HAUTE.value
    else:
        confiance = ConfianceFiche.MOYENNE.value

    return {
        "score_brut": score_brut,
        "score_max_applicable": score_max_applicable,
        "score_renormalise": score_renormalise,
        "lettre": lettre_pour(score_renormalise, g.lettres),
        "criteres_evalues": criteres_evalues,
        "criteres_na": criteres_na,
        "criteres_revue_requise": criteres_revue,
        "confiance": confiance,
        "detail": {
            c: {
                "statut": ev["statut"],
                "score": ev.get("score"),
                "score_max": g.baremes[c],
                "niveau": ev.get("niveau"),
                "flags": list(ev.get("flags") or []),
                "evaluateur": ev.get("evaluateur"),
            }
            for c, ev in sorted(par_critere.items())
            if c in g.baremes  # éval hors grille (ex. C11 sur run v1.3) ignorée
        },
    }


def render_fiche_md(media: dict, run_id: str, fiche: dict) -> str:
    lignes = [
        f"# Fiche d'évaluation — {media['nom']} ({media['domaine']})",
        "",
        f"- Run : `{run_id}` · généré le {datetime.now(UTC).date().isoformat()}",
        f"- **Score : {fiche['score_brut']:g} / {fiche['score_max_applicable']:g}"
        f" → {fiche['score_renormalise']:g}/100 · lettre {fiche['lettre']}**",
        f"- Confiance : **{fiche['confiance']}**",
        f"- Critères évalués : {', '.join(fiche['criteres_evalues']) or 'aucun'}"
        f" · N/A : {', '.join(fiche['criteres_na']) or 'aucun'}"
        f" · revue requise : {', '.join(fiche['criteres_revue_requise']) or 'aucun'}",
        "",
        "| Critère | Statut | Score | Niveau | Flags | Évaluateur |",
        "|---|---|---|---|---|---|",
    ]
    for critere, det in fiche["detail"].items():
        score = (
            "N/A" if det["score"] is None else f"{det['score']:g}/{det['score_max']}"
        )
        lignes.append(
            f"| {critere} | {det['statut']} | {score} | "
            f"{det['niveau'] if det['niveau'] is not None else '-'} | "
            f"{', '.join(det['flags']) or '-'} | {det['evaluateur'] or '-'} |"
        )
    lignes.append("")
    return "\n".join(lignes)


async def run(
    domaine: str,
    run_id: str,
    out_dir: Path,
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

    async with async_session_maker() as session:
        try:
            media = await resoudre_media(session, domaine)
            run_row = (
                await session.execute(
                    select(MediaEvalRun).where(MediaEvalRun.run_id == run_id)
                )
            ).scalar_one_or_none()
            if run_row is None:
                print(f"REJET : run {run_id!r} inconnu (lancer create_run.py).")
                return 1
            rows = await session.execute(
                select(MediaEvalEvaluation).where(
                    MediaEvalEvaluation.media_id == media.id,
                    MediaEvalEvaluation.run_id == run_id,
                )
            )
            evaluations = [
                {
                    "critere": ev.critere,
                    "statut": ev.statut.value
                    if hasattr(ev.statut, "value")
                    else ev.statut,
                    "score": ev.score,
                    "niveau": ev.niveau,
                    "flags": list(ev.flags or []),
                    "evaluateur": ev.evaluateur,
                }
                for ev in rows.scalars()
            ]
            if not evaluations:
                print(f"REJET : aucune évaluation pour {domaine} / {run_id}.")
                return 1

            fiche = compute_fiche(evaluations, run_row.version_methodo)
            media_dict = {"nom": media.nom, "domaine": media.domaine}
            print(json.dumps(fiche, indent=2, ensure_ascii=False))

            out_dir.mkdir(parents=True, exist_ok=True)
            md_path = out_dir / f"{media.domaine.replace('.', '_')}_{run_id}.md"
            md_path.write_text(render_fiche_md(media_dict, run_id, fiche))
            print(f"Fiche markdown : {md_path}")

            if not apply:
                await session.rollback()
                print("(dry-run — ligne media_eval_fiches non écrite. --apply.)")
                return 0

            existante = (
                await session.execute(
                    select(MediaEvalFiche).where(
                        MediaEvalFiche.media_id == media.id,
                        MediaEvalFiche.run_id == run_id,
                    )
                )
            ).scalar_one_or_none()
            valeurs = {
                "score_brut": fiche["score_brut"],
                "score_max_applicable": fiche["score_max_applicable"],
                "score_renormalise": fiche["score_renormalise"],
                "lettre": fiche["lettre"],
                "criteres_evalues": fiche["criteres_evalues"],
                "criteres_na": fiche["criteres_na"],
                "confiance": ConfianceFiche(fiche["confiance"]),
                "detail": fiche["detail"],
            }
            if existante is None:
                session.add(MediaEvalFiche(media_id=media.id, run_id=run_id, **valeurs))
            else:
                for champ, valeur in valeurs.items():
                    setattr(existante, champ, valeur)
            await session.commit()
            print("APPLIQUÉ : fiche écrite (media_eval_fiches).")
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
    parser.add_argument("--run-id", required=True)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=DEFAULT_FICHES_DIR,
        help="dossier des fiches markdown (défaut docs/media-eval/fiches)",
    )
    parser.add_argument(
        "--apply", action="store_true", help="exécute (défaut: dry-run)"
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
                args.out_dir,
                apply=args.apply,
                allow_prod=args.allow_prod,
            )
        )
    )


if __name__ == "__main__":
    main()
