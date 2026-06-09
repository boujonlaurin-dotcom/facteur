"""Tests hermétiques pour `scripts/build_event_dataset.py`.

Couvre le seeding des pools par entité partagée, la fenêtre temporelle, le cap
de taille, la stratification par thème (comptée en pools), et la sérialisation
(`event_id: null`, prêt à étiqueter).
"""

import json
from datetime import UTC, datetime, timedelta
from pathlib import Path

from scripts.build_event_dataset import (
    BuildStats,
    EventArticle,
    build_pools,
    filter_window,
    load_articles,
    serialize_events,
    stratify_pools,
)
from scripts.build_highlight_dataset import DEFAULT_QUOTAS

BASE = datetime(2026, 6, 8, 12, 0, 0, tzinfo=UTC)


def _entity(name: str, type_: str = "PERSON") -> str:
    return json.dumps({"name": name, "type": type_})


def _art(
    aid: str,
    entity: str,
    *,
    theme: str = "international",
    topics=None,
    hours_ago: int = 0,
    source: str | None = None,
) -> EventArticle:
    return EventArticle(
        id=aid,
        title=f"Titre {aid} {entity}",
        url=f"https://example.com/{aid}",
        published_at=BASE - timedelta(hours=hours_ago),
        source_name=source or f"src-{aid}",
        source_id=source or f"src-{aid}",
        bias_stance="center",
        theme=theme,
        topics=topics or ["geopolitics"],
        entities=[_entity(entity)],
    )


def _pool_of(entity: str, n: int, **kw) -> list[EventArticle]:
    return [_art(f"{entity}-{i}", entity, **kw) for i in range(n)]


# ---------------------------------------------------------------------------
# load_articles porte topics
# ---------------------------------------------------------------------------


def test_load_articles_carries_topics(tmp_path: Path):
    raw = {
        "articles": [
            {
                "id": "a1",
                "title": "T",
                "url": "u",
                "published_at": "2026-06-08T08:00:00Z",
                "source_name": "Le Monde",
                "source_id": "s1",
                "bias_stance": "center",
                "theme": "international",
                "topics": ["geopolitics", "middleeast"],
                "entities": [_entity("Trump")],
            }
        ]
    }
    p = tmp_path / "raw.json"
    p.write_text(json.dumps(raw), encoding="utf-8")
    arts = load_articles(p)
    assert len(arts) == 1
    assert arts[0].topics == ["geopolitics", "middleeast"]
    assert arts[0].entity_keys() == [("trump", "Trump")]


# ---------------------------------------------------------------------------
# build_pools : seeding par entité partagée, fenêtre, cap
# ---------------------------------------------------------------------------


def test_build_pools_seeds_by_shared_entity():
    arts = _pool_of("Trump", 3) + _pool_of("Macron", 3)
    stats = BuildStats(n_articles=len(arts))
    pools = build_pools(arts, min_size=3, window_hours=72, max_per_pool=30, stats=stats)
    keys = {p.key for p in pools}
    assert keys == {"trump", "macron"}
    trump = next(p for p in pools if p.key == "trump")
    assert trump.seed_type == "PERSON"
    assert trump.display == "Trump"
    assert len(trump.articles) == 3


def test_build_pools_drops_pool_below_min_size_after_window():
    # 2 articles récents + 2 hors fenêtre → après fenêtre 72h il reste 2 < min 3
    arts = _pool_of("Trump", 2, hours_ago=0) + _pool_of("Trump", 2, hours_ago=200)
    # renommer les ids pour éviter collision
    for i, a in enumerate(arts):
        a.id = f"trump-{i}"
    stats = BuildStats(n_articles=len(arts))
    pools = build_pools(arts, min_size=3, window_hours=72, max_per_pool=30, stats=stats)
    assert pools == []


def test_build_pools_caps_pool_size_keeping_recent():
    arts = [_art(f"trump-{i}", "Trump", hours_ago=i) for i in range(10)]
    stats = BuildStats(n_articles=len(arts))
    pools = build_pools(arts, min_size=3, window_hours=72, max_per_pool=4, stats=stats)
    assert len(pools) == 1
    pool = pools[0]
    assert len(pool.articles) == 4
    # les 4 plus récents (hours_ago 0..3)
    kept_ids = {a.id for a in pool.articles}
    assert kept_ids == {"trump-0", "trump-1", "trump-2", "trump-3"}


def test_filter_window_keeps_within_window_of_latest():
    arts = [
        _art("a", "Trump", hours_ago=0),
        _art("b", "Trump", hours_ago=50),
        _art("c", "Trump", hours_ago=100),
    ]
    kept = filter_window(arts, hours=72)
    assert {a.id for a in kept} == {"a", "b"}


# ---------------------------------------------------------------------------
# stratify_pools : quotas comptés en pools
# ---------------------------------------------------------------------------


def test_stratify_pools_respects_seeds_per_theme_override():
    arts = _pool_of("Trump", 5) + _pool_of("Macron", 4) + _pool_of("Biden", 3)
    stats = BuildStats(n_articles=len(arts))
    pools = build_pools(arts, min_size=3, window_hours=72, max_per_pool=30, stats=stats)
    selected = stratify_pools(pools, DEFAULT_QUOTAS, seeds_per_theme=2, stats=stats)
    assert len(selected) == 2
    # les 2 plus gros pools d'abord (Trump=5, Macron=4)
    assert {p.key for p in selected} == {"trump", "macron"}


def test_stratify_pools_skips_unknown_theme():
    arts = _pool_of("Trump", 3, theme="theme-inexistant")
    stats = BuildStats(n_articles=len(arts))
    pools = build_pools(arts, min_size=3, window_hours=72, max_per_pool=30, stats=stats)
    selected = stratify_pools(pools, DEFAULT_QUOTAS, seeds_per_theme=5, stats=stats)
    assert selected == []


# ---------------------------------------------------------------------------
# serialize_events : event_id null, prêt à étiqueter
# ---------------------------------------------------------------------------


def test_serialize_events_shape_ready_to_label():
    arts = _pool_of("Trump", 3, topics=["geopolitics", "middleeast"])
    stats = BuildStats(n_articles=len(arts))
    pools = build_pools(arts, min_size=3, window_hours=72, max_per_pool=30, stats=stats)
    payload = serialize_events(pools, window_hours=72, quotas=DEFAULT_QUOTAS)

    assert payload["dataset_kind"] == "event_membership"
    assert payload["seed_window_hours"] == 72
    assert len(payload["pools"]) == 1
    pool = payload["pools"][0]
    assert pool["seed_entity"] == {"name": "Trump", "type": "PERSON"}
    assert pool["events"] == []
    for art in pool["articles"]:
        assert art["event_id"] is None
        assert art["label_reviewed"] is False
        assert art["topics"] == ["geopolitics", "middleeast"]
        # entities portées verbatim (chaînes JSON)
        assert art["entities"] == [_entity("Trump")]
