#!/usr/bin/env python3
"""Export des évaluations d'un run → JSON au schéma `GoldenSet` (lecture seule).

Sérialise les ``media_eval_evaluations`` d'un run dans le **même schéma** que
le golden set humain, ce qui permet de les comparer directement
(``evaluate_golden_agreement.py``). Le raccourci ``code:jti_shortcut`` est
inclus (préfixe ``code:``) au même titre que les évaluateurs agents.

Fonction pure ``evaluations_to_goldenset`` partagée avec ``rapport_pilote.py`` :
elle **lève** si deux évaluations existent pour un même (média, critère) après
filtrage — l'export doit être sans ambiguïté.

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


def evaluations_to_goldenset(
    evaluations: list[dict],
    *,
    prefixes: tuple[str, ...] = DEFAULT_PREFIXES,
    notateur: str = "export:media-eval",
) -> GoldenSet:
    """Transforme des dicts d'évaluations en `GoldenSet` — pur, testable.

    ``evaluations`` : {media_domaine, critere, statut, score, niveau,
    evaluateur}. Lève ``ValueError`` si deux évals subsistent pour un même
    (média, critère) après filtrage par préfixe d'évaluateur.
    """
    par_cle: dict[tuple[str, str], dict] = {}
    for ev in evaluations:
        if not any(ev["evaluateur"].startswith(p) for p in prefixes):
            continue
        cle = (ev["media_domaine"], ev["critere"])
        if cle in par_cle:
            raise ValueError(
                f"deux évaluations pour {cle} : {par_cle[cle]['evaluateur']!r} et "
                f"{ev['evaluateur']!r} — export ambigu."
            )
        par_cle[cle] = ev
    entries = [
        GoldenEntry(
            media_domaine=ev["media_domaine"],
            critere=ev["critere"],
            statut=ev["statut"],
            score=ev["score"],
            niveau=ev.get("niveau"),
        )
        for ev in par_cle.values()
    ]
    return GoldenSet(notateur=notateur, note_at=None, entries=entries)


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
