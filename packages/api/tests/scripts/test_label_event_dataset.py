"""Tests hermétiques pour `scripts/label_event_dataset.py`.

L'appel LLM est court-circuité par `EVENT_LABEL_DRY_RUN=1`. Les tests couvrent
le validateur (assignation exactement-une-fois-sinon-NOISE, slug, jamais
d'écrasement d'un article revu), l'itération par mode, et un run dry-run
end-to-end.
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path

from scripts.label_event_dataset import (
    apply_partition,
    iter_pools_to_label,
    partition_pool,
    pool_is_reviewed,
    resolve_assignment,
    run,
    slugify,
)


def _toy_dataset() -> dict:
    return {
        "pools": [
            {
                "pool_key": "trump",
                "pool_display": "Trump",
                "seed_entity": {"name": "Trump", "type": "PERSON"},
                "events": [],
                "articles": [
                    {"id": "A0", "title": "Trump frappe l'Iran", "event_id": None,
                     "label_reviewed": False},
                    {"id": "A1", "title": "Trump et l'Iran", "event_id": None,
                     "label_reviewed": False},
                    {"id": "A2", "title": "Trump hué au NBA", "event_id": None,
                     "label_reviewed": False},
                ],
            },
            {
                "pool_key": "macron",
                "pool_display": "Macron",
                "seed_entity": {"name": "Macron", "type": "PERSON"},
                "events": [],
                "articles": [
                    {"id": "B0", "title": "Macron à Berlin", "event_id": "gold-evt",
                     "label_reviewed": True},
                    {"id": "B1", "title": "Macron en Allemagne", "event_id": None,
                     "label_reviewed": False},
                ],
            },
        ],
    }


# ---------------------------------------------------------------------------
# slugify
# ---------------------------------------------------------------------------


def test_slugify_strips_accents_and_punct():
    assert slugify("Iran-Israël: frappes!") == "iran-israel-frappes"
    assert slugify("  ") == "event"
    assert slugify("NBA Finals") == "nba-finals"


# ---------------------------------------------------------------------------
# resolve_assignment : exactly-once-or-NOISE
# ---------------------------------------------------------------------------


def test_resolve_assignment_exactly_once_or_noise():
    partition = {
        "events": [
            {"event_id": "evt-a", "label": "A", "article_indices": [0, 1]},
            {"event_id": "evt-b", "label": "B", "article_indices": [1, 2]},
        ],
        "noise_indices": [3],
    }
    assignment, labels = resolve_assignment(partition, n=4)
    assert assignment[0] == "evt-a"  # exactement une fois
    assert assignment[1] == "NOISE"  # double-assigné → NOISE
    assert assignment[2] == "evt-b"
    assert assignment[3] == "NOISE"  # jamais assigné → NOISE
    assert labels["evt-a"] == "A"


def test_resolve_assignment_ignores_out_of_range_indices():
    partition = {"events": [{"event_id": "x", "article_indices": [0, 99, -1]}]}
    assignment, _ = resolve_assignment(partition, n=2)
    assert assignment[0] == "x"
    assert assignment[1] == "NOISE"


def test_resolve_assignment_slugifies_labels():
    partition = {"events": [{"label": "Iran & Israël", "article_indices": [0]}]}
    assignment, labels = resolve_assignment(partition, n=1)
    assert assignment[0] == "iran-israel"
    assert "iran-israel" in labels


# ---------------------------------------------------------------------------
# apply_partition : jamais d'écrasement d'un article revu
# ---------------------------------------------------------------------------


def test_apply_partition_skips_reviewed_articles():
    pool = _toy_dataset()["pools"][1]  # macron : B0 revu, B1 non
    partition = {"events": [{"event_id": "evt-x", "article_indices": [0, 1]}]}
    written = apply_partition(pool, partition, skip_reviewed=True)
    assert pool["articles"][0]["event_id"] == "gold-evt"  # intact
    assert pool["articles"][1]["event_id"] == "evt-x"
    assert pool["articles"][1]["label_source"] == "llm_pass1"
    assert written == 1


def test_apply_partition_builds_events_list():
    pool = _toy_dataset()["pools"][0]
    partition = {
        "events": [{"event_id": "iran", "label": "Iran", "article_indices": [0, 1]}],
        "noise_indices": [2],
    }
    apply_partition(pool, partition, skip_reviewed=True)
    events = {e["event_id"]: e for e in pool["events"]}
    assert events["iran"]["size"] == 2
    assert events["NOISE"]["size"] == 1


def test_apply_partition_blind_writes_shadow_field():
    pool = _toy_dataset()["pools"][1]
    partition = {"events": [{"event_id": "evt-x", "article_indices": [0, 1]}]}
    apply_partition(
        pool, partition, target_field="event_id_blind", skip_reviewed=False
    )
    # event_id (gold) intact ; le champ fantôme reçoit la prédiction
    assert pool["articles"][0]["event_id"] == "gold-evt"
    assert pool["articles"][0]["event_id_blind"] == "evt-x"


# ---------------------------------------------------------------------------
# iter_pools_to_label : modes
# ---------------------------------------------------------------------------


def test_pool_is_reviewed():
    ds = _toy_dataset()
    assert pool_is_reviewed(ds["pools"][0]) is False
    assert pool_is_reviewed(ds["pools"][1]) is True


def test_iter_fill_yields_only_unreviewed_pools():
    out = list(iter_pools_to_label(_toy_dataset(), mode="fill"))
    assert [p["pool_key"] for p, _ in out] == ["trump"]


def test_iter_blind_yields_only_reviewed_pools():
    out = list(iter_pools_to_label(_toy_dataset(), mode="blind"))
    assert [p["pool_key"] for p, _ in out] == ["macron"]


def test_iter_all_yields_both():
    out = list(iter_pools_to_label(_toy_dataset(), mode="all"))
    assert {p["pool_key"] for p, _ in out} == {"trump", "macron"}


# ---------------------------------------------------------------------------
# Dry-run stub
# ---------------------------------------------------------------------------


def test_partition_pool_dry_run(monkeypatch):
    monkeypatch.setenv("EVENT_LABEL_DRY_RUN", "1")
    pool = _toy_dataset()["pools"][0]
    partition = asyncio.run(partition_pool(client=None, pool=pool))
    # 1 événement par article
    assert len(partition["events"]) == 3
    assert partition["events"][0]["article_indices"] == [0]


# ---------------------------------------------------------------------------
# run() end-to-end dry-run
# ---------------------------------------------------------------------------


def test_run_dry_fill_labels_unreviewed_only(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("EVENT_LABEL_DRY_RUN", "1")
    ds_path = tmp_path / "ds.json"
    ds_path.write_text(json.dumps(_toy_dataset()), encoding="utf-8")
    out_path = tmp_path / "out.json"

    asyncio.run(
        run(
            dataset_path=ds_path,
            mode="fill",
            model="mistral-large-latest",
            out_path=out_path,
            limit=None,
        )
    )

    out = json.loads(out_path.read_text(encoding="utf-8"))
    trump = next(p for p in out["pools"] if p["pool_key"] == "trump")
    macron = next(p for p in out["pools"] if p["pool_key"] == "macron")
    # pool trump (non revu) étiqueté : 1 event/article (dry-run)
    assert all(a["event_id"] is not None for a in trump["articles"])
    # pool macron est revu → mode fill l'ignore : B1 reste non étiqueté
    assert macron["articles"][0]["event_id"] == "gold-evt"
    assert macron["articles"][1]["event_id"] is None
