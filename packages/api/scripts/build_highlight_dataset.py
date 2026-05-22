"""Construit le dataset d'annotation pour la calibration data-driven du
highlighting (Story 7.4, suite).

Workflow :
    1. L'utilisateur extrait un dump brut via MCP Supabase (cf. README de
       la doc de maintenance).
    2. Ce script :
       a. groupe les articles en pseudo-clusters par entité partagée
          (reprend `build_pseudo_clusters` de `inspect_title_annotations.py`),
       b. filtre les clusters mal formés (≥70 % des paires partagent ≥2
          entités PERSON/ORG/EVENT, fenêtre ≤36 h, 1 article par source),
       c. stratifie pour respecter un quota par thème + diversité de stance,
       d. dump le dataset annotable (champ `annotations` vide par article)
          dans `.context/highlight-dataset-<date>.json`.

Forme du dump d'entrée (un sur-ensemble du format accepté par
`inspect_title_annotations.py:25-39`) :

    {
      "generated_at": "2026-05-19T15:00:00Z",
      "articles": [
        {
          "id": "uuid",
          "title": "...",
          "url": "...",
          "published_at": "2026-05-19T08:00:00Z",
          "source_name": "Le Monde",
          "source_id": "uuid",
          "bias_stance": "center-left",
          "theme": "politics",
          "entities": ["{\"name\": \"Macron\", \"type\": \"PERSON\"}", ...]
        }, ...
      ]
    }

Usage :
    cd packages/api && source venv/bin/activate
    python scripts/build_highlight_dataset.py \\
        --raw .context/raw-articles-2026-05-19.json \\
        --out .context/highlight-dataset-2026-05-19.json

Sortie :
    JSON sérialisé (schéma documenté dans `docs/maintenance/
    maintenance-highlight-calibration.md`).
"""

