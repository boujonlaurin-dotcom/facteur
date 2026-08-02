#!/usr/bin/env python3
"""Dry-run comparatif du fold couverture (B-2) — READ-ONLY contre la prod.

Rejoue `charger contenus → build_topic_clusters → sélection top-15 (entrée LLM)`
**avec** et **sans** le fold fiabilité (`EDITORIAL_COVERAGE_FOLD_ENABLED`), sans
appeler le LLM (la sélection des 15 clusters soumis est déterministe : elle ne
dépend que de `len(source_domains)`, cf. `curation.select_topics`).

Ce script n'écrit **rien** en base. Il produit :
  - le diff des 15 clusters soumis au LLM (entrants / sortants / % changé) ;
  - la distribution `source_count` avant/après + les franchissements 2→1 / 3→2 ;
  - la répartition par thème des clusters entrants et sortants (garde-fou
    `politics`).

Garde-fou du plan : si **> 50 % du top-15 change**, le script sort un code
retour ≠ 0 (on revoit le critère avant de merger).

Usage:
    cd packages/api && source venv/bin/activate
    PYTHONPATH=. python scripts/dryrun_coverage_fold.py --hours 24 --tag b2-fold
    PYTHONPATH=. python scripts/dryrun_coverage_fold.py --hours 24 --tag b2-fold --compare

Sorties (comme evaluate_event_clustering.py) :
    ../../.context/dryrun_coverage_fold_<tag>.json  (machine)
    ../../.context/dryrun_coverage_fold_<tag>.md    (lisible)
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from collections import Counter
from datetime import UTC, datetime, timedelta
from pathlib import Path

# packages/api sur sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

# Seuil de churn bloquant (plan §2).
CHURN_ABORT_THRESHOLD = 0.50

parser = argparse.ArgumentParser(
    description="Dry-run comparatif du fold couverture B-2 (read-only prod)"
)
parser.add_argument(
    "--hours", type=int, default=24, help="Fenêtre de contenus (défaut: 24h)"
)
parser.add_argument("--tag", default="b2-fold", help="Nom du run (défaut: b2-fold)")
parser.add_argument(
    "--compare",
    action="store_true",
    help="Affiche le tableau détaillé cluster-par-cluster en plus du résumé",
)
args = parser.parse_args()

# Le LLM n'est jamais appelé, mais on neutralise la clé par précaution (la
# sélection top-15 est purement déterministe).
os.environ["MISTRAL_API_KEY"] = ""

from sqlalchemy import select  # noqa: E402
from sqlalchemy.orm import selectinload  # noqa: E402

from app.database import async_session_maker, engine  # noqa: E402
from app.models.content import Content  # noqa: E402
from app.models.source import Source  # noqa: E402
from app.services.briefing.importance_detector import (  # noqa: E402
    ImportanceDetector,
    TopicCluster,
)
from app.services.editorial.config import load_editorial_config  # noqa: E402

ClusterKey = frozenset


def _cluster_key(cluster: TopicCluster) -> ClusterKey:
    """Clé stable d'un cluster = ensemble des content.id qui le composent.

    `cluster_id` est un uuid4 régénéré à chaque `build_topic_clusters`, donc
    inutilisable pour apparier deux runs. Le clustering est déterministe sur
    les mêmes contenus → les groupes sont identiques fold ON/OFF ; seuls les
    décomptes de sources changent. La composition en contenus est donc la clé.
    """
    return frozenset(c.id for c in cluster.contents)


def _select_top_clusters(
    clusters: list[TopicCluster], count: int, limit: int
) -> list[TopicCluster]:
    """Reproduit la sélection pré-LLM de `curation.select_topics` (:220-248).

    Préfère les clusters multi-source (≥2 domaines), retombe sur l'ensemble si
    le pool multi-source est insuffisant, puis trie par nombre de domaines
    décroissant et coupe à `limit`.
    """
    available = clusters
    multi_source = [c for c in available if len(c.source_domains) >= 2]
    pool = multi_source if len(multi_source) >= count else available
    return sorted(pool, key=lambda c: len(c.source_domains), reverse=True)[:limit]


async def _load_contents(hours: int) -> list[Content]:
    since = datetime.now(UTC) - timedelta(hours=hours)
    stmt = (
        select(Content)
        .join(Content.source)
        .options(selectinload(Content.source))
        .where(
            Content.published_at >= since,
            Source.is_active.is_(True),
        )
        .order_by(Content.published_at.desc())
    )
    async with async_session_maker() as session:
        result = await session.execute(stmt)
        return list(result.scalars().all())


def _build_clusters(contents: list[Content], fold_enabled: bool) -> list[TopicCluster]:
    if fold_enabled:
        os.environ["EDITORIAL_COVERAGE_FOLD_ENABLED"] = "true"
    else:
        os.environ["EDITORIAL_COVERAGE_FOLD_ENABLED"] = "false"
    detector = ImportanceDetector()
    return detector.build_topic_clusters(contents)


def _domain_histogram(clusters: list[TopicCluster]) -> dict[str, int]:
    hist: Counter[int] = Counter(len(c.source_domains) for c in clusters)
    # buckets lisibles : 1, 2, 3, 4+
    out = {"1": 0, "2": 0, "3": 0, "4+": 0}
    for n, cnt in hist.items():
        if n <= 1:
            out["1"] += cnt
        elif n == 2:
            out["2"] += cnt
        elif n == 3:
            out["3"] += cnt
        else:
            out["4+"] += cnt
    return out


def _theme_counter(clusters: list[TopicCluster]) -> dict[str, int]:
    return dict(Counter((c.theme or "null") for c in clusters))


def _label_for(key: ClusterKey, by_key: dict[ClusterKey, TopicCluster]) -> str:
    c = by_key.get(key)
    if c is None:
        return "?"
    return (c.label or (c.contents[0].title if c.contents else ""))[:70]


async def run() -> int:
    config = load_editorial_config()
    count = config.pipeline.subjects_count
    limit = config.pipeline.cluster_input_limit

    contents = await _load_contents(args.hours)
    if not contents:
        print("⚠ Aucun contenu chargé — vérifier DATABASE_URL et --hours.")
        return 2

    clusters_off = _build_clusters(contents, fold_enabled=False)
    clusters_on = _build_clusters(contents, fold_enabled=True)

    by_key_off = {_cluster_key(c): c for c in clusters_off}
    by_key_on = {_cluster_key(c): c for c in clusters_on}

    top_off = _select_top_clusters(clusters_off, count, limit)
    top_on = _select_top_clusters(clusters_on, count, limit)
    keys_off = [_cluster_key(c) for c in top_off]
    keys_on = [_cluster_key(c) for c in top_on]
    set_off, set_on = set(keys_off), set(keys_on)

    leaving = set_off - set_on  # dans le top-15 baseline, plus après fold
    entering = set_on - set_off  # nouveaux dans le top-15 après fold

    denom = max(len(set_off), 1)
    pct_changed = len(leaving) / denom

    # Franchissements de gate, sur les clusters appariés.
    crossings_2_1 = 0
    crossings_3_2 = 0
    for key, c_off in by_key_off.items():
        c_on = by_key_on.get(key)
        if c_on is None:
            continue
        d_off, d_on = len(c_off.source_domains), len(c_on.source_domains)
        if d_off >= 2 and d_on < 2:
            crossings_2_1 += 1
        if d_off >= 3 and d_on == 2:
            crossings_3_2 += 1

    # Répartition par thème des clusters entrants / sortants (garde-fou politics).
    leaving_themes = Counter(_label_theme(k, by_key_off) for k in leaving)
    entering_themes = Counter(_label_theme(k, by_key_on) for k in entering)
    theme_net: dict[str, int] = {}
    for t in set(leaving_themes) | set(entering_themes):
        theme_net[t] = entering_themes.get(t, 0) - leaving_themes.get(t, 0)
    politics_net = theme_net.get("politics", 0)

    payload = {
        "tag": args.tag,
        "hours": args.hours,
        "generated_at": datetime.now(UTC).isoformat(),
        "contents_loaded": len(contents),
        "clusters_total_off": len(clusters_off),
        "clusters_total_on": len(clusters_on),
        "top_limit": limit,
        "subjects_count": count,
        "top15_size_off": len(top_off),
        "top15_size_on": len(top_on),
        "top15_leaving": len(leaving),
        "top15_entering": len(entering),
        "top15_pct_changed": round(pct_changed, 4),
        "crossings_2_to_1": crossings_2_1,
        "crossings_3_to_2": crossings_3_2,
        "domain_hist_off": _domain_histogram(clusters_off),
        "domain_hist_on": _domain_histogram(clusters_on),
        "leaving_themes": dict(leaving_themes),
        "entering_themes": dict(entering_themes),
        "theme_net_entering_minus_leaving": theme_net,
        "politics_net": politics_net,
        "churn_abort_threshold": CHURN_ABORT_THRESHOLD,
        "aborted": pct_changed > CHURN_ABORT_THRESHOLD,
        "leaving_labels": [_label_for(k, by_key_off) for k in leaving],
        "entering_labels": [_label_for(k, by_key_on) for k in entering],
    }

    CONTEXT_DIR.mkdir(parents=True, exist_ok=True)
    json_path = CONTEXT_DIR / f"dryrun_coverage_fold_{args.tag}.json"
    md_path = CONTEXT_DIR / f"dryrun_coverage_fold_{args.tag}.md"
    json_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    md_path.write_text(_render_md(payload), encoding="utf-8")

    _print_summary(payload, by_key_off, by_key_on, leaving, entering)

    if payload["aborted"]:
        print(
            f"\n❌ ABORT : {pct_changed:.0%} du top-15 change "
            f"(> {CHURN_ABORT_THRESHOLD:.0%}). Revoir le critère avant de merger."
        )
        return 1
    if politics_net < 0:
        print(
            f"\n⚠ politics net-sortant du top-15 ({politics_net}). "
            "À examiner, mais non bloquant."
        )
    print(f"\n✅ OK : {pct_changed:.0%} du top-15 change (≤ {CHURN_ABORT_THRESHOLD:.0%}).")
    print(f"   JSON : {json_path}")
    print(f"   MD   : {md_path}")
    return 0


def _label_theme(key: ClusterKey, by_key: dict[ClusterKey, TopicCluster]) -> str:
    c = by_key.get(key)
    return (c.theme or "null") if c is not None else "null"


def _render_md(p: dict) -> str:
    lines = [
        f"# Dry-run fold couverture B-2 — `{p['tag']}`",
        "",
        f"- Généré : {p['generated_at']}",
        f"- Fenêtre : {p['hours']}h — {p['contents_loaded']} contenus",
        f"- Clusters : {p['clusters_total_off']} (off) / {p['clusters_total_on']} (on)",
        "",
        "## Top-15 soumis au LLM (entrée)",
        "",
        f"- Sortants : **{p['top15_leaving']}** / {p['top15_size_off']}",
        f"- Entrants : **{p['top15_entering']}**",
        f"- % changé : **{p['top15_pct_changed']:.0%}** "
        f"(seuil abort {p['churn_abort_threshold']:.0%})",
        f"- Franchissements 2→1 : {p['crossings_2_to_1']} · 3→2 : {p['crossings_3_to_2']}",
        "",
        "## Distribution source_count (tous clusters)",
        "",
        "| domaines | off | on |",
        "|---|---|---|",
    ]
    for bucket in ("1", "2", "3", "4+"):
        lines.append(
            f"| {bucket} | {p['domain_hist_off'][bucket]} | {p['domain_hist_on'][bucket]} |"
        )
    lines += [
        "",
        "## Thèmes (entrants − sortants, garde-fou politics)",
        "",
        "| thème | entrants | sortants | net |",
        "|---|---|---|---|",
    ]
    net = p["theme_net_entering_minus_leaving"]
    for t in sorted(net, key=lambda k: net[k]):
        lines.append(
            f"| {t} | {p['entering_themes'].get(t, 0)} | "
            f"{p['leaving_themes'].get(t, 0)} | {net[t]:+d} |"
        )
    lines += [
        "",
        f"**politics net = {p['politics_net']:+d}** "
        f"({'net-sortant ⚠' if p['politics_net'] < 0 else 'ok'})",
        "",
        f"**Verdict : {'ABORT ❌' if p['aborted'] else 'OK ✅'}**",
        "",
    ]
    return "\n".join(lines)


def _print_summary(p, by_key_off, by_key_on, leaving, entering) -> None:
    print("=" * 66)
    print(f"  DRY-RUN FOLD COUVERTURE B-2 — tag={p['tag']} hours={p['hours']}")
    print("=" * 66)
    print(f"  Contenus         : {p['contents_loaded']}")
    print(f"  Clusters off/on  : {p['clusters_total_off']} / {p['clusters_total_on']}")
    print(
        f"  Top-15 sortants  : {p['top15_leaving']} / {p['top15_size_off']} "
        f"({p['top15_pct_changed']:.0%})"
    )
    print(f"  Top-15 entrants  : {p['top15_entering']}")
    print(f"  2→1 / 3→2        : {p['crossings_2_to_1']} / {p['crossings_3_to_2']}")
    print(f"  politics net     : {p['politics_net']:+d}")
    if args.compare:
        print("-" * 66)
        print("  SORTANTS (dans le top-15 baseline, foldés hors ensuite) :")
        for k in leaving:
            c = by_key_off.get(k)
            print(
                f"    [{c.theme or 'null':<13}] {len(c.source_domains)}→? "
                f"{_label_for(k, by_key_off)}"
            )
        print("  ENTRANTS :")
        for k in entering:
            c = by_key_on.get(k)
            print(
                f"    [{c.theme or 'null':<13}] {len(c.source_domains)} dom. "
                f"{_label_for(k, by_key_on)}"
            )


async def _main() -> int:
    try:
        return await run()
    finally:
        await engine.dispose()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main()))
