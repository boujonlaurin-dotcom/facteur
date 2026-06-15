"""Construit le dataset annotable « appartenance à un événement » pour la
calibration de la *porte de cohérence sujet* des perspectives
(cf. `docs/maintenance/maintenance-clustering-calibration.md`).

Contrairement à `build_highlight_dataset.py`, on ne cherche PAS des clusters
« bien formés » : on veut des **pools lâches** seedés par l'entité la plus
saillante (Trump, Macron, …) qui mélangent plusieurs événements distincts —
c'est exactement là que la fuite de faux-positifs de la branche
« weak double signal » se voit. Le LLM (puis le PO) re-partitionne ensuite
chaque pool par événement concret (`label_event_dataset.py`).

Workflow :
    1. Le PO extrait un dump brut via MCP Supabase (SELECT incluant
       **topics ET entities**, cf. doc de maintenance).
    2. Ce script :
       a. groupe les articles en pools par entité PERSON/ORG/EVENT partagée
          (réutilise `build_pseudo_clusters` de `inspect_title_annotations.py`),
       b. applique une fenêtre temporelle + un cap de taille par pool
          (PAS de dédup par source ni de filtre « ≥2 entités » — on garde
          les pools gras),
       c. stratifie par thème (quotas comptés **en pools**),
       d. sérialise le dataset annotable (`event_id: null` par article).

Forme du dump d'entrée (sur-ensemble du format de
`inspect_title_annotations.py`) :

    {
      "generated_at": "2026-06-09T15:00:00Z",
      "articles": [
        {
          "id": "uuid", "title": "...", "url": "...",
          "published_at": "2026-06-08T08:00:00Z",
          "source_name": "Le Monde", "source_id": "uuid",
          "bias_stance": "center-left", "theme": "international",
          "topics": ["geopolitics", "middleeast"],
          "entities": ["{\"name\": \"Trump\", \"type\": \"PERSON\"}", ...]
        }, ...
      ]
    }

Usage :
    cd packages/api && source venv/bin/activate
    python scripts/build_event_dataset.py \\
        --raw ../../.context/raw-articles-2026-06-09.json \\
        --out ../../.context/gold-events-2026-06-09.json

Sortie :
    JSON sérialisé (schéma documenté dans la doc de maintenance).
"""

