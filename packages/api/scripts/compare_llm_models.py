"""Compare deux runs LLM (ex: mistral-medium vs mistral-large) sur le même
gold dataset.

Produit un rapport markdown combinant :
- Tableau métriques medium-vs-PO, large-vs-PO et large-vs-medium
  (F1_span, F1_tok, accord weight κ + MAE, accord catégorie κ).
- Section qualitative : N titres sample, montrant côte-à-côte
  target_spans avec text + weight + category + justification pour
  chaque annotateur, plus le gold PO en référence.

Le picker qualitatif privilégie les titres où les deux modèles divergent
(soit en spans, soit en weight, soit en justification) — c'est là que
l'écart de qualité se voit le mieux.

Usage :
    cd packages/api && python scripts/compare_llm_models.py \\
        --medium ../../.context/highlight-dataset-llm-pass-3-2026-05-22.json \\
        --large  ../../.context/highlight-dataset-llm-pass-3-large-2026-05-22.json \\
        --out    ../../.context/llm-medium-vs-large-2026-05-22.md
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from scripts.compare_annotations import (  # noqa: E402
    aggregate,
    cohen_kappa,
    match_spans,
    score_perspective,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"


# ---------------------------------------------------------------------------
# Dataset merging
# ---------------------------------------------------------------------------


def merge_datasets(medium: dict, large: dict) -> dict:
    """Fusionne le slot llm_pass2 de chaque dataset en deux slots distincts
    `llm_pass2_medium` et `llm_pass2_large` dans le dataset medium (base)."""
    large_by_id: dict[str, dict] = {}
    for c in large["clusters"]:
        for art in c["articles"]:
            ann = (art.get("annotations") or {}).get("llm_pass2")
            if ann is not None:
                large_by_id[art["id"]] = ann

    merged = json.loads(json.dumps(medium))  # deep copy
    for c in merged["clusters"]:
        for art in c["articles"]:
            ann = art.get("annotations") or {}
            if "llm_pass2" in ann:
                ann["llm_pass2_medium"] = ann.pop("llm_pass2")
            if art["id"] in large_by_id:
                ann["llm_pass2_large"] = large_by_id[art["id"]]
    return merged


def collect_pairs(
    dataset: dict, left_key: str, right_key: str
) -> list[tuple[str, dict, dict, dict]]:
    """Yield (title, ref_title, left_ann, right_ann) pour les perspectives
    où les deux annotateurs sont présents et la perspective est PO-reviewed
    (filtre dur — on compare sur le gold uniquement)."""
    pairs: list[tuple[str, dict, dict, dict]] = []
    for c in dataset["clusters"]:
        ref_id = c["reference_article_id"]
        ref = next(a for a in c["articles"] if a["id"] == ref_id)
        for art in c["articles"]:
            if art["id"] == ref_id:
                continue
            ann = art.get("annotations") or {}
            if ann.get("dropped"):
                continue
            po = ann.get("po_synchronous") or {}
            if not po.get("po_reviewed"):
                continue
            left = ann.get(left_key)
            right = ann.get(right_key)
            if not left or not right:
                continue
            pairs.append((art["title"], ref["title"], left, right))
    return pairs


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------


def metrics_against(dataset: dict, llm_key: str) -> dict:
    """Calcule les métriques d'un annotateur LLM vs po_synchronous gold."""
    scores: list[dict] = []
    for c in dataset["clusters"]:
        ref_id = c["reference_article_id"]
        for art in c["articles"]:
            if art["id"] == ref_id:
                continue
            ann = art.get("annotations") or {}
            if ann.get("dropped"):
                continue
            po = ann.get("po_synchronous")
            llm = ann.get(llm_key)
            if not po or not llm:
                continue
            if not po.get("po_reviewed"):
                continue
            scores.append(score_perspective(art["title"], po, llm, svc=None))
    return aggregate(scores)


def metrics_llm_vs_llm(dataset: dict, left_key: str, right_key: str) -> dict:
    """Métriques croisées entre deux LLMs (sans gold PO)."""
    scores: list[dict] = []
    for c in dataset["clusters"]:
        ref_id = c["reference_article_id"]
        for art in c["articles"]:
            if art["id"] == ref_id:
                continue
            ann = art.get("annotations") or {}
            if ann.get("dropped"):
                continue
            left = ann.get(left_key)
            right = ann.get(right_key)
            if not left or not right:
                continue
            scores.append(score_perspective(art["title"], left, right, svc=None))
    return aggregate(scores)


# ---------------------------------------------------------------------------
# Qualitative picker
# ---------------------------------------------------------------------------


def _span_set(ann: dict) -> set[tuple[int, int]]:
    return {(s["start"], s["end"]) for s in (ann.get("target_spans") or [])}


