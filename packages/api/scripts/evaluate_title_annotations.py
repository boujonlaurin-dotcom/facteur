"""Évaluateur data-driven de la pipeline `TitleAnnotationService`
(Story 7.4, suite — calibration).

Charge un dataset annoté (cf. `build_highlight_dataset.py` + annotation
PO/agent), lance la pipeline sur chaque cluster, et produit :

- Métriques precision/recall/F1 au niveau **token-lemma** et au niveau
  **span fusionné** (spans contigus collés en une unité).
- Catégorisation des erreurs : FP croisés avec `exclude_spans` du gold
  (FP_pivot_entity, FP_neutral_verb, FP_entity_alias…), FN tagués via
  `target_spans.category` (FN_editorial_angle, FN_multi_token_expression…).
- Top-N lemmes en FP et FN — utile pour inférer une whitelist/stopword
  *depuis les données*, pas l'intuition.

Le mode `--compare baseline.json after.json` charge deux runs précédents
et imprime le delta de métriques (utilisé par les PRs de calibration).

Usage :
    cd packages/api && source venv/bin/activate
    python scripts/evaluate_title_annotations.py \\
        --dataset .context/highlight-dataset-2026-05-19.json \\
        --tag baseline
    python scripts/evaluate_title_annotations.py \\
        --compare .context/highlight-baseline-2026-05-19.json \\
                  .context/highlight-after-iter1.json

Sorties :
    .context/highlight-<tag>-<date>.json   (machine, consommé par --compare)
    .context/highlight-<tag>-<date>.md     (lisible humain)
"""