import argparse
import json
import os
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from scripts.build_highlight_dataset import DEFAULT_QUOTAS  # noqa: E402
from scripts.inspect_title_annotations import (  # noqa: E402
    DISCRIMINANT_TYPES,
    build_pseudo_clusters,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

NOISE_EVENT_ID = "NOISE"


@dataclass
class EventArticle:
    """Article porteur de `topics` (en plus des champs du highlight Article)."""

    id: str
    title: str
    url: str
    published_at: datetime
    source_name: str
    source_id: str
    bias_stance: str
    theme: str
    topics: list[str]
    entities: list[str]

    def entity_keys(self) -> list[tuple[str, str]]:
        """(key=lower, display) par entité PERSON/ORG/EVENT — comme le highlight Article.

        Requis par `build_pseudo_clusters`, qui seede les pools par entité
        discriminante partagée.
        """
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

    def entity_type(self, name_lower: str) -> str | None:
        """Type déclaré pour l'entité nommée `name_lower` (None si absente)."""
        for raw in self.entities or []:
            try:
                obj = json.loads(raw)
            except (ValueError, TypeError):
                continue
            if (obj.get("name") or "").strip().lower() == name_lower:
                return obj.get("type")
        return None


@dataclass
class Pool:
    key: str
    display: str
    articles: list[EventArticle]
    theme: str = ""
    seed_type: str = "PERSON"


@dataclass
class BuildStats:
    n_articles: int = 0
    n_pseudo_pools: int = 0
    n_after_window: int = 0
    n_selected: int = 0
    per_group: dict[str, int] = field(default_factory=dict)
    skipped_themes: list[str] = field(default_factory=list)


def load_articles(path: Path) -> list[EventArticle]:
    data = json.loads(path.read_text(encoding="utf-8"))
    out: list[EventArticle] = []
    for a in data["articles"]:
        out.append(
            EventArticle(
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
                topics=list(a.get("topics") or []),
                entities=list(a.get("entities") or []),
            )
        )
    return out


def filter_window(arts: list[EventArticle], hours: int) -> list[EventArticle]:
    """Garde les articles publiés ≤ `hours` avant le plus récent du pool.

    Reproduit le `cutoff = now - time_window_hours` de
    `search_internal_perspectives` (la porte ne voit que des candidats
    récents), appliqué relativement au pool plutôt qu'à « now » pour rester
    reproductible sur un dump figé.
    """
    if not arts:
        return arts
    latest = max(a.published_at for a in arts)
    cutoff = latest - timedelta(hours=hours)
    return [a for a in arts if a.published_at >= cutoff]


def pick_theme(arts: list[EventArticle]) -> str:
    counts = Counter(a.theme for a in arts if a.theme)
    if not counts:
        return ""
    return counts.most_common(1)[0][0]


def _seed_type(key: str, arts: list[EventArticle]) -> str:
    """Type déclaré de l'entité seed (premier article qui la porte)."""
    for a in arts:
        t = a.entity_type(key)
        if t:
            return t
    return "PERSON"


def build_pools(
    articles: list[EventArticle],
    min_size: int,
    window_hours: int,
    max_per_pool: int,
    stats: BuildStats,
) -> list[Pool]:
    """Pools lâches par entité partagée + fenêtre + cap de taille.

    Volontairement PAS de dédup par source ni de filtre « ≥2 entités » : on
    veut des paires intra-événement multi-sources ET des pools qui se scindent.
    """
    raw = build_pseudo_clusters(articles, min_size=min_size, top_n=10_000)
    stats.n_pseudo_pools = len(raw)

    pools: list[Pool] = []
    for key, display, arts in raw:
        windowed = filter_window(arts, window_hours)
        if len(windowed) < min_size:
            continue
        stats.n_after_window += 1
        capped = sorted(windowed, key=lambda a: a.published_at, reverse=True)[
            :max_per_pool
        ]
        pools.append(
            Pool(
                key=key,
                display=display,
                articles=capped,
                theme=pick_theme(capped),
                seed_type=_seed_type(key, capped),
            )
        )
    return pools


def stratify_pools(
    pools: list[Pool],
    quotas: dict[str, dict],
    seeds_per_theme: int | None,
    stats: BuildStats,
) -> list[Pool]:
    """Sélectionne les plus gros pools par groupe thématique.

    `seeds_per_theme` (si fourni) écrase le `target_clusters` de chaque groupe.
    Tri par taille descendante : les pools gras (≥3 événements) sont prioritaires
    car c'est là que la fuite FP est observable.
    """
    theme_to_group: dict[str, str] = {}
    for group, cfg in quotas.items():
        for theme in cfg["themes"]:
            theme_to_group[theme] = group

    targets = {
        group: (seeds_per_theme if seeds_per_theme is not None else cfg["target_clusters"])
        for group, cfg in quotas.items()
    }

    sorted_pools = sorted(pools, key=lambda p: len(p.articles), reverse=True)
    selected: list[Pool] = []
    taken: dict[str, int] = defaultdict(int)
    for pool in sorted_pools:
        group = theme_to_group.get(pool.theme)
        if group is None:
            continue
        if taken[group] >= targets[group]:
            continue
        selected.append(pool)
        taken[group] += 1

    stats.per_group = dict(taken)
    stats.skipped_themes = [g for g, t in targets.items() if taken[g] < t]
    stats.n_selected = len(selected)
    return selected


def serialize_events(
    selected: list[Pool], window_hours: int, quotas: dict[str, dict]
) -> dict:
    now = datetime.now(UTC).isoformat()
    return {
        "generated_at": now,
        "schema_version": 1,
        "dataset_kind": "event_membership",
        "seed_window_hours": window_hours,
        "stratification": {
            g: cfg["target_clusters"] for g, cfg in quotas.items()
        },
        "pools": [
            {
                "pool_key": p.key,
                "pool_display": p.display,
                "seed_entity": {"name": p.display, "type": p.seed_type},
                "theme": p.theme,
                "events": [],
                "articles": [
                    {
                        "id": a.id,
                        "title": a.title,
                        "url": a.url,
                        "published_at": a.published_at.isoformat(),
                        "source_name": a.source_name,
                        "source_id": a.source_id,
                        "bias_stance": a.bias_stance,
                        "theme": a.theme,
                        "topics": a.topics,
                        "entities": a.entities,
                        "event_id": None,
                        "label_source": None,
                        "label_reviewed": False,
                        "label_confidence": None,
                        "label_notes": "",
                    }
                    for a in sorted(p.articles, key=lambda a: a.published_at)
                ],
            }
            for p in selected
        ],
    }


def print_stats(stats: BuildStats, selected: list[Pool]) -> None:
    print(f"Articles chargés                 : {stats.n_articles}")
    print(f"Pseudo-pools bruts (≥min_size)   : {stats.n_pseudo_pools}")
    print(f"  après fenêtre temporelle       : {stats.n_after_window}")
    print(f"Pools sélectionnés (quotas)      : {stats.n_selected}")
    print("Répartition par groupe :")
    for group, n in sorted(stats.per_group.items()):
        print(f"  - {group:14s} : {n}")
    if stats.skipped_themes:
        print(
            f"⚠️  Quotas non atteints pour : {', '.join(stats.skipped_themes)}",
            file=sys.stderr,
        )
    n_articles = sum(len(p.articles) for p in selected)
    print(f"Articles à étiqueter             : {n_articles}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", required=True, help="Dump JSON brut (cf. docstring)")
    parser.add_argument("--out", default=None, help="Chemin de sortie")
    parser.add_argument("--min-size", type=int, default=6)
    parser.add_argument("--max-per-pool", type=int, default=30)
    parser.add_argument("--window-hours", type=int, default=72)
    parser.add_argument(
        "--seeds-per-theme",
        type=int,
        default=None,
        help="Écrase le target_clusters de chaque groupe (sinon DEFAULT_QUOTAS)",
    )
    args = parser.parse_args()

    articles = load_articles(Path(args.raw))
    if not articles:
        print("⚠️  Dump vide.", file=sys.stderr)
        sys.exit(1)

    stats = BuildStats(n_articles=len(articles))
    pools = build_pools(
        articles,
        min_size=args.min_size,
        window_hours=args.window_hours,
        max_per_pool=args.max_per_pool,
        stats=stats,
    )
    selected = stratify_pools(pools, DEFAULT_QUOTAS, args.seeds_per_theme, stats)

    payload = serialize_events(selected, args.window_hours, DEFAULT_QUOTAS)

    today = datetime.now(UTC).date().isoformat()
    out_path = (
        Path(args.out) if args.out else CONTEXT_DIR / f"gold-events-{today}.json"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print_stats(stats, selected)
    print(f"✅ Dataset écrit : {out_path}")


if __name__ == "__main__":
    main()
