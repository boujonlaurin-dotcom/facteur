#!/usr/bin/env python3
"""Benchmark des évaluations LLM vs gold curé (Composant 1, étape 1c).

Calqué sur `evaluate_veille_curation.py` : charge le gold (sources curées,
éval connue) + un artefact d'évals **générées en aveugle** pour ces mêmes
sources, mesure l'accord, écrit json + md. Garde-fou de confiance AVANT apply.

Métriques :
  - `bias_stance` : **exact** + **adjacent** (axe ordinal gauche<->droite ;
    `alternative/specialized/unknown` hors-axe -> adjacent == exact).
  - `reliability_score` : **exact**.
  - scores FQS : **MAE** sur les paires où les deux valeurs existent.
  - table des désaccords.

Usage :
    cd packages/api
    python3 scripts/evaluate_source_evaluations.py \
        --gold .context/source_eval_targets.json \
        --generated .context/source_evaluations_gold_blind.json
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from scripts.source_eval_schema import BIAS_AXIS, EvaluationArtifact


def _adjacent(a: str, b: str) -> bool:
    if a == b:
        return True
    if a in BIAS_AXIS and b in BIAS_AXIS:
        return abs(BIAS_AXIS[a] - BIAS_AXIS[b]) <= 1
    return False  # hors-axe : pas d'adjacence


def evaluate(gold: list[dict], generated: EvaluationArtifact) -> dict:
    gen_by_id = {e.source_id: e for e in generated.evaluations}
    pairs = []
    for g in gold:
        ev = gen_by_id.get(g["source_id"])
        if ev is None:
            continue
        cur = g["current"]
        pairs.append((g["name"], cur, ev))

    n = len(pairs)
    if n == 0:
        return {"n": 0, "error": "aucune paire gold/généré"}

    bias_exact = sum(1 for _, c, e in pairs if e.bias_stance == c["bias_stance"])
    bias_adj = sum(1 for _, c, e in pairs if _adjacent(e.bias_stance, c["bias_stance"]))
    # reliability générée = DÉRIVÉE des scores (rubrique §2), pas la valeur LLM.
    rel_exact = sum(
        1 for _, c, e in pairs if e.derived_reliability() == c["reliability_score"]
    )

    mae: dict[str, float | None] = {}
    for col in ("score_independence", "score_rigor", "score_ux"):
        diffs = [
            abs(getattr(e, col) - c[col])
            for _, c, e in pairs
            if getattr(e, col) is not None and c[col] is not None
        ]
        mae[col] = round(sum(diffs) / len(diffs), 3) if diffs else None

    disagreements = [
        {
            "name": name,
            "gold_bias": c["bias_stance"],
            "gen_bias": e.bias_stance,
            "adjacent": _adjacent(e.bias_stance, c["bias_stance"]),
            "gold_rel": c["reliability_score"],
            "gen_rel": e.derived_reliability(),
            "confidence": e.confidence,
        }
        for name, c, e in pairs
        if e.bias_stance != c["bias_stance"]
        or e.derived_reliability() != c["reliability_score"]
    ]

    return {
        "n": n,
        "bias_exact": round(bias_exact / n, 3),
        "bias_adjacent": round(bias_adj / n, 3),
        "reliability_exact": round(rel_exact / n, 3),
        "score_mae": mae,
        "disagreements": disagreements,
    }


def render_md(report: dict) -> str:
    if report.get("n", 0) == 0:
        return f"# Benchmark éval sources\n\n{report.get('error', 'vide')}\n"
    lines = [
        "# Benchmark évaluations LLM vs gold",
        "",
        f"- Paires évaluées : **{report['n']}**",
        f"- bias_stance exact : **{report['bias_exact']:.0%}** | "
        f"adjacent : **{report['bias_adjacent']:.0%}**",
        f"- reliability_score exact : **{report['reliability_exact']:.0%}**",
        f"- MAE scores FQS : {report['score_mae']}",
        "",
        f"## Désaccords ({len(report['disagreements'])})",
        "",
        "| Source | gold bias | gen bias | adj | gold fiab | gen fiab | conf |",
        "|---|---|---|:-:|---|---|--:|",
    ]
    for d in report["disagreements"]:
        lines.append(
            f"| {d['name']} | {d['gold_bias']} | {d['gen_bias']} | "
            f"{'✓' if d['adjacent'] else '✗'} | {d['gold_rel']} | {d['gen_rel']} | "
            f"{d['confidence']:.2f} |"
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--gold", type=Path, required=True, help="source_eval_targets.json"
    )
    parser.add_argument(
        "--generated", type=Path, required=True, help="évals gold en aveugle"
    )
    args = parser.parse_args()

    gold = json.loads(args.gold.read_text()).get("gold", [])
    generated = EvaluationArtifact.model_validate_json(args.generated.read_text())
    report = evaluate(gold, generated)

    ts = datetime.now(UTC).strftime("%Y%m%d")
    ctx = Path(__file__).resolve().parents[3] / ".context"
    (ctx / f"source-eval-benchmark-{ts}.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False)
    )
    (ctx / f"source-eval-benchmark-{ts}.md").write_text(render_md(report))
    print(render_md(report))


if __name__ == "__main__":
    main()
