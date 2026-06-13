"""Compare deux annotateurs sur le même dataset (Story 7.4, Phase 2.B).

Cas d'usage principal : mesurer l'accord LLM↔PO sur les perspectives
PO-reviewed après un run `llm_annotate_titles.py --mode blind`. Le "left"
joue le rôle de gold, le "right" celui de prédiction.

Métriques :
- Span-level (intervalles fusionnés) : P / R / F1
- Token-lemma (lemmes spaCy chevauchant les spans) : P / R / F1
- Accord `weight` : MAE et Cohen κ sur les target spans matchés
- Accord `category` : matrice de confusion + accord brut
- Top N désaccords pour relecture humaine

Usage :
    python scripts/compare_annotations.py \\
        --dataset .context/highlight-dataset-llm-pass2-<date>.json \\
        --left po_synchronous --right llm_pass2 \\
        --filter po_reviewed=true \\
        --out .context/llm-vs-po-agreement-<date>.md
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.services.title_annotation_service import (  # noqa: E402
    get_title_annotation_service,
)
from scripts.evaluate_title_annotations import (  # noqa: E402
    _safe_div,
    _f1,
    fuse_spans,
    spans_overlap,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"


# ---------------------------------------------------------------------------
# Match spans LLM ↔ PO (overlap = matched pair)
# ---------------------------------------------------------------------------


def match_spans(
    gold: list[dict], pred: list[dict]
) -> tuple[list[tuple[dict, dict]], list[dict], list[dict]]:
    """Apparie gold ↔ pred par chevauchement (un-à-un, plus grand overlap d'abord).

    Retourne (paires, gold_non_matchés, pred_non_matchés).
    """
    pairs: list[tuple[dict, dict]] = []
    used_pred: set[int] = set()
    used_gold: set[int] = set()
    # Tri par overlap descendant
    candidates: list[tuple[int, int, int]] = []
    for gi, g in enumerate(gold):
        g_range = (g["start"], g["end"])
        for pi, p in enumerate(pred):
            p_range = (p["start"], p["end"])
            if spans_overlap(g_range, p_range):
                overlap = min(g["end"], p["end"]) - max(g["start"], p["start"])
                candidates.append((overlap, gi, pi))
    candidates.sort(reverse=True)
    for _, gi, pi in candidates:
        if gi in used_gold or pi in used_pred:
            continue
        pairs.append((gold[gi], pred[pi]))
        used_gold.add(gi)
        used_pred.add(pi)
    fn = [gold[i] for i in range(len(gold)) if i not in used_gold]
    fp = [pred[i] for i in range(len(pred)) if i not in used_pred]
    return pairs, fn, fp


# ---------------------------------------------------------------------------
# Cohen κ (catégoriel)
# ---------------------------------------------------------------------------


def cohen_kappa(pairs: list[tuple[str, str]]) -> float:
    """Cohen κ sur catégories discrètes — supporte input arbitraire."""
    if not pairs:
        return 0.0
    cats: set[str] = set()
    for a, b in pairs:
        cats.add(a)
        cats.add(b)
    n = len(pairs)
    p_observed = sum(1 for a, b in pairs if a == b) / n
    counts_a: Counter = Counter(a for a, _ in pairs)
    counts_b: Counter = Counter(b for _, b in pairs)
    p_expected = sum((counts_a[c] / n) * (counts_b[c] / n) for c in cats)
    if p_expected >= 1.0:
        return 1.0
    return (p_observed - p_expected) / (1.0 - p_expected)


# ---------------------------------------------------------------------------
# Per-perspective scoring
# ---------------------------------------------------------------------------


def score_perspective(
    title: str, gold_ann: dict, pred_ann: dict, svc=None
) -> dict:
    g_targets = gold_ann.get("target_spans") or []
    p_targets = pred_ann.get("target_spans") or []
    g_excludes = gold_ann.get("exclude_spans") or []
    p_excludes = pred_ann.get("exclude_spans") or []

    # --- Span-level (intervalles fusionnés)
    g_fused = set(fuse_spans(g_targets))
    p_fused = set(fuse_spans(p_targets))
    tp_span = sorted(g_fused & p_fused)
    fp_span = sorted(p_fused - g_fused)
    fn_span = sorted(g_fused - p_fused)

    # --- Token-lemma (chevauchements via spaCy)
    tp_tok: set[str] = set()
    fp_tok: set[str] = set()
    fn_tok: set[str] = set()
    if svc is not None and svc.is_nlp_available:
        tokens = svc.compute_strong_tokens(title)
        g_lemmas = {
            t["lemma"] for s in g_targets for t in tokens
            if spans_overlap((t["start"], t["end"]), (s["start"], s["end"]))
        }
        p_lemmas = {
            t["lemma"] for s in p_targets for t in tokens
            if spans_overlap((t["start"], t["end"]), (s["start"], s["end"]))
        }
        tp_tok = g_lemmas & p_lemmas
        fp_tok = p_lemmas - g_lemmas
        fn_tok = g_lemmas - p_lemmas

    # --- Matching pour accord weight/category
    target_pairs, target_fn, target_fp = match_spans(g_targets, p_targets)
    exclude_pairs, _, _ = match_spans(g_excludes, p_excludes)

    weight_diffs: list[tuple[float, float]] = []
    cat_target_pairs: list[tuple[str, str]] = []
    for g, p in target_pairs:
        weight_diffs.append((float(g.get("weight", 0)), float(p.get("weight", 0))))
        cat_target_pairs.append((g.get("category", "?"), p.get("category", "?")))
    cat_exclude_pairs = [
        (g.get("category", "?"), p.get("category", "?")) for g, p in exclude_pairs
    ]

    return {
        "title": title,
        "tp_span": tp_span, "fp_span": fp_span, "fn_span": fn_span,
        "tp_tok": tp_tok, "fp_tok": fp_tok, "fn_tok": fn_tok,
        "weight_diffs": weight_diffs,
        "cat_target_pairs": cat_target_pairs,
        "cat_exclude_pairs": cat_exclude_pairs,
        "disagreement_score": len(fp_span) + len(fn_span),
    }


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------


def aggregate(scores: list[dict]) -> dict:
    tp_span = sum(len(s["tp_span"]) for s in scores)
    fp_span = sum(len(s["fp_span"]) for s in scores)
    fn_span = sum(len(s["fn_span"]) for s in scores)
    p_span = _safe_div(tp_span, tp_span + fp_span)
    r_span = _safe_div(tp_span, tp_span + fn_span)
    f1_span = _f1(p_span, r_span)

    tp_tok = sum(len(s["tp_tok"]) for s in scores)
    fp_tok = sum(len(s["fp_tok"]) for s in scores)
    fn_tok = sum(len(s["fn_tok"]) for s in scores)
    p_tok = _safe_div(tp_tok, tp_tok + fp_tok)
    r_tok = _safe_div(tp_tok, tp_tok + fn_tok)
    f1_tok = _f1(p_tok, r_tok)

    weight_diffs = [d for s in scores for d in s["weight_diffs"]]
    if weight_diffs:
        mae = sum(abs(a - b) for a, b in weight_diffs) / len(weight_diffs)
        # κ catégoriel sur valeurs discrètes 0.25/0.5/1.0
        kappa_pairs = [(str(a), str(b)) for a, b in weight_diffs]
        kappa = cohen_kappa(kappa_pairs)
    else:
        mae = 0.0
        kappa = 0.0

    cat_target_pairs = [p for s in scores for p in s["cat_target_pairs"]]
    cat_exclude_pairs = [p for s in scores for p in s["cat_exclude_pairs"]]
    cat_target_kappa = cohen_kappa(cat_target_pairs)
    cat_exclude_kappa = cohen_kappa(cat_exclude_pairs)

    # Matrices de confusion
    confusion_target: dict[str, Counter] = defaultdict(Counter)
    for g, p in cat_target_pairs:
        confusion_target[g][p] += 1
    confusion_exclude: dict[str, Counter] = defaultdict(Counter)
    for g, p in cat_exclude_pairs:
        confusion_exclude[g][p] += 1

    return {
        "n_perspectives": len(scores),
        "span": {"tp": tp_span, "fp": fp_span, "fn": fn_span,
                 "precision": p_span, "recall": r_span, "f1": f1_span},
        "token": {"tp": tp_tok, "fp": fp_tok, "fn": fn_tok,
                  "precision": p_tok, "recall": r_tok, "f1": f1_tok},
        "weight_agreement": {
            "n": len(weight_diffs), "mae": mae, "cohen_kappa": kappa,
        },
        "category_target_kappa": cat_target_kappa,
        "category_exclude_kappa": cat_exclude_kappa,
        "confusion_target": {k: dict(v) for k, v in confusion_target.items()},
        "confusion_exclude": {k: dict(v) for k, v in confusion_exclude.items()},
    }


# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------


def render(
    metrics: dict, scores: list[dict], left: str, right: str, top_n: int = 10
) -> str:
    today = datetime.now(timezone.utc).date().isoformat()
    out = [
        f"# Accord `{left}` ↔ `{right}` ({today})",
        "",
        f"- Perspectives évaluées : {metrics['n_perspectives']}",
        f"- `{left}` = gold, `{right}` = prediction",
        "",
        "## Span-level (intervalles fusionnés)",
        "",
        f"- TP={metrics['span']['tp']} · FP={metrics['span']['fp']} · "
        f"FN={metrics['span']['fn']}",
        f"- P = {metrics['span']['precision']:.3f} · "
        f"R = {metrics['span']['recall']:.3f} · "
        f"**F1 = {metrics['span']['f1']:.3f}**",
        "",
        "## Token-lemma (chevauchement via spaCy)",
        "",
        f"- TP={metrics['token']['tp']} · FP={metrics['token']['fp']} · "
        f"FN={metrics['token']['fn']}",
        f"- P = {metrics['token']['precision']:.3f} · "
        f"R = {metrics['token']['recall']:.3f} · "
        f"**F1 = {metrics['token']['f1']:.3f}**",
        "",
        "## Accord `weight` (sur target_spans appariés)",
        "",
        f"- N spans matchés : {metrics['weight_agreement']['n']}",
        f"- MAE : {metrics['weight_agreement']['mae']:.3f}",
        f"- Cohen κ : {metrics['weight_agreement']['cohen_kappa']:.3f}",
        "",
        "## Accord `category`",
        "",
        f"- κ target : {metrics['category_target_kappa']:.3f}",
        f"- κ exclude : {metrics['category_exclude_kappa']:.3f}",
        "",
    ]

    # Top désaccords
    out.append(f"## Top {top_n} désaccords (FP+FN spans)")
    out.append("")
    sorted_scores = sorted(scores, key=lambda s: s["disagreement_score"], reverse=True)
    for s in sorted_scores[:top_n]:
        if s["disagreement_score"] == 0:
            break
        out.append(f"### {s['title']}")
        if s["fp_span"]:
            out.append(f"- FP (uniquement `{right}`) : " + ", ".join(
                f"[{a}:{b}]" for a, b in s["fp_span"]
            ))
        if s["fn_span"]:
            out.append(f"- FN (manquant dans `{right}`) : " + ", ".join(
                f"[{a}:{b}]" for a, b in s["fn_span"]
            ))
        out.append("")

    return "\n".join(out)


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def _matches_filter(ann: dict, filter_spec: str | None) -> bool:
    if not filter_spec:
        return True
    key, _, val = filter_spec.partition("=")
    actual = ann.get(key)
    if val.lower() in ("true", "false"):
        return bool(actual) == (val.lower() == "true")
    return str(actual) == val


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--left", default="po_synchronous",
                        help="Annotateur gold")
    parser.add_argument("--right", default="llm_pass2",
                        help="Annotateur prediction")
    parser.add_argument(
        "--filter",
        default=None,
        help="Filtre sur l'annotation gold (ex: po_reviewed=true)",
    )
    parser.add_argument("--out", default=None)
    parser.add_argument("--out-json", default=None)
    parser.add_argument("--top-n", type=int, default=10)
    parser.add_argument("--no-spacy", action="store_true",
                        help="Skip métriques token-lemma (utile en test sans spaCy)")
    args = parser.parse_args()

    dataset = json.loads(Path(args.dataset).read_text(encoding="utf-8"))
    svc = None
    if not args.no_spacy:
        svc = get_title_annotation_service()
        if not svc.is_nlp_available:
            print(
                "⚠️  spaCy indisponible — métriques token-lemma à 0. "
                "Ajoute --no-spacy pour acquitter explicitement.",
                file=sys.stderr,
            )

    scores: list[dict] = []
    for cluster in dataset["clusters"]:
        ref_id = cluster["reference_article_id"]
        for art in cluster["articles"]:
            if art["id"] == ref_id:
                continue
            ann = art.get("annotations") or {}
            if ann.get("dropped"):
                continue
            gold = ann.get(args.left)
            pred = ann.get(args.right)
            if not gold or not pred:
                continue
            if not _matches_filter(gold, args.filter):
                continue
            scores.append(score_perspective(art["title"], gold, pred, svc=svc))

    metrics = aggregate(scores)
    report = render(metrics, scores, args.left, args.right, top_n=args.top_n)

    today = datetime.now(timezone.utc).date().isoformat()
    out_md = Path(args.out) if args.out else (
        CONTEXT_DIR / f"llm-vs-po-agreement-{today}.md"
    )
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text(report, encoding="utf-8")

    out_json = Path(args.out_json) if args.out_json else (
        CONTEXT_DIR / f"llm-vs-po-agreement-{today}.json"
    )
    out_json.write_text(
        json.dumps(
            {
                "generated_at": datetime.now(timezone.utc).isoformat(),
                "dataset": args.dataset,
                "left": args.left, "right": args.right,
                "filter": args.filter,
                "metrics": metrics,
            },
            ensure_ascii=False, indent=2,
        ),
        encoding="utf-8",
    )

    print(f"✅ Rapport MD : {out_md}")
    print(f"✅ Rapport JSON : {out_json}")
    print()
    print(report)


if __name__ == "__main__":
    main()