def _disagreement_signal(
    medium: dict, large: dict, po: dict
) -> tuple[int, int]:
    """Retourne (n_total_disagreements, n_pure_LLM_diffs).

    Le premier sert au tri (cas globalement intéressants), le second
    privilégie les cas où medium et large divergent (le coeur de l'étude)."""
    m = _span_set(medium)
    L = _span_set(large)
    g = _span_set(po)
    total = len((m - g) | (g - m) | (L - g) | (g - L))
    llm_only = len((m - L) | (L - m))
    return total, llm_only


def pick_qualitative_samples(
    pairs: list[tuple[str, dict, dict, dict]],
    medium_anns: dict[str, dict],
    large_anns: dict[str, dict],
    po_anns: dict[str, dict],
    n: int = 12,
) -> list[tuple[str, dict, dict, dict]]:
    """Trie les titres par signal de désaccord LLM↔LLM décroissant.

    Retourne au plus n titres, en priorisant les cas où medium et large
    divergent — c'est là que l'écart de qualité saute aux yeux."""
    ranked: list[tuple[tuple[int, int], str, dict, dict, dict]] = []
    for title, ref_title, medium_ann, large_ann in pairs:
        po = po_anns[title]
        signal = _disagreement_signal(medium_ann, large_ann, po)
        # Tri prioritaire : (LLM-only diffs DESC, total diffs DESC)
        ranked.append(((-signal[1], -signal[0]), title, medium_ann, large_ann, po))
    ranked.sort(key=lambda r: r[0])
    return [(t, m, lg, po) for _, t, m, lg, po in ranked[:n]]


# ---------------------------------------------------------------------------
# Markdown rendering
# ---------------------------------------------------------------------------


def _format_target_spans(spans: list[dict], with_just: bool = True) -> str:
    if not spans:
        return "_(aucun)_"
    lines = []
    for s in spans:
        weight = s.get("weight")
        cat = s.get("category", "?")
        text = s.get("text", "")
        head = f"**{text!r}** · `{cat}`"
        if weight is not None:
            head += f" · weight={weight}"
        if with_just and s.get("justification"):
            head += f"  \n  _“{s['justification']}”_"
        lines.append(f"- {head}")
    return "\n".join(lines)


def _format_exclude_spans(spans: list[dict]) -> str:
    if not spans:
        return "_(aucun)_"
    return ", ".join(
        f"`{s.get('text','')}`/{s.get('category','?')}" for s in spans
    )


def render_metric_row(label: str, m: dict) -> str:
    return (
        f"| {label} | {m['span']['f1']:.3f} | {m['token']['f1']:.3f} | "
        f"{m['weight_agreement']['mae']:.3f} | "
        f"{m['weight_agreement']['cohen_kappa']:.3f} | "
        f"{m['category_target_kappa']:.3f} |"
    )