import argparse
import json
import os
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from itertools import combinations
from pathlib import Path

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from scripts.inspect_title_annotations import (  # noqa: E402
    DISCRIMINANT_TYPES,
    build_pseudo_clusters,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

# Stratification par défaut. Les slugs viennent de `THEME_LABELS`
# (`app/services/recommendation_service.py:1911-1923`).
DEFAULT_QUOTAS: dict[str, dict] = {
    "politics":      {"target_clusters": 6, "min_stances": 3, "themes": ["politics"]},
    "international": {"target_clusters": 6, "min_stances": 3, "themes": ["international", "geopolitics"]},
    "economy":       {"target_clusters": 5, "min_stances": 2, "themes": ["economy"]},
    "culture":       {"target_clusters": 4, "min_stances": 2, "themes": ["culture", "culture_ideas"]},
    "society":       {"target_clusters": 5, "min_stances": 2, "themes": ["society", "society_climate", "environment"]},
    "science_tech":  {"target_clusters": 4, "min_stances": 2, "themes": ["science", "tech"]},
}


@dataclass
class Article:
    id: str
    title: str
    url: str
    published_at: datetime
    source_name: str
    source_id: str
    bias_stance: str
    theme: str
    entities: list[str]

    def entity_keys(self) -> list[tuple[str, str]]:
        out: list[tuple[str, str]] = []
        for raw in self.entities or []:
            try:
                obj = json.loads(raw)
            except (ValueError, TypeError):
                continue
            if obj.get("type") not in DISCRIMINANT_TYPES:
                continue
            name = (obj.get("name") or "").strip()
            if name:
                out.append((name.lower(), name))
        return out

    def discriminant_entity_set(self) -> set[str]:
        return {k for k, _ in self.entity_keys()}


@dataclass
class Cluster:
    key: str
    display: str
    articles: list[Article]
    theme: str = ""
    distinct_stances: int = 0


@dataclass
class BuildStats:
    n_articles: int = 0
    n_pseudo_clusters: int = 0
    n_well_formed: int = 0
    n_after_window: int = 0
    n_after_source_dedup: int = 0
    n_selected: int = 0
    per_group: dict[str, int] = field(default_factory=dict)
    skipped_themes: list[str] = field(default_factory=list)


def load_articles(path: Path) -> list[Article]:
    data = json.loads(path.read_text(encoding="utf-8"))
    out: list[Article] = []
    for a in data["articles"]:
        out.append(
            Article(
                id=str(a["id"]),
                title=a["title"] or "",
                url=a.get("url") or "",
                published_at=datetime.fromisoformat(
                    a["published_at"].replace("Z", "+00:00")
                ),
                source_name=a.get("source_name") or "?",
                source_id=str(a.get("source_id") or ""),
                bias_stance=a.get("bias_stance") or "unknown",
                theme=(a.get("theme") or "").strip(),
                entities=list(a.get("entities") or []),
            )
        )
    return out


def dedup_by_source(arts: list[Article]) -> list[Article]:
    """Garde l'article le plus récent par source dans un cluster."""
    by_source: dict[str, Article] = {}
    for a in arts:
        existing = by_source.get(a.source_id)
        if existing is None or a.published_at > existing.published_at:
            by_source[a.source_id] = a
    return list(by_source.values())


def within_window(arts: list[Article], hours: int) -> bool:
    if len(arts) < 2:
        return True
    ts = [a.published_at for a in arts]
    return (max(ts) - min(ts)) <= timedelta(hours=hours)


def well_formed(arts: list[Article], min_pair_ratio: float, min_shared: int) -> bool:
    """≥ `min_pair_ratio` des paires d'articles partagent ≥ `min_shared` entités."""
    if len(arts) < 2:
        return False
    pairs = list(combinations(arts, 2))
    if not pairs:
        return False
    sets = {a.id: a.discriminant_entity_set() for a in arts}
    good = sum(1 for a, b in pairs if len(sets[a.id] & sets[b.id]) >= min_shared)
    return (good / len(pairs)) >= min_pair_ratio


def pick_theme(arts: list[Article]) -> str:
    counts = Counter(a.theme for a in arts if a.theme)
    if not counts:
        return ""
    return counts.most_common(1)[0][0]


def count_stances(arts: list[Article]) -> int:
    return len({a.bias_stance for a in arts if a.bias_stance and a.bias_stance != "unknown"})


def build_clusters(
    articles: list[Article],
    min_size: int,
    window_hours: int,
    min_pair_ratio: float,
    min_shared_entities: int,
    stats: BuildStats,
) -> list[Cluster]:
    """Pipeline complet de construction des clusters bien formés."""
    raw = build_pseudo_clusters(articles, min_size=min_size, top_n=10_000)
    stats.n_pseudo_clusters = len(raw)

    clusters: list[Cluster] = []
    for key, display, arts in raw:
        deduped = dedup_by_source(arts)
        if len(deduped) < min_size:
            continue
        stats.n_after_source_dedup += 1
        if not within_window(deduped, window_hours):
            continue
        stats.n_after_window += 1
        if not well_formed(deduped, min_pair_ratio, min_shared_entities):
            continue
        stats.n_well_formed += 1
        clusters.append(
            Cluster(
                key=key,
                display=display,
                articles=deduped,
                theme=pick_theme(deduped),
                distinct_stances=count_stances(deduped),
            )
        )
    return clusters


def stratify(
    clusters: list[Cluster],
    quotas: dict[str, dict],
    max_per_cluster: int,
    stats: BuildStats,
) -> list[Cluster]:
    """Sélectionne les clusters selon les quotas par groupe thématique."""
    theme_to_group: dict[str, str] = {}
    for group, cfg in quotas.items():
        for theme in cfg["themes"]:
            theme_to_group[theme] = group

    # Tri par taille descendante (les gros clusters sont mieux pour annoter)
    sorted_clusters = sorted(clusters, key=lambda c: len(c.articles), reverse=True)

    selected: list[Cluster] = []
    taken_per_group: dict[str, int] = defaultdict(int)

    for cluster in sorted_clusters:
        group = theme_to_group.get(cluster.theme)
        if group is None:
            continue
        cfg = quotas[group]
        if taken_per_group[group] >= cfg["target_clusters"]:
            continue
        if cluster.distinct_stances < cfg["min_stances"]:
            continue
        # Cap articles par cluster (les plus récents conservés)
        cluster.articles = sorted(
            cluster.articles, key=lambda a: a.published_at, reverse=True
        )[:max_per_cluster]
        selected.append(cluster)
        taken_per_group[group] += 1

    stats.per_group = dict(taken_per_group)
    stats.skipped_themes = [
        g for g, cfg in quotas.items()
        if taken_per_group[g] < cfg["target_clusters"]
    ]
    stats.n_selected = len(selected)
    return selected


def serialize(selected: list[Cluster], model_version: str, quotas: dict[str, dict]) -> dict:
    now = datetime.now(timezone.utc).isoformat()
    return {
        "generated_at": now,
        "schema_version": 1,
        "model_version": model_version,
        "stratification": {g: cfg["target_clusters"] for g, cfg in quotas.items()},
        "clusters": [
            {
                "cluster_key": c.key,
                "cluster_display": c.display,
                "theme": c.theme,
                "reference_article_id": min(
                    c.articles, key=lambda a: a.published_at
                ).id,
                "articles": [
                    {
                        "id": a.id,
                        "title": a.title,
                        "url": a.url,
                        "published_at": a.published_at.isoformat(),
                        "source_name": a.source_name,
                        "source_id": a.source_id,
                        "bias_stance": a.bias_stance,
                        "entities": a.entities,
                        "annotations": {},
                    }
                    for a in sorted(c.articles, key=lambda a: a.published_at)
                ],
            }
            for c in selected
        ],
    }


def print_stats(stats: BuildStats, selected: list[Cluster]) -> None:
    print(f"Articles chargés                 : {stats.n_articles}")
    print(f"Pseudo-clusters bruts (≥min_size): {stats.n_pseudo_clusters}")
    print(f"  après dedup source             : {stats.n_after_source_dedup}")
    print(f"  après fenêtre temporelle       : {stats.n_after_window}")
    print(f"  après filtre 'bien formé'      : {stats.n_well_formed}")
    print(f"Clusters sélectionnés (quotas)   : {stats.n_selected}")
    print("Répartition par groupe :")
    for group, n in sorted(stats.per_group.items()):
        print(f"  - {group:14s} : {n}")
    if stats.skipped_themes:
        print(
            f"⚠️  Quotas non atteints pour : {', '.join(stats.skipped_themes)}",
            file=sys.stderr,
        )
    n_titles = sum(len(c.articles) for c in selected)
    print(f"Titres annotables                : {n_titles}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", required=True, help="Dump JSON brut (cf. docstring)")
    parser.add_argument("--out", default=None, help="Chemin de sortie")
    parser.add_argument("--min-size", type=int, default=4)
    parser.add_argument("--max-per-cluster", type=int, default=7)
    parser.add_argument("--window-hours", type=int, default=36)
    parser.add_argument(
        "--min-pair-ratio",
        type=float,
        default=0.7,
        help="Fraction min des paires qui doivent partager ≥min-shared entités",
    )
    parser.add_argument("--min-shared-entities", type=int, default=2)
    parser.add_argument(
        "--model-version",
        default="v1-spacy-fr_md",
        help="Annoté dans le JSON pour aligner sur la pipeline",
    )
    args = parser.parse_args()

    articles = load_articles(Path(args.raw))
    if not articles:
        print("⚠️  Dump vide.", file=sys.stderr)
        sys.exit(1)

    stats = BuildStats(n_articles=len(articles))
    clusters = build_clusters(
        articles,
        min_size=args.min_size,
        window_hours=args.window_hours,
        min_pair_ratio=args.min_pair_ratio,
        min_shared_entities=args.min_shared_entities,
        stats=stats,
    )
    selected = stratify(clusters, DEFAULT_QUOTAS, args.max_per_cluster, stats)

    payload = serialize(selected, args.model_version, DEFAULT_QUOTAS)

    today = datetime.now(timezone.utc).date().isoformat()
    out_path = (
        Path(args.out)
        if args.out
        else CONTEXT_DIR / f"highlight-dataset-{today}.json"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    print_stats(stats, selected)
    print(f"✅ Dataset écrit : {out_path}")


if __name__ == "__main__":
    main()
