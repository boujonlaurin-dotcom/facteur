"""Évaluateur de la *porte de cohérence sujet* des perspectives
(`PerspectiveService._is_topically_coherent`) contre un gold « appartenance
à un événement » (cf. `docs/maintenance/maintenance-clustering-calibration.md`).

Le harness importe les **vraies** fonctions de la porte (pas de
réimplémentation) et rejoue, pour chaque pool, **toutes les paires ordonnées**
seed↔candidat — la porte est asymétrique : n'importe quel article peut ouvrir
l'écran « couverture médiatique ». Il mesure :

- Pairwise **précision / rappel / F1** (micro + macro par pool ; NOISE jamais
  positif).
- **Contamination par seed** : % d'articles hors-événement admis dans le
  cluster prédit (moyenne + pires offenders).
- **FP par chemin d'acceptation** : `strong_jaccard` / `double_entity` /
  `weak_double_signal` (la fuite). Attendu : majorité des FP en
  `weak_double_signal`.
- **FN par signal manquant** : `low_jaccard` / `jaccard_below_floor` /
  `no_shared_topic` / `no_shared_entity` → révèle le gap des paraphrases.
- **Couverture des signaux** : fraction de paires `full_signals` vs jaccard-seul.

`--sweep` balaie `PERSPECTIVE_MIN_JACCARD_FLOOR` (et l'option « exiger
`shared_entities ≥ 2` partout ») pour exposer le tradeoff précision/rappel.

Hors-périmètre **déterministe** : Layer 2/3 (Google News) génère des candidats
mais ne porte ni topics ni entities — on mesure la *porte*, pas la génération.

Usage :
    cd packages/api && source venv/bin/activate
    python scripts/evaluate_event_clustering.py \\
        --dataset ../../.context/gold-events-2026-06-09.json --tag baseline
    python scripts/evaluate_event_clustering.py \\
        --dataset ../../.context/gold-events-2026-06-09.json --sweep
    python scripts/evaluate_event_clustering.py --compare \\
        ../../.context/gold-events-baseline-2026-06-09.json \\
        ../../.context/gold-events-iter1-2026-06-09.json

Sorties :
    .context/gold-events-<tag>-<date>.json  (machine, consommé par --compare)
    .context/gold-events-<tag>-<date>.md    (lisible humain)
"""

import argparse
import json
import os
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.services.perspective_service import (  # noqa: E402
    PERSPECTIVE_DISCRIMINANT_ENTITY_TYPES,
    PERSPECTIVE_MIN_JACCARD_FLOOR,
    PERSPECTIVE_TITLE_JACCARD_MIN,
    PerspectiveService,
    _parse_entity_names,
)
from app.services.text_similarity import normalize_title  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

NOISE_EVENT_ID = "NOISE"

# Valeurs balayées par défaut en mode --sweep.
DEFAULT_FLOOR_SWEEP = [0.08, 0.12, 0.15, 0.20, 0.25]


# ---------------------------------------------------------------------------
# Réplique paramétrable de la porte — anti-drift garanti par les tests
# ---------------------------------------------------------------------------


def gate_pair(
    signals: dict,
    floor: float = PERSPECTIVE_MIN_JACCARD_FLOOR,
    require_double_entity: bool = False,
) -> tuple[bool, str]:
    """Réplique de `_is_topically_coherent` avec floor + option configurables.

    Avec les valeurs par défaut (`floor=PERSPECTIVE_MIN_JACCARD_FLOOR`,
    `require_double_entity=False`), DOIT être identique octet pour octet à
    `PerspectiveService._is_topically_coherent` — c'est ce que vérifie le test
    anti-drift `test_gate_pair_matches_real_gate`. Les paramètres servent
    uniquement au `--sweep` (Iter 1) :
      - `floor` : durcit le Jaccard minimal de la branche « weak double signal ».
      - `require_double_entity` : désactive la branche faible (exige ≥2 entités
        discriminantes partout).
    """
    if signals["title_jaccard"] >= PERSPECTIVE_TITLE_JACCARD_MIN:
        return True, ""
    full_signals = (
        signals["shared_topics"] is not None
        and signals["shared_entities"] is not None
    )
    if full_signals:
        if signals["shared_entities"] and signals["shared_entities"] >= 2:
            return True, ""
        if require_double_entity:
            return False, "no_signal"
        if signals["title_jaccard"] >= floor:
            topic_ok = bool(signals["shared_topics"] and signals["shared_topics"] >= 1)
            entity_ok = bool(
                signals["shared_entities"] and signals["shared_entities"] >= 1
            )
            if topic_ok and entity_ok:
                return True, ""
        return False, "no_signal"
    return False, "low_jaccard"


