"""Banc de mesure de la **porte de curation veille** (`feed_filter._score_block`)
contre un gold écrit à la main (cf.
`docs/maintenance/maintenance-veille-curation-calibration.md`).

Modèle (allégé) du harness de calibration clustering
(`scripts/evaluate_event_clustering.py`), mais **sans LLM ni revue PO** : le gold
est un dataset fixture monté à la main (`tests/fixtures/veille_curation_gold.json`,
`dataset_kind: veille_curation`).

Le harness **rejoue la vraie porte** (anti-drift garanti par les tests) :

- Reconstruit `VeilleFilters` + `ScoringContext` via le **vrai**
  `build_veille_scoring_context` (stub de session, sans DB), et des `Content` /
  `Source` transitoires (pattern de `prove_veille_curation.py`).
- Partitionne les candidats en **Bloc A** (source configurée) / **Bloc B**
  (topics/mots-clés hors sources configurées, via le **vrai** prédicat
  mot-entier `matches_word_boundary`), puis rejoue le **vrai** `_score_block`
  par bloc. La décision garder/écarter vient donc de la fonction de prod ; le
  harness n'attribue que le *chemin* (via le vrai `_matched_axes`) et la
  *raison* de rejet.

Métriques :

- Précision / rappel / F1 (micro + macro par config).
- **FP par bloc** (A vs B) — le chiffre vedette : le Bloc A en laisser-passer
  est la fuite principale.
- **FP par chemin** (`source_only` / `keyword` / `topic` / `topic+keyword`) :
  attendu en baseline = majorité `source_only` dans le Bloc A.
- **FN par raison** (`floor_source_only` / `below_threshold` /
  `diversity_capped` / `not_a_candidate`).
- **Couverture d'axe** : parmi les articles `relevant`, part qui n'a qu'un axe
  mot-clé (sans topic ML) ou source-seul — quantifie le trou « nba » (topic ML
  mort) et le coût en rappel du gate-all.

`--sweep` balaie le levier Bloc A `{laisser-passer | floor | floor+seuil}` (et la
valeur de seuil) ; `--compare BASELINE AFTER`.

Usage :
    cd packages/api && PYTHONPATH=. python scripts/evaluate_veille_curation.py \\
        --dataset tests/fixtures/veille_curation_gold.json \\
        --tag baseline --block-a-policy passthrough
    PYTHONPATH=. python scripts/evaluate_veille_curation.py \\
        --dataset tests/fixtures/veille_curation_gold.json --sweep
    PYTHONPATH=. python scripts/evaluate_veille_curation.py --compare \\
        ../../.context/veille-curation-baseline-<date>.json \\
        ../../.context/veille-curation-iter1-<date>.json

Sorties :
    .context/veille-curation-<tag>-<date>.json  (machine, consommé par --compare)
    .context/veille-curation-<tag>-<date>.md    (lisible humain)
"""