def render_report(
    medium_metrics: dict,
    large_metrics: dict,
    cross_metrics: dict,
    samples: list[tuple[str, dict, dict, dict]],
    n_pairs: int,
) -> str:
    today = datetime.now(timezone.utc).date().isoformat()
    out: list[str] = [
        f"# Comparaison Mistral-medium ↔ Mistral-large ({today})",
        "",
        f"- Perspectives PO-reviewed évaluées : {n_pairs}",
        "- Gold : `po_synchronous` (annotation PO synchrone).",
        "- Métriques : F1_span (intervalles fusionnés), F1_tok (lemmes "
        "chevauchant les spans, via spaCy), MAE et κ sur `weight` (sur "
        "target_spans appariés par overlap), κ sur `category` (target).",
        "",
        "## Métriques quantitatives",
        "",
        "| Annotateur | F1_span | F1_tok | MAE weight | κ weight | "
        "κ category |",
        "|---|---:|---:|---:|---:|---:|",
        render_metric_row("mistral-medium vs PO", medium_metrics),
        render_metric_row("mistral-large vs PO", large_metrics),
        render_metric_row("mistral-large vs mistral-medium", cross_metrics),
        "",
        "### Écart large ↔ medium (vs PO)",
        "",
        "| Métrique | medium | large | Δ |",
        "|---|---:|---:|---:|",
    ]
    for label, key, sub in [
        ("F1_span", "span", "f1"),
        ("F1_tok", "token", "f1"),
        ("MAE weight", "weight_agreement", "mae"),
        ("κ weight", "weight_agreement", "cohen_kappa"),
        ("κ category target", "category_target_kappa", None),
    ]:
        if sub is None:
            mv = medium_metrics[key]
            lv = large_metrics[key]
        else:
            mv = medium_metrics[key][sub]
            lv = large_metrics[key][sub]
        out.append(f"| {label} | {mv:.3f} | {lv:.3f} | {lv - mv:+.3f} |")

    out.extend(
        [
            "",
            "## Échantillon qualitatif",
            "",
            "Titres triés par désaccord LLM↔LLM décroissant — c'est là que "
            "l'écart entre medium et large se voit le mieux. Le gold PO "
            "est fourni en référence.",
            "",
        ]
    )

    for title, medium_ann, large_ann, po_ann in samples:
        out.append(f"### {title}")
        out.append("")
        out.append("**Gold PO :**")
        out.append(_format_target_spans(po_ann.get("target_spans") or [], with_just=False))
        if po_ann.get("notes"):
            out.append(f"  \n_Note PO :_ {po_ann['notes']}")
        out.append("")
        out.append("**mistral-medium :**")
        out.append(_format_target_spans(medium_ann.get("target_spans") or []))
        out.append(
            f"  \nExclude : { _format_exclude_spans(medium_ann.get('exclude_spans') or []) }"
        )
        if medium_ann.get("notes"):
            out.append(f"  \n_Note :_ {medium_ann['notes']}")
        out.append("")
        out.append("**mistral-large :**")
        out.append(_format_target_spans(large_ann.get("target_spans") or []))
        out.append(
            f"  \nExclude : { _format_exclude_spans(large_ann.get('exclude_spans') or []) }"
        )
        if large_ann.get("notes"):
            out.append(f"  \n_Note :_ {large_ann['notes']}")
        out.append("")

    return "\n".join(out)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--medium", required=True,
        help="Dataset annoté par mistral-medium (slot `llm_pass2`).",
    )
    parser.add_argument(
        "--large", required=True,
        help="Dataset annoté par mistral-large (slot `llm_pass2`).",
    )
    parser.add_argument(
        "--out", default=None,
        help="Chemin du rapport markdown (défaut : .context/llm-medium-vs-large-<date>.md)",
    )
    parser.add_argument(
        "--out-json", default=None,
        help="Chemin du dataset fusionné (utile pour audit) — optionnel.",
    )
    parser.add_argument(
        "--samples", type=int, default=12,
        help="Nombre de titres montrés en section qualitative.",
    )
    args = parser.parse_args()

    medium = json.loads(Path(args.medium).read_text(encoding="utf-8"))
    large = json.loads(Path(args.large).read_text(encoding="utf-8"))
    merged = merge_datasets(medium, large)

    # Index annotations par titre pour le picker qualitatif
    medium_by_title: dict[str, dict] = {}
    large_by_title: dict[str, dict] = {}
    po_by_title: dict[str, dict] = {}
    for c in merged["clusters"]:
        for art in c["articles"]:
            ann = art.get("annotations") or {}
            if "llm_pass2_medium" in ann:
                medium_by_title[art["title"]] = ann["llm_pass2_medium"]
            if "llm_pass2_large" in ann:
                large_by_title[art["title"]] = ann["llm_pass2_large"]
            if (ann.get("po_synchronous") or {}).get("po_reviewed"):
                po_by_title[art["title"]] = ann["po_synchronous"]

    pairs = collect_pairs(merged, "llm_pass2_medium", "llm_pass2_large")
    if not pairs:
        print("❌ Aucun titre commun aux deux runs LLM.", file=sys.stderr)
        sys.exit(2)

    medium_metrics = metrics_against(merged, "llm_pass2_medium")
    large_metrics = metrics_against(merged, "llm_pass2_large")
    cross_metrics = metrics_llm_vs_llm(merged, "llm_pass2_medium", "llm_pass2_large")
    samples = pick_qualitative_samples(
        pairs, medium_by_title, large_by_title, po_by_title, n=args.samples
    )

    report = render_report(
        medium_metrics, large_metrics, cross_metrics, samples, n_pairs=len(pairs)
    )

    today = datetime.now(timezone.utc).date().isoformat()
    out_md = (
        Path(args.out) if args.out else (CONTEXT_DIR / f"llm-medium-vs-large-{today}.md")
    )
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text(report, encoding="utf-8")
    print(f"✅ Rapport : {out_md}")

    if args.out_json:
        Path(args.out_json).write_text(
            json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"✅ Dataset fusionné : {args.out_json}")

    print()
    print(f"  medium vs PO : F1_span={medium_metrics['span']['f1']:.3f}")
    print(f"  large  vs PO : F1_span={large_metrics['span']['f1']:.3f}")
    print(
        f"  Δ F1_span (large - medium) = "
        f"{large_metrics['span']['f1'] - medium_metrics['span']['f1']:+.3f}"
    )


if __name__ == "__main__":
    main()
