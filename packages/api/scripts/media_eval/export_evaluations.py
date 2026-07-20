#!/usr/bin/env python3
"""Export des évaluations d'un run → JSON au schéma `GoldenSet` (lecture seule).

Sérialise les ``media_eval_evaluations`` d'un run dans le **même schéma** que
le golden set humain, ce qui permet de les comparer directement
(``evaluate_golden_agreement.py``). Le raccourci ``code:jti_shortcut`` est
inclus (préfixe ``code:``) au même titre que les évaluateurs agents.

Fonction pure ``evaluations_to_goldenset`` partagée avec ``rapport_pilote.py``.
**Mode consensus (double évaluation, décision PO 18/07/2026)** : les critères à
3 niveaux (C5/C9/C10 en v1.3) sont notés par **deux** évaluateurs indépendants
(préfixes ``…@v1-a`` / ``…@v1-b``). Deux évaluations pour un même
(média, critère) ne sont plus une erreur : accord → consensus conservé ;
désaccord → ``revue_requise`` avec les deux verdicts documentés (conforme v1.3).

Usage :
    cd packages/api
    python3 scripts/media_eval/export_evaluations.py --run-id pilote-2026-07 \
        --out .context/media_eval/pilote-2026-07/evaluations_export.json
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import select

from app.config import get_settings
from app.database import async_session_maker, engine
from app.models.media_eval import MediaEvalEvaluation, MediaEvalMedia
from scripts.media_eval.schemas import GoldenEntry, GoldenSet

DEFAULT_PREFIXES = ("agent:", "code:")


def _verdict_court(ev: dict) -> str:
    """Verdict lisible d'une évaluation (pour documenter un désaccord)."""
    if ev["statut"] != "evaluee":
        return ev["statut"]
    if ev.get("niveau") is not None:
        return f"niveau {ev['niveau']}"
    return f"score {ev.get('score')}"


def evaluateurs_accordent(evals: list[dict]) -> bool:
    """True si les évaluations d'un même (média, critère) convergent.

    Accord = même statut ; et si ``evaluee`` : même niveau (critères à niveaux)
    ou, à défaut de niveau, même score. Le désaccord bascule en revue humaine.
    """
    if len({e["statut"] for e in evals}) > 1:
        return False
    if evals[0]["statut"] != "evaluee":
        return True
    niveaux = [e.get("niveau") for e in evals]
    if all(n is not None for n in niveaux):
        return len(set(niveaux)) == 1
    return len({e.get("score") for e in evals}) == 1


def _grouper_par_cle(
    evaluations: list[dict], prefixes: tuple[str, ...]
) -> dict[tuple[str, str], list[dict]]:
    """Groupe les évaluations par (média, critère), filtrées par préfixe."""
    par_cle: dict[tuple[str, str], list[dict]] = {}
    for ev in evaluations:
        if not any(ev["evaluateur"].startswith(p) for p in prefixes):
            continue
        par_cle.setdefault((ev["media_domaine"], ev["critere"]), []).append(ev)
    return par_cle


def _entry_consensus(evals: list[dict]) -> GoldenEntry:
    """Entrée consensus d'un (média, critère) — 1 ou plusieurs évaluateurs."""
    rep = evals[0]
    version = rep.get("version_methodo")
    commun = {
        "media_domaine": rep["media_domaine"],
        "critere": rep["critere"],
        **({"version_methodo": version} if version else {}),
    }
    if len(evals) == 1:
        return GoldenEntry(
            **commun, statut=rep["statut"], score=rep["score"], niveau=rep.get("niveau")
        )
    evaluateurs = ", ".join(sorted(e["evaluateur"] for e in evals))
    if evaluateurs_accordent(evals):
        return GoldenEntry(
            **commun,
            statut=rep["statut"],
            score=rep["score"],
            niveau=rep.get("niveau"),
            commentaire=f"consensus double évaluation ({evaluateurs})",
        )
    votes = " / ".join(
        f"{e['evaluateur']}: {_verdict_court(e)}"
        for e in sorted(evals, key=lambda e: e["evaluateur"])
    )
    return GoldenEntry(
        **commun,
        statut="revue_requise",
        score=None,
        niveau=None,
        commentaire=f"désaccord double évaluation — {votes}",
    )


