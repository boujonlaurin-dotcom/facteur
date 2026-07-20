#!/usr/bin/env python3
"""Accord évaluations agents vs golden set humain — benchmark V0.

Calqué sur `scripts/evaluate_source_evaluations.py` : charge le gold
(`docs/media-eval/golden/gold_v0.json`, notation Laurin) + un export
d'évaluations générées (même schéma `GoldenSet`), mesure l'accord, écrit
json + md dans `.context/`.

Métriques (critères de succès V0 §2) :
- C9 / C11 : accord **exact** sur le niveau ;
- C1 / C5 / C7 / C8 : accord si **|Δ| ≤ 20 % du barème** du critère ;
- désaccords **N/A-vs-score** listés à part (aucun ne doit rester inexpliqué) ;
- MAE sur les paires scorées des deux côtés.

Usage :
    cd packages/api
    python3 scripts/media_eval/evaluate_golden_agreement.py \
        --gold ../../docs/media-eval/golden/gold_v0.json \
        --generated .context/media_eval/pilote-2026-07/evaluations_export.json
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.media_eval.schemas import (
    GoldenEntry,
    GoldenSet,
    grille,
)

TOLERANCE_CONTINUE = 0.20  # |Δ| ≤ 20 % du barème (critère de succès V0)


def _paire_accord(gold: GoldenEntry, gen: GoldenEntry) -> dict:
    """Compare une paire (média, critère). Pur, testable.

    La grille (critères à niveaux, barèmes) est résolue depuis la version du
    gold : un run v1.3 se compare avec les paliers v1.3 (C2..C7 à niveaux).
    """
    critere = gold.critere
    g = grille(gold.version_methodo)
    resultat: dict = {
        "media": gold.media_domaine,
        "critere": critere,
        "gold_statut": gold.statut,
        "gen_statut": gen.statut,
        "gold_score": gold.score,
        "gen_score": gen.score,
        "gold_niveau": gold.niveau,
        "gen_niveau": gen.niveau,
    }
    if (gold.statut == "evaluee") != (gen.statut == "evaluee"):
        resultat |= {"accord": False, "type_desaccord": "na_vs_score", "delta": None}
        return resultat
    if gold.statut != "evaluee":
        # N/A ou revue_requise des deux côtés : accord si même statut.
        accord = gold.statut == gen.statut
        resultat |= {
            "accord": accord,
            "type_desaccord": None if accord else "statut",
            "delta": None,
        }
        return resultat
    if critere in g.criteres_niveaux:
        accord = gold.niveau == gen.niveau
        resultat |= {
            "accord": accord,
            "type_desaccord": None if accord else "niveau",
            "delta": abs((gold.score or 0) - (gen.score or 0)),
        }
        return resultat
    delta = abs((gold.score or 0) - (gen.score or 0))
    accord = delta <= TOLERANCE_CONTINUE * g.baremes[critere]
    resultat |= {
        "accord": accord,
        "type_desaccord": None if accord else "score",
        "delta": delta,
    }
    return resultat


def evaluate(gold: GoldenSet, generated: GoldenSet) -> dict:
    gen_par_cle = {(e.media_domaine, e.critere): e for e in generated.entries}
    paires = [
        (g, gen_par_cle[(g.media_domaine, g.critere)])
        for g in gold.entries
        if (g.media_domaine, g.critere) in gen_par_cle
    ]
    if not paires:
        return {"n": 0, "error": "aucune paire gold/généré"}

    resultats = [_paire_accord(g, gen) for g, gen in paires]
    par_media: dict[str, dict] = {}
    for r in resultats:
        stats = par_media.setdefault(r["media"], {"accords": 0, "total": 0})
        stats["total"] += 1
        stats["accords"] += int(r["accord"])

    deltas = [r["delta"] for r in resultats if r["delta"] is not None]
    desaccords = sorted(
        (r for r in resultats if not r["accord"]),
        key=lambda r: (r["type_desaccord"] != "na_vs_score", -(r["delta"] or 0)),
    )
    return {
        "n": len(resultats),
        "accord_global": round(sum(r["accord"] for r in resultats) / len(resultats), 3),
        "par_media": {
            m: f"{s['accords']}/{s['total']}" for m, s in sorted(par_media.items())
        },
        "na_vs_score": sum(
            1 for r in resultats if r["type_desaccord"] == "na_vs_score"
        ),
        "mae_scores": round(sum(deltas) / len(deltas), 2) if deltas else None,
        "desaccords": desaccords,
    }


def render_md(report: dict) -> str:
    if report.get("n", 0) == 0:
        return f"# Accord media-eval vs gold\n\n{report.get('error', 'vide')}\n"
    lignes = [
        "# Accord évaluations agents vs golden set",
        "",
        f"- Paires évaluées : **{report['n']}**",
        f"- Accord global : **{report['accord_global']:.0%}**"
        f" (cible V0 : ≥ 4 critères / 6 par média)",
        f"- Par média : {report['par_media']}",
        f"- Désaccords N/A-vs-score : **{report['na_vs_score']}** (cible : 0 inexpliqué)",
        f"- MAE scores : {report['mae_scores']}",
        "",
        f"## Désaccords ({len(report['desaccords'])})",
        "",
        "| Média | Critère | Type | Gold | Généré | Δ |",
        "|---|---|---|---|---|--:|",
    ]
    for d in report["desaccords"]:
        gold = (
            f"niv {d['gold_niveau']}"
            if d["gold_niveau"] is not None
            else (
                d["gold_score"] if d["gold_statut"] == "evaluee" else d["gold_statut"]
            )
        )
        gen = (
            f"niv {d['gen_niveau']}"
            if d["gen_niveau"] is not None
            else (d["gen_score"] if d["gen_statut"] == "evaluee" else d["gen_statut"])
        )
        lignes.append(
            f"| {d['media']} | {d['critere']} | {d['type_desaccord']} | "
            f"{gold} | {gen} | {d['delta'] if d['delta'] is not None else '-'} |"
        )
    return "\n".join(lignes) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gold", type=Path, required=True, help="gold_v0.json")
    parser.add_argument(
        "--generated",
        type=Path,
        required=True,
        help="export évals générées (même schéma)",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path(__file__).resolve().parents[4] / ".context",
        help="dossier de sortie (défaut .context ; docs/media-eval/rapports "
        "pour un livrable commité)",
    )
    parser.add_argument(
        "--slug",
        default=None,
        help="suffixe de fichier (défaut : date du jour, ex. 20260710)",
    )
    args = parser.parse_args()

    gold = GoldenSet.model_validate_json(args.gold.read_text())
    generated = GoldenSet.model_validate_json(args.generated.read_text())
    report = evaluate(gold, generated)

    slug = args.slug or datetime.now(UTC).strftime("%Y%m%d")
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"media-eval-accord-{slug}.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False)
    )
    (out_dir / f"media-eval-accord-{slug}.md").write_text(render_md(report))
    print(render_md(report))


if __name__ == "__main__":
    main()