def classify_accept_path(signals: dict) -> str | None:
    """Chemin de la porte RÉELLE qui accepte cette paire (None si rejetée).

    Sert à l'attribution des FP. Doit s'accorder avec
    `_is_topically_coherent` (test anti-drift).
    """
    if signals["title_jaccard"] >= PERSPECTIVE_TITLE_JACCARD_MIN:
        return "strong_jaccard"
    full_signals = (
        signals["shared_topics"] is not None
        and signals["shared_entities"] is not None
    )
    if full_signals:
        if signals["shared_entities"] and signals["shared_entities"] >= 2:
            return "double_entity"
        if signals["title_jaccard"] >= PERSPECTIVE_MIN_JACCARD_FLOOR:
            topic_ok = bool(signals["shared_topics"] and signals["shared_topics"] >= 1)
            entity_ok = bool(
                signals["shared_entities"] and signals["shared_entities"] >= 1
            )
            if topic_ok and entity_ok:
                return "weak_double_signal"
    return None


def classify_reject_reason(signals: dict) -> str | None:
    """Raison du rejet d'une paire (attribution des FN). None si acceptée.

    - `low_jaccard`        : signaux incomplets (Layer 2/3) + Jaccard < seuil fort.
    - `jaccard_below_floor`: full_signals, mais Jaccard sous le floor de la
      branche faible (le gap des paraphrases : titres reformulés → Jaccard ~0).
    - `no_shared_topic`    : full_signals, Jaccard ≥ floor, mais 0 topic partagé.
    - `no_shared_entity`   : idem, 0 entité discriminante partagée.
    """
    if classify_accept_path(signals) is not None:
        return None
    full_signals = (
        signals["shared_topics"] is not None
        and signals["shared_entities"] is not None
    )
    if not full_signals:
        return "low_jaccard"
    if signals["title_jaccard"] < PERSPECTIVE_MIN_JACCARD_FLOOR:
        return "jaccard_below_floor"
    if not (signals["shared_topics"] and signals["shared_topics"] >= 1):
        return "no_shared_topic"
    if not (signals["shared_entities"] and signals["shared_entities"] >= 1):
        return "no_shared_entity"
    return "no_signal"


# ---------------------------------------------------------------------------
# Modèle de données
# ---------------------------------------------------------------------------


@dataclass
class GoldArticle:
    id: str
    title: str
    topics: list[str]
    entities: list[str]
    event_id: str

    # Pré-calcul des primitives seed (mêmes formules que le call-site).
    def seed_tokens(self) -> set[str]:
        return normalize_title(self.title)

    def seed_topics(self) -> set[str]:
        return {t.lower() for t in (self.topics or []) if t}

    def seed_disc_entities(self) -> set[str]:
        return set(
            _parse_entity_names(
                self.entities, types=PERSPECTIVE_DISCRIMINANT_ENTITY_TYPES
            )
        )