def evaluations_to_goldenset(
    evaluations: list[dict],
    *,
    prefixes: tuple[str, ...] = DEFAULT_PREFIXES,
    notateur: str = "export:media-eval",
) -> GoldenSet:
    """Transforme des dicts d'évaluations en `GoldenSet` — pur, testable.

    ``evaluations`` : {media_domaine, critere, statut, score, niveau,
    evaluateur, version_methodo?}. Plusieurs évaluations d'un même
    (média, critère) sont réconciliées en **consensus** (double évaluation) :
    accord → l'entrée est conservée ; désaccord → ``revue_requise`` documenté.
    """
    par_cle = _grouper_par_cle(evaluations, prefixes)
    entries = [_entry_consensus(evals) for evals in par_cle.values()]
    if not entries:
        return GoldenSet(notateur=notateur, note_at=None, entries=[])
    # La version du set = celle des entrées (portée par run ; défaut v1.2).
    return GoldenSet(
        notateur=notateur,
        note_at=None,
        entries=entries,
        version_methodo=entries[0].version_methodo,
    )


def accord_inter_evaluateurs(
    evaluations: list[dict], *, prefixes: tuple[str, ...] = DEFAULT_PREFIXES
) -> dict:
    """Accord entre évaluateurs indépendants (double évaluation) — pur.

    Ne considère que les (média, critère) notés par **≥ 2 évaluateurs
    distincts** (préfixes ``…@v1-a`` / ``…@v1-b``). Mesure la fréquence de
    convergence (même règle d'accord que le consensus d'export). Un désaccord
    ici est aussi celui qui bascule l'entrée en ``revue_requise``.
    """
    paires = [
        (media, critere, evals)
        for (media, critere), evals in _grouper_par_cle(evaluations, prefixes).items()
        if len({e["evaluateur"] for e in evals}) >= 2
    ]
    if not paires:
        return {"n": 0, "accord_inter": None, "desaccords": []}

    desaccords = []
    accords = 0
    for media, critere, evals in sorted(paires):
        if evaluateurs_accordent(evals):
            accords += 1
        else:
            desaccords.append(
                {
                    "media": media,
                    "critere": critere,
                    "verdicts": {e["evaluateur"]: _verdict_court(e) for e in evals},
                }
            )
    return {
        "n": len(paires),
        "accord_inter": round(accords / len(paires), 3),
        "accords": accords,
        "desaccords": desaccords,
    }


async def charger_evaluations(session, run_id: str) -> list[dict]:
    """Lit les évaluations d'un run (jointes au domaine média)."""
    rows = await session.execute(
        select(MediaEvalEvaluation, MediaEvalMedia.domaine)
        .join(MediaEvalMedia, MediaEvalMedia.id == MediaEvalEvaluation.media_id)
        .where(MediaEvalEvaluation.run_id == run_id)
    )
    resultats: list[dict] = []
    for ev, domaine in rows.all():
        resultats.append(
            {
                "media_domaine": domaine,
                "critere": ev.critere,
                "statut": ev.statut.value if hasattr(ev.statut, "value") else ev.statut,
                "score": ev.score,
                "niveau": ev.niveau,
                "evaluateur": ev.evaluateur,
                "version_methodo": ev.version_methodo,
            }
        )
    return resultats


async def run(run_id: str, out: Path, prefixes: tuple[str, ...]) -> int:
    async with async_session_maker() as session:
        try:
            evaluations = await charger_evaluations(session, run_id)
            if not evaluations:
                print(f"REJET : aucune évaluation pour le run {run_id!r}.")
                return 1
            goldenset = evaluations_to_goldenset(evaluations, prefixes=prefixes)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(goldenset.model_dump_json(indent=2) + "\n")
            print(f"Export : {len(goldenset.entries)} entrées → {out}")
            inter = accord_inter_evaluateurs(evaluations, prefixes=prefixes)
            if inter["n"]:
                print(
                    f"Accord inter-évaluateurs : {inter['accords']}/{inter['n']} "
                    f"({inter['accord_inter']:.0%}) sur les critères double évaluation"
                )
                for d in inter["desaccords"]:
                    print(f"  ⚠ {d['media']} · {d['critere']} : {d['verdicts']}")
            return 0
        except ValueError as exc:
            print(f"REJET : {exc}")
            return 1
        finally:
            await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--out", type=Path, required=True, help="JSON de sortie")
    parser.add_argument(
        "--evaluateur-prefixes",
        default=",".join(DEFAULT_PREFIXES),
        help="préfixes d'évaluateurs inclus (défaut 'agent:,code:')",
    )
    args = parser.parse_args()
    prefixes = tuple(p for p in args.evaluateur_prefixes.split(",") if p)
    # Lecture seule — get_settings garde le comportement usuel (DB courante).
    get_settings()
    sys.exit(asyncio.run(run(args.run_id, args.out, prefixes)))


if __name__ == "__main__":
    main()