import argparse
import asyncio
import datetime
import json
import os
import sys
from collections import Counter
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from uuid import UUID, uuid4

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.models.content import Content  # noqa: E402
from app.models.enums import ContentType  # noqa: E402
from app.models.source import Source  # noqa: E402
from app.models.veille import VeilleConfig  # noqa: E402
from app.services.recommendation.helpers.keyword_match import (  # noqa: E402
    matches_word_boundary,
)
from app.services.recommendation.scoring_config import ScoringWeights  # noqa: E402
from app.services.recommendation.scoring_engine import PillarScoringEngine  # noqa: E402
from app.services.veille.feed_filter import (  # noqa: E402
    VeilleAngle,
    VeilleFilters,
    _matched_axes,
    _score_block,
)
from app.services.veille.scoring_context import (  # noqa: E402
    build_veille_scoring_context,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

UTC = datetime.UTC
NOW = datetime.datetime(2026, 6, 9, 12, 0, 0, tzinfo=UTC)

# Politiques du levier Bloc A balayées par défaut en mode --sweep.
BLOCK_A_POLICIES = ["passthrough", "floor", "floor_threshold"]
# Valeurs de seuil balayées (autour de VEILLE_RELEVANCE_THRESHOLD = 48).
DEFAULT_THRESHOLD_SWEEP = [44.0, 48.0, 52.0]


def policy_flags(policy: str) -> tuple[bool, bool]:
    """(apply_floor, apply_threshold) pour une politique Bloc A."""
    return {
        "passthrough": (False, False),
        "floor": (True, False),
        "floor_threshold": (True, True),
    }[policy]


@contextmanager
def _threshold_override(value: float | None):
    """Surcharge temporaire de ``VEILLE_RELEVANCE_THRESHOLD`` (sweep seuil).

    ``_score_block`` lit l'attribut de classe ; on le patche pour le sweep
    plutôt que de forker la porte (anti-drift). S'applique globalement (Bloc A
    **et** Bloc B) le temps de l'évaluation.
    """
    if value is None:
        yield
        return
    original = ScoringWeights.VEILLE_RELEVANCE_THRESHOLD
    ScoringWeights.VEILLE_RELEVANCE_THRESHOLD = value
    try:
        yield
    finally:
        ScoringWeights.VEILLE_RELEVANCE_THRESHOLD = original


# ---------------------------------------------------------------------------
# Stub de session : `build_veille_scoring_context` ne touche la DB que pour le
# UserProfile → on renvoie None et il retombe sur une instance transitoire.
# ---------------------------------------------------------------------------


class _StubResult:
    def scalars(self):
        return self

    def first(self):
        return None


class _StubSession:
    async def execute(self, *_a, **_k):
        return _StubResult()


# ---------------------------------------------------------------------------
# Modèle de données
# ---------------------------------------------------------------------------


@dataclass
class GoldArticle:
    id: str
    title: str
    description: str
    topics: list[str]
    source_key: str
    source_name: str
    published_at: datetime.datetime
    label: str  # "relevant" | "off_angle"

    @property
    def gold_relevant(self) -> bool:
        return self.label == "relevant"


@dataclass
class GoldConfig:
    config_key: str
    config_display: str
    theme_id: str
    theme_label: str
    angles: list[dict]
    global_keywords: list[str]
    sources: list[dict]
    source_intents: dict[str, str]
    articles: list[GoldArticle]


def _parse_dt(raw: str | None) -> datetime.datetime:
    if not raw:
        return NOW - datetime.timedelta(hours=6)
    dt = datetime.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt


def load_dataset(path: Path) -> list[GoldConfig]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    configs: list[GoldConfig] = []
    for c in raw["configs"]:
        articles = [
            GoldArticle(
                id=str(a["id"]),
                title=a.get("title") or "",
                description=a.get("description") or "",
                topics=list(a.get("topics") or []),
                source_key=str(a["source_id"]),
                source_name=a.get("source_name") or str(a["source_id"]),
                published_at=_parse_dt(a.get("published_at")),
                label=a["label"],
            )
            for a in c["articles"]
        ]
        configs.append(
            GoldConfig(
                config_key=c["config_key"],
                config_display=c.get("config_display", c["config_key"]),
                theme_id=c["theme_id"],
                theme_label=c.get("theme_label", c["theme_id"]),
                angles=list(c.get("angles") or []),
                global_keywords=list(c.get("global_keywords") or []),
                sources=list(c.get("sources") or []),
                source_intents={
                    s["source_id"]: s["why"]
                    for s in (c.get("sources") or [])
                    if s.get("why")
                },
                articles=articles,
            )
        )
    return configs


# ---------------------------------------------------------------------------
# Construction filtres + contexte + objets transitoires
# ---------------------------------------------------------------------------


def build_filters_context(config: GoldConfig):
    """(`VeilleFilters`, `ScoringContext`, source_key→UUID, contents)."""
    # UUID stable par clé de source (config + articles externes).
    source_keys = {s["source_id"] for s in config.sources}
    source_keys.update(a.source_key for a in config.articles)
    key_to_uuid: dict[str, UUID] = {k: uuid4() for k in sorted(source_keys)}

    source_objs: dict[str, Source] = {
        key: Source(
            id=key_to_uuid[key],
            name=next(
                (
                    s.get("name")
                    for s in config.sources
                    if s["source_id"] == key
                ),
                key,
            ),
            theme=config.theme_id,
            is_curated=True,
            secondary_themes=[],
            tone=None,
        )
        for key in key_to_uuid
    }

    contents: dict[str, Content] = {}
    for a in config.articles:
        contents[a.id] = Content(
            id=uuid4(),
            title=a.title,
            description=a.description,
            theme=config.theme_id,
            topics=a.topics,
            published_at=a.published_at,
            source_id=key_to_uuid[a.source_key],
            source=source_objs[a.source_key],
            content_type=ContentType.ARTICLE,
            duration_seconds=None,
            entities=[],
            content_quality="full",
            thumbnail_url="https://img",
        )

    config_source_uuids = [key_to_uuid[s["source_id"]] for s in config.sources]
    intents_by_uuid = {
        key_to_uuid[k]: v for k, v in config.source_intents.items()
    }
    filters = VeilleFilters(
        theme_id=config.theme_id or None,
        angles=[
            VeilleAngle(
                topic_id=ang["topic_id"],
                label=ang.get("label", ang["topic_id"]),
                keywords=list(ang.get("keywords") or []),
            )
            for ang in config.angles
        ],
        source_ids=config_source_uuids,
        global_keywords=list(config.global_keywords),
        source_intents=intents_by_uuid,
    )

    veille_config = VeilleConfig(
        id=uuid4(),
        user_id=uuid4(),
        theme_id=config.theme_id,
        theme_label=config.theme_label,
        status="active",
    )
    context = asyncio.run(
        build_veille_scoring_context(_StubSession(), veille_config, filters, NOW)
    )
    return filters, context, key_to_uuid, contents


def _matches_block_b_prefilter(
    content: Content, topic_slugs: set[str], keywords: list[str]
) -> bool:
    """Réplique le prédicat SQL Bloc B (`build_topic_keyword_predicate`) :
    topic overlap **OU** mot-clé en mot-entier (titre/description)."""
    if topic_slugs and content.topics and any(t in topic_slugs for t in content.topics):
        return True
    title_lower = (content.title or "").lower()
    desc_lower = (content.description or "").lower()
    return any(matches_word_boundary(kw, title_lower, desc_lower) for kw in keywords)


# ---------------------------------------------------------------------------
# Attribution (chemin d'acceptation / raison de rejet) — concorde avec la
# décision de la VRAIE porte (anti-drift testé), mais ne la prend pas.
# ---------------------------------------------------------------------------


def classify_accept_path(axes: list[str]) -> str:
    has_topic = "topic" in axes
    has_kw = "keyword" in axes
    if has_topic and has_kw:
        return "topic+keyword"
    if has_topic:
        return "topic"
    if has_kw:
        return "keyword"
    return "source_only"


def classify_reject_reason(
    axes: list[str],
    score: float,
    *,
    apply_floor: bool,
    apply_threshold: bool,
    floor_active: bool,
    threshold: float,
) -> str:
    if floor_active and "topic" not in axes and "keyword" not in axes:
        return "floor_source_only"
    if apply_threshold and score < threshold:
        return "below_threshold"
    # A passé floor + seuil mais n'est pas dans le set gardé → coupé par le cap
    # de diversité (Bloc A uniquement).
    return "diversity_capped"


# ---------------------------------------------------------------------------
# Évaluation
# ---------------------------------------------------------------------------


@dataclass
class ArticleResult:
    config_key: str
    article_id: str
    block: str | None  # "A" | "B" | None (jamais candidat)
    gold_relevant: bool
    kept: bool
    accept_path: str | None
    reject_reason: str | None
    axes: list[str]
    score: float


@dataclass
class ConfigScore:
    config_key: str
    n_articles: int
    tp: int = 0
    fp: int = 0
    fn: int = 0
    tn: int = 0

    @property
    def precision(self) -> float:
        return _safe_div(self.tp, self.tp + self.fp)

    @property
    def recall(self) -> float:
        return _safe_div(self.tp, self.tp + self.fn)

    @property
    def f1(self) -> float:
        return _f1(self.precision, self.recall)


def evaluate_config(
    config: GoldConfig, apply_floor: bool, apply_threshold: bool
) -> tuple[ConfigScore, list[ArticleResult]]:
    filters, context, _key_to_uuid, contents = build_filters_context(config)
    topic_slugs = set(filters.topic_slugs)
    source_ids = set(filters.source_ids)
    keywords = filters.all_keywords
    threshold = ScoringWeights.VEILLE_RELEVANCE_THRESHOLD
    floor_active = apply_floor and bool(topic_slugs or keywords)

    # Partition par appartenance à une source configurée (= la requête SQL).
    block_a_articles: list[GoldArticle] = []
    block_b_articles: list[GoldArticle] = []
    block_of: dict[str, str | None] = {}
    for a in config.articles:
        content = contents[a.id]
        if content.source_id in source_ids:
            block_a_articles.append(a)
            block_of[a.id] = "A"
        elif _matches_block_b_prefilter(content, topic_slugs, keywords):
            block_b_articles.append(a)
            block_of[a.id] = "B"
        else:
            block_of[a.id] = None  # jamais ramené par le prédicat → exclu

    # Rejoue la VRAIE porte par bloc. Bloc B reste en (floor, seuil) historique.
    kept_a = (
        _score_block(
            [contents[a.id] for a in block_a_articles],
            context,
            filters,
            apply_floor=apply_floor,
            apply_threshold=apply_threshold,
            diversity_cap=ScoringWeights.VEILLE_SOURCE_DIVERSITY_CAP,
            block="sources",
        )
        if block_a_articles
        else []
    )
    kept_b = (
        _score_block(
            [contents[a.id] for a in block_b_articles],
            context,
            filters,
            apply_floor=True,
            apply_threshold=True,
            block="elargie",
        )
        if block_b_articles
        else []
    )
    kept_ids = {c.id for c, _s, _ax in kept_a} | {c.id for c, _s, _ax in kept_b}

    engine = PillarScoringEngine()
    score = ConfigScore(config_key=config.config_key, n_articles=len(config.articles))
    results: list[ArticleResult] = []
    for a in config.articles:
        content = contents[a.id]
        block = block_of[a.id]
        axes = _matched_axes(content, topic_slugs, source_ids, keywords)
        raw = engine.compute_score(content, context).final_score
        kept = content.id in kept_ids
        block_floor_active = (
            floor_active if block == "A" else bool(topic_slugs or keywords)
        )
        block_apply_threshold = apply_threshold if block == "A" else True
        if kept:
            accept_path: str | None = classify_accept_path(axes)
            reject_reason: str | None = None
        else:
            accept_path = None
            if block is None:
                reject_reason = "not_a_candidate"
            else:
                reject_reason = classify_reject_reason(
                    axes,
                    raw,
                    apply_floor=(apply_floor if block == "A" else True),
                    apply_threshold=block_apply_threshold,
                    floor_active=block_floor_active,
                    threshold=threshold,
                )
        results.append(
            ArticleResult(
                config_key=config.config_key,
                article_id=a.id,
                block=block,
                gold_relevant=a.gold_relevant,
                kept=kept,
                accept_path=accept_path,
                reject_reason=reject_reason,
                axes=axes,
                score=round(raw, 1),
            )
        )
        if kept and a.gold_relevant:
            score.tp += 1
        elif kept and not a.gold_relevant:
            score.fp += 1
        elif not kept and a.gold_relevant:
            score.fn += 1
        else:
            score.tn += 1

    return score, results


# ---------------------------------------------------------------------------
# Agrégation
# ---------------------------------------------------------------------------


def _safe_div(num: float, denom: float) -> float:
    return num / denom if denom else 0.0


def _f1(precision: float, recall: float) -> float:
    return _safe_div(2 * precision * recall, precision + recall)


def aggregate(
    config_scores: list[ConfigScore], results: list[ArticleResult]
) -> dict:
    tp = sum(s.tp for s in config_scores)
    fp = sum(s.fp for s in config_scores)
    fn = sum(s.fn for s in config_scores)
    tn = sum(s.tn for s in config_scores)
    p = _safe_div(tp, tp + fp)
    r = _safe_div(tp, tp + fn)

    scored = [s for s in config_scores if (s.tp + s.fp + s.fn) > 0]
    macro_p = _safe_div(sum(s.precision for s in scored), len(scored))
    macro_r = _safe_div(sum(s.recall for s in scored), len(scored))
    macro_f1 = _safe_div(sum(s.f1 for s in scored), len(scored))

    fp_by_block: Counter = Counter()
    fp_by_path: Counter = Counter()
    fn_by_reason: Counter = Counter()
    for res in results:
        if res.kept and not res.gold_relevant:
            fp_by_block[res.block or "none"] += 1
            fp_by_path[res.accept_path or "unknown"] += 1
        elif not res.kept and res.gold_relevant:
            fn_by_reason[res.reject_reason or "unknown"] += 1

    # Couverture d'axe parmi les articles `relevant`.
    rel = [res for res in results if res.gold_relevant]
    n_rel = len(rel)
    n_rel_topic = sum(1 for res in rel if "topic" in res.axes)
    n_rel_kw_only = sum(
        1 for res in rel if "keyword" in res.axes and "topic" not in res.axes
    )
    n_rel_source_only = sum(
        1 for res in rel if "topic" not in res.axes and "keyword" not in res.axes
    )

    return {
        "n_configs": len(config_scores),
        "n_articles": sum(s.n_articles for s in config_scores),
        "micro": {
            "tp": tp, "fp": fp, "fn": fn, "tn": tn,
            "precision": p, "recall": r, "f1": _f1(p, r),
        },
        "macro": {"precision": macro_p, "recall": macro_r, "f1": macro_f1},
        "fp_by_block": dict(fp_by_block.most_common()),
        "fp_by_path": dict(fp_by_path.most_common()),
        "fn_by_reason": dict(fn_by_reason.most_common()),
        "axis_coverage": {
            "n_relevant": n_rel,
            "n_relevant_topic": n_rel_topic,
            "n_relevant_keyword_only": n_rel_kw_only,
            "n_relevant_source_only": n_rel_source_only,
            "keyword_only_ratio": _safe_div(n_rel_kw_only, n_rel),
            "source_only_ratio": _safe_div(n_rel_source_only, n_rel),
        },
        "per_config": [
            {
                "config_key": s.config_key,
                "n_articles": s.n_articles,
                "tp": s.tp, "fp": s.fp, "fn": s.fn, "tn": s.tn,
                "precision": s.precision, "recall": s.recall, "f1": s.f1,
            }
            for s in config_scores
        ],
    }


def evaluate_dataset(
    configs: list[GoldConfig], policy: str, threshold: float | None = None
) -> dict:
    apply_floor, apply_threshold = policy_flags(policy)
    config_scores: list[ConfigScore] = []
    results: list[ArticleResult] = []
    with _threshold_override(threshold):
        for config in configs:
            cs, rs = evaluate_config(config, apply_floor, apply_threshold)
            config_scores.append(cs)
            results.extend(rs)
    return aggregate(config_scores, results)


# ---------------------------------------------------------------------------
# Sweep
# ---------------------------------------------------------------------------


def sweep(configs: list[GoldConfig], thresholds: list[float]) -> list[dict]:
    """Balaie le levier Bloc A {laisser-passer | floor | floor+seuil} (et le
    seuil pour floor+seuil)."""
    rows: list[dict] = []
    for policy in BLOCK_A_POLICIES:
        if policy == "floor_threshold":
            for thr in thresholds:
                rows.append(_sweep_row(configs, policy, thr))
        else:
            rows.append(_sweep_row(configs, policy, None))
    return rows


def _sweep_row(configs: list[GoldConfig], policy: str, thr: float | None) -> dict:
    m = evaluate_dataset(configs, policy, threshold=thr)
    setting = policy if thr is None else f"{policy}@{thr:.0f}"
    return {
        "setting": setting,
        "policy": policy,
        "threshold": thr,
        "precision": m["micro"]["precision"],
        "recall": m["micro"]["recall"],
        "f1": m["micro"]["f1"],
        "fp": m["micro"]["fp"],
        "fp_block_a": m["fp_by_block"].get("A", 0),
        "fp_source_only": m["fp_by_path"].get("source_only", 0),
        "fn": m["micro"]["fn"],
    }


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def render_report(metrics: dict, dataset_path: Path, tag: str, policy: str) -> str:
    today = datetime.datetime.now(UTC).date().isoformat()
    micro = metrics["micro"]
    macro = metrics["macro"]
    cov = metrics["axis_coverage"]
    out = [
        f"# Évaluation curation veille — `{tag}` ({today})",
        "",
        f"- Dataset : `{dataset_path.name}`",
        f"- Politique Bloc A : `{policy}`",
        f"- Configs : {metrics['n_configs']} · Articles : {metrics['n_articles']}",
        "",
        "## Métriques",
        "",
        f"- **Micro** : P = {micro['precision']:.3f} · R = {micro['recall']:.3f} · "
        f"F1 = {micro['f1']:.3f}  (TP={micro['tp']} FP={micro['fp']} "
        f"FN={micro['fn']} TN={micro['tn']})",
        f"- **Macro** (par config) : P = {macro['precision']:.3f} · "
        f"R = {macro['recall']:.3f} · F1 = {macro['f1']:.3f}",
        "",
        "## FP par bloc (le chiffre vedette)",
        "",
    ]
    if metrics["fp_by_block"]:
        for block, n in metrics["fp_by_block"].items():
            out.append(f"- Bloc `{block}` : {n}")
    else:
        out.append("- *(aucun FP)*")
    out += ["", "## FP par chemin d'acceptation", ""]
    if metrics["fp_by_path"]:
        for path, n in metrics["fp_by_path"].items():
            out.append(f"- `{path}` : {n}")
    else:
        out.append("- *(aucun FP)*")
    out += ["", "## FN par raison", ""]
    if metrics["fn_by_reason"]:
        for reason, n in metrics["fn_by_reason"].items():
            out.append(f"- `{reason}` : {n}")
    else:
        out.append("- *(aucun FN)*")
    out += [
        "",
        "## Couverture d'axe (parmi les `relevant`)",
        "",
        f"- `relevant` total : {cov['n_relevant']}",
        f"- avec axe **topic** ML : {cov['n_relevant_topic']}",
        f"- **mot-clé seul** (pas de topic ML) : {cov['n_relevant_keyword_only']} "
        f"({cov['keyword_only_ratio']:.1%}) — quantifie le trou « nba »",
        f"- **source seule** (ni topic ni mot-clé) : "
        f"{cov['n_relevant_source_only']} ({cov['source_only_ratio']:.1%}) — "
        f"coût en rappel du gate-all (floor-pruned)",
        "",
        "## Détail par config",
        "",
        "| config | n | TP | FP | FN | TN | P | R | F1 |",
        "|--------|---|----|----|----|----|---|---|----|",
    ]
    for c in metrics["per_config"]:
        out.append(
            f"| `{c['config_key']}` | {c['n_articles']} | {c['tp']} | {c['fp']} | "
            f"{c['fn']} | {c['tn']} | {c['precision']:.2f} | {c['recall']:.2f} | "
            f"{c['f1']:.2f} |"
        )
    out.append("")
    return "\n".join(out)


def render_sweep(rows: list[dict]) -> str:
    out = [
        "## Sweep levier Bloc A",
        "",
        "| Réglage | P | R | F1 | FP | FP_blocA | FP_source_only | FN |",
        "|---------|---|---|----|----|----------|----------------|----|",
    ]
    for row in rows:
        out.append(
            f"| {row['setting']} | {row['precision']:.3f} | {row['recall']:.3f} | "
            f"{row['f1']:.3f} | {row['fp']} | {row['fp_block_a']} | "
            f"{row['fp_source_only']} | {row['fn']} |"
        )
    return "\n".join(out)


def render_compare(baseline: dict, after: dict) -> str:
    lines = [
        "# Comparaison baseline ↔ after",
        "",
        f"Articles baseline = {baseline['n_articles']} · after = {after['n_articles']}",
        "",
        "| Métrique | baseline | after | Δ |",
        "|----------|----------|-------|---|",
    ]
    for metric in ("precision", "recall", "f1"):
        b = baseline["micro"][metric]
        a = after["micro"][metric]
        lines.append(f"| micro {metric} | {b:.3f} | {a:.3f} | {a - b:+.3f} |")
    bfp = baseline["micro"]["fp"]
    afp = after["micro"]["fp"]
    lines.append(f"| FP | {bfp} | {afp} | {afp - bfp:+d} |")
    bfa = baseline["fp_by_block"].get("A", 0)
    afa = after["fp_by_block"].get("A", 0)
    lines.append(f"| FP Bloc A | {bfa} | {afa} | {afa - bfa:+d} |")
    bso = baseline["fp_by_path"].get("source_only", 0)
    aso = after["fp_by_path"].get("source_only", 0)
    lines.append(f"| FP source_only | {bso} | {aso} | {aso - bso:+d} |")
    bfn = baseline["micro"]["fn"]
    afn = after["micro"]["fn"]
    lines.append(f"| FN | {bfn} | {afn} | {afn - bfn:+d} |")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", help="Gold veille_curation (mode évaluation)")
    parser.add_argument("--tag", default="baseline")
    parser.add_argument(
        "--block-a-policy",
        default="floor_threshold",
        choices=BLOCK_A_POLICIES,
        help="Levier Bloc A (baseline prod = passthrough ; after = floor_threshold)",
    )
    parser.add_argument("--threshold", type=float, default=None)
    parser.add_argument("--sweep", action="store_true")
    parser.add_argument(
        "--compare", nargs=2, metavar=("BASELINE", "AFTER"),
        help="2 JSON produits par ce script",
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
    configs = load_dataset(dataset_path)

    metrics = evaluate_dataset(configs, args.block_a_policy, threshold=args.threshold)
    report = render_report(metrics, dataset_path, args.tag, args.block_a_policy)

    sweep_rows = sweep(configs, DEFAULT_THRESHOLD_SWEEP) if args.sweep else None
    if sweep_rows:
        report = report + "\n" + render_sweep(sweep_rows) + "\n"

    today = datetime.datetime.now(UTC).date().isoformat()
    out_json = Path(
        args.out_json or CONTEXT_DIR / f"veille-curation-{args.tag}-{today}.json"
    )
    out_md = Path(
        args.out_md or CONTEXT_DIR / f"veille-curation-{args.tag}-{today}.md"
    )
    out_json.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "generated_at": datetime.datetime.now(UTC).isoformat(),
        "dataset": dataset_path.name,
        "tag": args.tag,
        "block_a_policy": args.block_a_policy,
        "threshold": args.threshold,
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