def load_dataset(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _pool_articles(pool: dict) -> list[GoldArticle]:
    return [
        GoldArticle(
            id=str(a["id"]),
            title=a.get("title") or "",
            topics=list(a.get("topics") or []),
            entities=list(a.get("entities") or []),
            event_id=(a.get("event_id") or NOISE_EVENT_ID),
        )
        for a in pool["articles"]
    ]


# ---------------------------------------------------------------------------
# Évaluation pairwise
# ---------------------------------------------------------------------------


@dataclass
class PairResult:
    pool_key: str
    seed_id: str
    cand_id: str
    predicted_same: bool
    gold_same: bool
    accept_path: str | None  # si prédit positif
    reject_reason: str | None  # si prédit négatif
    full_signals: bool


@dataclass
class PoolScore:
    pool_key: str
    n_articles: int
    tp: int = 0
    fp: int = 0
    fn: int = 0
    tn: int = 0
    # contamination : par seed, off_event_admitted / total_admitted
    contamination: list[tuple[str, float]] = field(default_factory=list)

    @property
    def precision(self) -> float:
        return _safe_div(self.tp, self.tp + self.fp)

    @property
    def recall(self) -> float:
        return _safe_div(self.tp, self.tp + self.fn)

    @property
    def f1(self) -> float:
        return _f1(self.precision, self.recall)


def _gold_same(seed: GoldArticle, cand: GoldArticle) -> bool:
    return seed.event_id == cand.event_id and seed.event_id != NOISE_EVENT_ID


def evaluate_pool(
    pool: dict,
    floor: float = PERSPECTIVE_MIN_JACCARD_FLOOR,
    require_double_entity: bool = False,
) -> tuple[PoolScore, list[PairResult]]:
    """Rejoue la porte sur toutes les paires ordonnées (seed≠cand) d'un pool."""
    articles = _pool_articles(pool)
    pool_key = pool.get("pool_key", "?")
    score = PoolScore(pool_key=pool_key, n_articles=len(articles))
    results: list[PairResult] = []

    for seed in articles:
        seed_tokens = seed.seed_tokens()
        seed_topics = seed.seed_topics()
        seed_disc = seed.seed_disc_entities()
        admitted = 0
        admitted_off = 0
        for cand in articles:
            if cand.id == seed.id:
                continue
            signals = PerspectiveService._topical_signals(
                seed_tokens,
                seed_topics,
                seed_disc,
                cand_title=cand.title,
                cand_topics=cand.topics,
                cand_entities=cand.entities,
            )
            predicted_same, _ = gate_pair(
                signals, floor=floor, require_double_entity=require_double_entity
            )
            gold = _gold_same(seed, cand)
            full = (
                signals["shared_topics"] is not None
                and signals["shared_entities"] is not None
            )
            accept_path = classify_accept_path(signals) if predicted_same else None
            reject_reason = (
                classify_reject_reason(signals) if not predicted_same else None
            )
            results.append(
                PairResult(
                    pool_key=pool_key,
                    seed_id=seed.id,
                    cand_id=cand.id,
                    predicted_same=predicted_same,
                    gold_same=gold,
                    accept_path=accept_path,
                    reject_reason=reject_reason,
                    full_signals=full,
                )
            )
            if predicted_same and gold:
                score.tp += 1
            elif predicted_same and not gold:
                score.fp += 1
            elif not predicted_same and gold:
                score.fn += 1
            else:
                score.tn += 1
            if predicted_same:
                admitted += 1
                if not gold:
                    admitted_off += 1
        if admitted:
            score.contamination.append((seed.id, admitted_off / admitted))

    return score, results


# ---------------------------------------------------------------------------
# Agrégation
# ---------------------------------------------------------------------------


def _safe_div(num: float, denom: float) -> float:
    return num / denom if denom else 0.0


def _f1(precision: float, recall: float) -> float:
    return _safe_div(2 * precision * recall, precision + recall)


def aggregate(
    pool_scores: list[PoolScore], pair_results: list[PairResult]
) -> dict:
    tp = sum(s.tp for s in pool_scores)
    fp = sum(s.fp for s in pool_scores)
    fn = sum(s.fn for s in pool_scores)
    tn = sum(s.tn for s in pool_scores)
    p = _safe_div(tp, tp + fp)
    r = _safe_div(tp, tp + fn)

    # Macro = moyenne des métriques par pool (un gros pool ne domine pas).
    scored_pools = [s for s in pool_scores if (s.tp + s.fp + s.fn) > 0]
    macro_p = _safe_div(sum(s.precision for s in scored_pools), len(scored_pools))
    macro_r = _safe_div(sum(s.recall for s in scored_pools), len(scored_pools))
    macro_f1 = _safe_div(sum(s.f1 for s in scored_pools), len(scored_pools))

    # Contamination : moyenne sur tous les seeds ayant admis ≥1 candidat.
    contam_pairs = [c for s in pool_scores for c in s.contamination]
    mean_contam = _safe_div(sum(v for _, v in contam_pairs), len(contam_pairs))
    worst = sorted(contam_pairs, key=lambda c: c[1], reverse=True)[:10]

    # FP par chemin d'acceptation ; FN par raison.
    fp_paths: Counter = Counter()
    for pr in pair_results:
        if pr.predicted_same and not pr.gold_same:
            fp_paths[pr.accept_path or "unknown"] += 1
    fn_reasons: Counter = Counter()
    for pr in pair_results:
        if not pr.predicted_same and pr.gold_same:
            fn_reasons[pr.reject_reason or "unknown"] += 1

    # Couverture des signaux.
    n_pairs = len(pair_results)
    n_full = sum(1 for pr in pair_results if pr.full_signals)

    return {
        "n_pools": len(pool_scores),
        "n_scored_pools": len(scored_pools),
        "n_pairs": n_pairs,
        "micro": {
            "tp": tp, "fp": fp, "fn": fn, "tn": tn,
            "precision": p, "recall": r, "f1": _f1(p, r),
        },
        "macro": {
            "precision": macro_p, "recall": macro_r, "f1": macro_f1,
        },
        "contamination": {
            "mean": mean_contam,
            "n_seeds": len(contam_pairs),
            "worst": worst,
        },
        "fp_by_accept_path": dict(fp_paths.most_common()),
        "fn_by_reason": dict(fn_reasons.most_common()),
        "signal_coverage": {
            "n_pairs": n_pairs,
            "n_full_signals": n_full,
            "full_signals_ratio": _safe_div(n_full, n_pairs),
        },
        "per_pool": [
            {
                "pool_key": s.pool_key,
                "n_articles": s.n_articles,
                "tp": s.tp, "fp": s.fp, "fn": s.fn,
                "precision": s.precision, "recall": s.recall, "f1": s.f1,
            }
            for s in pool_scores
        ],
    }


def evaluate_dataset(
    dataset: dict,
    floor: float = PERSPECTIVE_MIN_JACCARD_FLOOR,
    require_double_entity: bool = False,
) -> dict:
    pool_scores: list[PoolScore] = []
    pair_results: list[PairResult] = []
    for pool in dataset["pools"]:
        score, results = evaluate_pool(
            pool, floor=floor, require_double_entity=require_double_entity
        )
        pool_scores.append(score)
        pair_results.extend(results)
    return aggregate(pool_scores, pair_results)


# ---------------------------------------------------------------------------
# Sweep
# ---------------------------------------------------------------------------


def sweep(
    dataset: dict, floors: list[float]
) -> list[dict]:
    """Balaie le floor + la variante « exiger 2 entités partout »."""
    rows: list[dict] = []
    for floor in floors:
        m = evaluate_dataset(dataset, floor=floor)
        rows.append({
            "setting": f"floor={floor:.2f}",
            "floor": floor,
            "require_double_entity": False,
            "precision": m["micro"]["precision"],
            "recall": m["micro"]["recall"],
            "f1": m["micro"]["f1"],
            "contamination": m["contamination"]["mean"],
            "fp": m["micro"]["fp"],
            "fn": m["micro"]["fn"],
        })
    m2 = evaluate_dataset(dataset, require_double_entity=True)
    rows.append({
        "setting": "require_entities>=2",
        "floor": None,
        "require_double_entity": True,
        "precision": m2["micro"]["precision"],
        "recall": m2["micro"]["recall"],
        "f1": m2["micro"]["f1"],
        "contamination": m2["contamination"]["mean"],
        "fp": m2["micro"]["fp"],
        "fn": m2["micro"]["fn"],
    })
    return rows


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def _id_short(s: str) -> str:
    return s[:8] if len(s) > 8 else s


def render_report(metrics: dict, dataset_path: Path, tag: str) -> str:
    today = datetime.now(UTC).date().isoformat()
    micro = metrics["micro"]
    macro = metrics["macro"]
    contam = metrics["contamination"]
    cov = metrics["signal_coverage"]
    out = [
        f"# Évaluation clustering perspectives — `{tag}` ({today})",
        "",
        f"- Dataset : `{dataset_path.name}`",
        f"- Pools : {metrics['n_pools']} (scorés : {metrics['n_scored_pools']}) · "
        f"Paires ordonnées : {metrics['n_pairs']}",
        "",
        "> Périmètre **déterministe** = la *porte* `_is_topically_coherent`. "
        "Layer 2/3 (Google News) génère des candidats sans topics/entities — "
        "hors mesure ici (on évalue la porte, pas la génération de candidats).",
        "",
        "## Métriques pairwise",
        "",
        f"- **Micro** : P = {micro['precision']:.3f} · R = {micro['recall']:.3f} · "
        f"F1 = {micro['f1']:.3f}  (TP={micro['tp']} FP={micro['fp']} "
        f"FN={micro['fn']} TN={micro['tn']})",
        f"- **Macro** (moyenne par pool) : P = {macro['precision']:.3f} · "
        f"R = {macro['recall']:.3f} · F1 = {macro['f1']:.3f}",
        "",
        "## Contamination par seed",
        "",
        f"- Moyenne : {contam['mean']:.3f}  (sur {contam['n_seeds']} seeds "
        "ayant admis ≥1 candidat)",
    ]
    if contam["worst"]:
        out.append("- Pires offenders (junk-drawers) :")
        for seed_id, val in contam["worst"][:5]:
            out.append(f"  - `{_id_short(seed_id)}` : {val:.2f}")
    out.append("")
    out.append("## FP par chemin d'acceptation (la fuite)")
    out.append("")
    if metrics["fp_by_accept_path"]:
        for path, n in metrics["fp_by_accept_path"].items():
            out.append(f"- `{path}` : {n}")
    else:
        out.append("- *(aucun FP)*")
    out.append("")
    out.append("## FN par signal manquant (gap paraphrases)")
    out.append("")
    if metrics["fn_by_reason"]:
        for reason, n in metrics["fn_by_reason"].items():
            out.append(f"- `{reason}` : {n}")
    else:
        out.append("- *(aucun FN)*")
    out.append("")
    out.append("## Couverture des signaux")
    out.append("")
    out.append(
        f"- `full_signals` : {cov['n_full_signals']}/{cov['n_pairs']} "
        f"({cov['full_signals_ratio']:.1%}) — garde-fou attribution de la fuite"
    )
    out.append("")
    out.append("## Détail par pool")
    out.append("")
    out.append("| pool | n | TP | FP | FN | P | R | F1 |")
    out.append("|------|---|----|----|----|---|---|----|")
    for p in metrics["per_pool"]:
        out.append(
            f"| `{p['pool_key']}` | {p['n_articles']} | {p['tp']} | {p['fp']} | "
            f"{p['fn']} | {p['precision']:.2f} | {p['recall']:.2f} | "
            f"{p['f1']:.2f} |"
        )
    out.append("")
    return "\n".join(out)


def render_sweep(rows: list[dict]) -> str:
    out = [
        "## Sweep floor (branche « weak double signal »)",
        "",
        "| Réglage | P | R | F1 | Contam | FP | FN |",
        "|---------|---|---|----|--------|----|----|",
    ]
    for row in rows:
        out.append(
            f"| {row['setting']} | {row['precision']:.3f} | {row['recall']:.3f} | "
            f"{row['f1']:.3f} | {row['contamination']:.3f} | {row['fp']} | "
            f"{row['fn']} |"
        )
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Compare mode
# ---------------------------------------------------------------------------


def render_compare(baseline: dict, after: dict) -> str:
    lines = [
        "# Comparaison baseline ↔ after",
        "",
        f"Paires baseline = {baseline['n_pairs']} · after = {after['n_pairs']}",
        "",
        "| Métrique | baseline | after | Δ |",
        "|----------|----------|-------|---|",
    ]
    for metric in ("precision", "recall", "f1"):
        b = baseline["micro"][metric]
        a = after["micro"][metric]
        lines.append(f"| micro {metric} | {b:.3f} | {a:.3f} | {a - b:+.3f} |")
    bc = baseline["contamination"]["mean"]
    ac = after["contamination"]["mean"]
    lines.append(f"| contamination | {bc:.3f} | {ac:.3f} | {ac - bc:+.3f} |")
    bfp = baseline["micro"]["fp"]
    afp = after["micro"]["fp"]
    lines.append(f"| FP | {bfp} | {afp} | {afp - bfp:+d} |")
    bfn = baseline["micro"]["fn"]
    afn = after["micro"]["fn"]
    lines.append(f"| FN | {bfn} | {afn} | {afn - bfn:+d} |")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", help="Dataset gold étiqueté (mode évaluation)")
    parser.add_argument("--tag", default="baseline", help="Nom de l'itération")
    parser.add_argument(
        "--sweep",
        action="store_true",
        help="Balaie le floor + variante « 2 entités partout » (Iter 1)",
    )
    parser.add_argument(
        "--floor",
        type=float,
        default=None,
        help="Override ponctuel du floor (sinon PERSPECTIVE_MIN_JACCARD_FLOOR)",
    )
    parser.add_argument(
        "--require-double-entity",
        action="store_true",
        help="Évalue la variante « exiger ≥2 entités discriminantes partout »",
    )
    parser.add_argument(
        "--compare",
        nargs=2,
        metavar=("BASELINE", "AFTER"),
        help="Mode comparaison : 2 JSON produits par ce script",
    )
    parser.add_argument("--out-json", default=None)
    parser.add_argument("--out-md", default=None)
    args = parser.parse_args()

    if args.compare:
        baseline = json.loads(Path(args.compare[0]).read_text(encoding="utf-8"))
        after = json.loads(Path(args.compare[1]).read_text(encoding="utf-8"))
        print(render_compare(baseline["metrics"], after["metrics"]))
        return

    if not args.dataset:
        parser.error("--dataset requis (sauf en mode --compare)")

    dataset_path = Path(args.dataset)
    dataset = load_dataset(dataset_path)

    floor = args.floor if args.floor is not None else PERSPECTIVE_MIN_JACCARD_FLOOR
    metrics = evaluate_dataset(
        dataset, floor=floor, require_double_entity=args.require_double_entity
    )
    report = render_report(metrics, dataset_path, args.tag)

    sweep_rows = sweep(dataset, DEFAULT_FLOOR_SWEEP) if args.sweep else None
    if sweep_rows:
        report = report + "\n" + render_sweep(sweep_rows) + "\n"

    today = datetime.now(UTC).date().isoformat()
    out_json = Path(
        args.out_json or CONTEXT_DIR / f"gold-events-{args.tag}-{today}.json"
    )
    out_md = Path(args.out_md or CONTEXT_DIR / f"gold-events-{args.tag}-{today}.md")
    out_json.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "generated_at": datetime.now(UTC).isoformat(),
        "dataset": dataset_path.name,
        "tag": args.tag,
        "floor": floor,
        "require_double_entity": args.require_double_entity,
        "metrics": metrics,
        "sweep": sweep_rows,
    }
    out_json.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    out_md.write_text(report, encoding="utf-8")

    print(f"✅ Résultats : {out_json}")
    print(f"✅ Rapport   : {out_md}")
    print()
    print(report)


if __name__ == "__main__":
    main()