import argparse
import json
import os
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.services.title_annotation_service import (  # noqa: E402
    TitleAnnotationService,
    get_title_annotation_service,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"


# ---------------------------------------------------------------------------
# Span helpers
# ---------------------------------------------------------------------------


def fuse_spans(spans: list[dict], gap: int = 1) -> list[tuple[int, int]]:
    """Fusionne les spans contigus (écart ≤ `gap` chars) en intervalles.

    Préserve l'ordre. Travaille sur (start, end) uniquement.
    """
    if not spans:
        return []
    sorted_spans = sorted(spans, key=lambda s: (s["start"], s["end"]))
    fused: list[tuple[int, int]] = []
    cur_s, cur_e = sorted_spans[0]["start"], sorted_spans[0]["end"]
    for s in sorted_spans[1:]:
        if s["start"] - cur_e <= gap:
            cur_e = max(cur_e, s["end"])
        else:
            fused.append((cur_s, cur_e))
            cur_s, cur_e = s["start"], s["end"]
    fused.append((cur_s, cur_e))
    return fused


def spans_overlap(a: tuple[int, int], b: tuple[int, int]) -> bool:
    return not (a[1] <= b[0] or b[1] <= a[0])


# ---------------------------------------------------------------------------
# Per-article evaluation
# ---------------------------------------------------------------------------


@dataclass
class ArticleScore:
    cluster_key: str
    article_id: str
    title: str
    tp_lemmas: set[str] = field(default_factory=set)
    fp_lemmas: set[str] = field(default_factory=set)
    fn_lemmas: set[str] = field(default_factory=set)
    # span-level (start, end) tuples after fusion
    tp_spans: list[tuple[int, int]] = field(default_factory=list)
    fp_spans: list[tuple[int, int]] = field(default_factory=list)
    fn_spans: list[tuple[int, int]] = field(default_factory=list)
    # error categories : {"FP_pivot_entity": [(span, lemma), ...]}
    fp_by_category: dict[str, list[tuple[tuple[int, int], str]]] = field(
        default_factory=lambda: defaultdict(list)
    )
    fn_by_category: dict[str, list[tuple[tuple[int, int], str]]] = field(
        default_factory=lambda: defaultdict(list)
    )


def _lemmas_in_range(
    tokens: list[dict], start: int, end: int
) -> list[str]:
    """Renvoie les lemmes des tokens qui chevauchent [start, end]."""
    return [
        t["lemma"]
        for t in tokens
        if spans_overlap((t["start"], t["end"]), (start, end))
    ]


def _categorize_fp(
    fp_span: tuple[int, int], exclude_spans: list[dict]
) -> str:
    for ex in exclude_spans:
        ex_range = (ex["start"], ex["end"])
        if spans_overlap(fp_span, ex_range):
            cat = ex.get("category") or "other"
            return f"FP_{cat}"
    return "FP_other"


def _categorize_fn(
    fn_span: tuple[int, int], target_spans: list[dict]
) -> str:
    for tg in target_spans:
        tg_range = (tg["start"], tg["end"])
        if spans_overlap(fn_span, tg_range):
            cat = tg.get("category") or "other"
            return f"FN_{cat}"
    return "FN_other"


def score_article(
    svc: TitleAnnotationService,
    cluster_key: str,
    article_id: str,
    alt_title: str,
    alt_tokens: list[dict],
    pred_spans: list[dict],
    target_spans: list[dict],
    exclude_spans: list[dict],
) -> ArticleScore:
    """Compare prédictions et gold pour un seul article (perspective).

    Token-level : ensemble des lemmes. Span-level : intervalles fusionnés.
    """
    score = ArticleScore(
        cluster_key=cluster_key, article_id=article_id, title=alt_title
    )

    pred_lemmas = {
        s["text"].lower(): s
        for s in pred_spans
    }
    # On préfère matcher sur les lemmes calculés par le service côté pred.
    # Pour les gold, on retrouve les lemmes via la tokenisation du titre.
    pred_lemma_set: set[str] = set()
    pred_span_to_lemma: dict[tuple[int, int], str] = {}
    for s in pred_spans:
        lemmas = _lemmas_in_range(alt_tokens, s["start"], s["end"])
        if lemmas:
            pred_lemma_set.update(lemmas)
            pred_span_to_lemma[(s["start"], s["end"])] = lemmas[0]

    gold_lemma_set: set[str] = set()
    gold_span_to_lemma: dict[tuple[int, int], str] = {}
    for s in target_spans:
        lemmas = _lemmas_in_range(alt_tokens, s["start"], s["end"])
        for lemma in lemmas:
            gold_lemma_set.add(lemma)
            gold_span_to_lemma.setdefault((s["start"], s["end"]), lemma)

    score.tp_lemmas = pred_lemma_set & gold_lemma_set
    score.fp_lemmas = pred_lemma_set - gold_lemma_set
    score.fn_lemmas = gold_lemma_set - pred_lemma_set

    # Span-level (intervalles fusionnés, match exact)
    pred_fused = fuse_spans(pred_spans)
    gold_fused = fuse_spans(target_spans)
    pred_set = set(pred_fused)
    gold_set = set(gold_fused)
    score.tp_spans = sorted(pred_set & gold_set)
    score.fp_spans = sorted(pred_set - gold_set)
    score.fn_spans = sorted(gold_set - pred_set)

    # Catégorisation : à partir des spans en erreur, plus parlant que les lemmes
    for fp_span in score.fp_spans:
        cat = _categorize_fp(fp_span, exclude_spans)
        lemma = pred_span_to_lemma.get(fp_span, "?")
        score.fp_by_category[cat].append((fp_span, lemma))
    for fn_span in score.fn_spans:
        cat = _categorize_fn(fn_span, target_spans)
        lemma = gold_span_to_lemma.get(fn_span, "?")
        score.fn_by_category[cat].append((fn_span, lemma))

    return score


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------


def _safe_div(num: float, denom: float) -> float:
    return num / denom if denom else 0.0


def _f1(precision: float, recall: float) -> float:
    return _safe_div(2 * precision * recall, precision + recall)


def aggregate(scores: list[ArticleScore]) -> dict:
    tp_tok = sum(len(s.tp_lemmas) for s in scores)
    fp_tok = sum(len(s.fp_lemmas) for s in scores)
    fn_tok = sum(len(s.fn_lemmas) for s in scores)
    p_tok = _safe_div(tp_tok, tp_tok + fp_tok)
    r_tok = _safe_div(tp_tok, tp_tok + fn_tok)

    tp_span = sum(len(s.tp_spans) for s in scores)
    fp_span = sum(len(s.fp_spans) for s in scores)
    fn_span = sum(len(s.fn_spans) for s in scores)
    p_span = _safe_div(tp_span, tp_span + fp_span)
    r_span = _safe_div(tp_span, tp_span + fn_span)

    fp_cats: Counter = Counter()
    fn_cats: Counter = Counter()
    fp_lemma_counter: Counter = Counter()
    fn_lemma_counter: Counter = Counter()
    for s in scores:
        for cat, errs in s.fp_by_category.items():
            fp_cats[cat] += len(errs)
            for _, lemma in errs:
                fp_lemma_counter[lemma] += 1
        for cat, errs in s.fn_by_category.items():
            fn_cats[cat] += len(errs)
            for _, lemma in errs:
                fn_lemma_counter[lemma] += 1

    return {
        "n_perspectives": len(scores),
        "token": {
            "tp": tp_tok, "fp": fp_tok, "fn": fn_tok,
            "precision": p_tok, "recall": r_tok, "f1": _f1(p_tok, r_tok),
        },
        "span": {
            "tp": tp_span, "fp": fp_span, "fn": fn_span,
            "precision": p_span, "recall": r_span, "f1": _f1(p_span, r_span),
        },
        "fp_categories": dict(fp_cats.most_common()),
        "fn_categories": dict(fn_cats.most_common()),
        "top_fp_lemmas": fp_lemma_counter.most_common(30),
        "top_fn_lemmas": fn_lemma_counter.most_common(30),
    }


# ---------------------------------------------------------------------------
# Prediction & evaluation runner
# ---------------------------------------------------------------------------


def load_dataset(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def evaluate_dataset(
    dataset: dict,
    svc: TitleAnnotationService,
    annotator: str,
) -> list[ArticleScore]:
    """Lance la pipeline sur chaque perspective et compare aux annotations."""
    scores: list[ArticleScore] = []
    for cluster in dataset["clusters"]:
        articles = cluster["articles"]
        ref_id = cluster["reference_article_id"]
        ref = next(a for a in articles if a["id"] == ref_id)

        titles = [a["title"] for a in articles]
        # Sync path: pas asyncio nécessaire pour un script CLI sur N petits batchs.
        tokens_list = [svc.compute_strong_tokens(t) for t in titles]
        tokens_by_id = {a["id"]: tokens_list[i] for i, a in enumerate(articles)}
        ref_tokens = tokens_by_id[ref_id]

        for art in articles:
            if art["id"] == ref_id:
                continue
            if (art.get("annotations") or {}).get("dropped"):
                # Perspective marquée comme à exclure (ex : mauvais clustering)
                continue
            ann = (art.get("annotations") or {}).get(annotator)
            if not ann:
                # Pas annoté → on saute pour ne pas pourrir les métriques
                continue
            pred_spans = svc.diff_spans(
                ref_tokens, tokens_by_id[art["id"]], art.get("bias_stance", "unknown")
            )
            scores.append(
                score_article(
                    svc=svc,
                    cluster_key=cluster["cluster_key"],
                    article_id=art["id"],
                    alt_title=art["title"],
                    alt_tokens=tokens_by_id[art["id"]],
                    pred_spans=pred_spans,
                    target_spans=ann.get("target_spans") or [],
                    exclude_spans=ann.get("exclude_spans") or [],
                )
            )
    return scores


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def format_metric_block(metrics: dict, label: str) -> list[str]:
    out = [f"### {label}"]
    tok = metrics["token"]
    span = metrics["span"]
    out.append(
        f"- **Token-lemma** : P = {tok['precision']:.3f} · R = {tok['recall']:.3f} · "
        f"F1 = {tok['f1']:.3f}  (TP={tok['tp']} FP={tok['fp']} FN={tok['fn']})"
    )
    out.append(
        f"- **Span fusionné** : P = {span['precision']:.3f} · R = {span['recall']:.3f} · "
        f"F1 = {span['f1']:.3f}  (TP={span['tp']} FP={span['fp']} FN={span['fn']})"
    )
    if metrics["fp_categories"]:
        out.append("- **FP par catégorie** :")
        for cat, n in metrics["fp_categories"].items():
            out.append(f"  - {cat}: {n}")
    if metrics["fn_categories"]:
        out.append("- **FN par catégorie** :")
        for cat, n in metrics["fn_categories"].items():
            out.append(f"  - {cat}: {n}")
    if metrics["top_fp_lemmas"]:
        out.append("- **Top FP lemmes** : " + ", ".join(
            f"{lemma}({n})" for lemma, n in metrics["top_fp_lemmas"][:15]
        ))
    if metrics["top_fn_lemmas"]:
        out.append("- **Top FN lemmes** : " + ", ".join(
            f"{lemma}({n})" for lemma, n in metrics["top_fn_lemmas"][:15]
        ))
    return out


def render_report(
    metrics: dict, dataset_path: Path, model_version: str, tag: str
) -> str:
    today = datetime.now(timezone.utc).date().isoformat()
    out = [
        f"# Évaluation highlighting — `{tag}` ({today})",
        "",
        f"- Dataset : `{dataset_path.name}`",
        f"- Pipeline : `{model_version}`",
        f"- Perspectives évaluées : {metrics['n_perspectives']}",
        "",
    ]
    out.extend(format_metric_block(metrics, "Métriques globales"))
    out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Compare mode
# ---------------------------------------------------------------------------


def render_compare(baseline: dict, after: dict) -> str:
    def d(metric_path: list[str]) -> float:
        a = after
        b = baseline
        for k in metric_path:
            a = a[k]
            b = b[k]
        return a - b

    lines = [
        "# Comparaison baseline ↔ after",
        "",
        f"Perspectives baseline = {baseline['n_perspectives']} · "
        f"after = {after['n_perspectives']}",
        "",
        "| Niveau | Métrique | baseline | after | Δ |",
        "|--------|----------|----------|-------|---|",
    ]
    for level in ("token", "span"):
        for metric in ("precision", "recall", "f1"):
            b = baseline[level][metric]
            a = after[level][metric]
            lines.append(
                f"| {level} | {metric} | {b:.3f} | {a:.3f} | {a-b:+.3f} |"
            )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", help="Dataset annoté (mode évaluation)")
    parser.add_argument(
        "--annotator",
        default="po_synchronous",
        help="Source d'annotation à scorer (po_synchronous / agent_mirror)",
    )
    parser.add_argument(
        "--tag",
        default="baseline",
        help="Nom de l'itération (intégré aux noms de fichiers de sortie)",
    )
    parser.add_argument(
        "--compare",
        nargs=2,
        metavar=("BASELINE", "AFTER"),
        help="Mode comparaison : 2 chemins JSON produits par ce script",
    )
    parser.add_argument("--out-json", default=None)
    parser.add_argument("--out-md", default=None)
    args = parser.parse_args()

    if args.compare:
        baseline = json.loads(Path(args.compare[0]).read_text(encoding="utf-8"))
        after = json.loads(Path(args.compare[1]).read_text(encoding="utf-8"))
        report = render_compare(baseline["metrics"], after["metrics"])
        print(report)
        return

    if not args.dataset:
        parser.error("--dataset requis (sauf en mode --compare)")

    dataset_path = Path(args.dataset)
    dataset = load_dataset(dataset_path)
    svc = get_title_annotation_service()
    if not svc.is_nlp_available:
        print(
            "❌ spaCy fr_core_news_md indisponible. "
            "Installe : pip install spacy==3.8.11 "
            "&& python -m spacy download fr_core_news_md",
            file=sys.stderr,
        )
        sys.exit(2)

    scores = evaluate_dataset(dataset, svc, args.annotator)
    metrics = aggregate(scores)

    today = datetime.now(timezone.utc).date().isoformat()
    out_json = Path(
        args.out_json or CONTEXT_DIR / f"highlight-{args.tag}-{today}.json"
    )
    out_md = Path(
        args.out_md or CONTEXT_DIR / f"highlight-{args.tag}-{today}.md"
    )
    out_json.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "dataset": dataset_path.name,
        "annotator": args.annotator,
        "tag": args.tag,
        "model_version": svc.MODEL_VERSION,
        "metrics": metrics,
    }
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    out_md.write_text(
        render_report(metrics, dataset_path, svc.MODEL_VERSION, args.tag),
        encoding="utf-8",
    )

    print(f"✅ Résultats : {out_json}")
    print(f"✅ Rapport   : {out_md}")
    print()
    print(render_report(metrics, dataset_path, svc.MODEL_VERSION, args.tag))


if __name__ == "__main__":
    main()
