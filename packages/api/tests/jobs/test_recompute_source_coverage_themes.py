"""Tests du job `recompute_source_coverage_themes` (story 22.5).

Le job dérive `Source.coverage_themes` (couverture éditoriale data-driven) à
partir du volume par thème des `contents` classifiés sur 90 j. On teste la
**math du gate** (part/count/cap/exclusion primaire), l'idempotence, et le fait
qu'il n'écrit JAMAIS `secondary_themes`.

Session mockée (pas de DB) : `session.execute` est dispatché par le SQL de la
requête, exactement comme les tests des jobs de `test_scheduler.py`. Les lignes
d'agrégation sont fournies canned, on inspecte les params de l'UPDATE final.
"""

from contextlib import asynccontextmanager
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

import pytest

from app.jobs.recompute_source_coverage_themes import (
    _MIN_COUNT,
    _MIN_PART,
    _MIN_SOURCE_VOLUME,
    _TOP_N,
    recompute_source_coverage_themes,
)


def _fetchall(rows):
    m = Mock()
    m.fetchall = Mock(return_value=rows)
    return m


async def _run(agg_rows, primary_rows, current_rows):
    """Exécute le job avec des lignes canned, renvoie (stats, update_params).

    `update_params` = la liste de dicts passée à l'UPDATE final (None si aucun
    UPDATE n'a été émis).
    """
    captured: dict[str, object] = {"update_params": None, "update_sql": None}

    async def _execute(statement, params=None):
        sql = str(statement)
        if "GROUP BY source_id, theme" in sql:
            return _fetchall(agg_rows)
        if "SELECT id::text AS id, theme FROM sources" in sql:
            return _fetchall(primary_rows)
        if "coverage_themes FROM sources" in sql:
            return _fetchall(current_rows)
        if "UPDATE sources SET coverage_themes" in sql:
            captured["update_params"] = params
            captured["update_sql"] = sql
            return Mock()
        raise AssertionError(f"unexpected SQL: {sql}")

    session = AsyncMock()
    session.execute = AsyncMock(side_effect=_execute)
    session.commit = AsyncMock()

    @asynccontextmanager
    async def _sm():
        yield session

    with patch(
        "app.jobs.recompute_source_coverage_themes.safe_async_session",
        side_effect=lambda: _sm(),
    ):
        stats = await recompute_source_coverage_themes()
    return stats, captured


def _agg(source_id, theme_counts):
    return [
        SimpleNamespace(source_id=source_id, theme=t, n=n)
        for t, n in theme_counts.items()
    ]


@pytest.mark.asyncio
async def test_gate_keeps_by_part_or_count_excludes_primary_and_caps_top5():
    # society = primaire (exclu). Total classifié = 110 (≥ _MIN_SOURCE_VOLUME).
    # international 40 ✓ ; environment 20 (.18 ≥ .15) ✓ ;
    # politics 15 (.14 < .15 mais count ≥ 8) ✓ ; science 12 (count ≥ 8) ✓ ;
    # culture 10 (count ≥ 8) ✓ ; economy 9 (count ≥ 8) ✓ ; sport 4 ✗.
    # 6 passent le gate → top-5 par count retire economy (9, le plus faible).
    assert _MIN_SOURCE_VOLUME <= 110
    assert _MIN_PART == 0.15 and _MIN_COUNT == 8 and _TOP_N == 5
    counts = {
        "international": 40,
        "environment": 20,
        "politics": 15,
        "science": 12,
        "culture": 10,
        "economy": 9,
        "sport": 4,
    }
    assert sum(counts.values()) == 110
    stats, cap = await _run(
        agg_rows=_agg("s1", counts),
        primary_rows=[SimpleNamespace(id="s1", theme="society")],
        current_rows=[SimpleNamespace(id="s1", coverage_themes=None)],
    )
    params = cap["update_params"]
    assert params is not None and len(params) == 1
    themes = params[0]["themes"]
    # Gardés triés par count desc, primaire "society" absent, top-5.
    assert themes == ["international", "environment", "politics", "science", "culture"]
    assert "sport" not in themes and "tech" not in themes
    assert stats["sources_updated"] == 1


@pytest.mark.asyncio
async def test_low_volume_source_left_intact():
    # Total 20 < _MIN_SOURCE_VOLUME (30) → aucune dérivation, pas d'UPDATE.
    counts = {"environment": 12, "culture": 8}
    assert sum(counts.values()) < _MIN_SOURCE_VOLUME
    stats, cap = await _run(
        agg_rows=_agg("s1", counts),
        primary_rows=[SimpleNamespace(id="s1", theme="society")],
        current_rows=[],
    )
    assert cap["update_params"] is None
    assert stats["sources_updated"] == 0
    assert stats["sources_skipped_low_volume"] == 1


@pytest.mark.asyncio
async def test_idempotent_no_update_when_unchanged():
    # environment 40, culture 30 (total 70, ≥ seuil) → les deux gardés, triés
    # par count desc. La couverture actuelle est déjà ce set → pas d'UPDATE.
    derived = ["environment", "culture"]
    stats, cap = await _run(
        agg_rows=_agg("s1", {"environment": 40, "culture": 30}),
        primary_rows=[SimpleNamespace(id="s1", theme="society")],
        current_rows=[SimpleNamespace(id="s1", coverage_themes=derived)],
    )
    assert cap["update_params"] is None  # déjà à jour → pas d'écriture
    assert stats["sources_unchanged"] == 1
    assert stats["sources_updated"] == 0


@pytest.mark.asyncio
async def test_writes_coverage_never_secondary_and_filters_null():
    counts = {"environment": 40, "culture": 30}
    _, cap = await _run(
        agg_rows=_agg("s1", counts),
        primary_rows=[SimpleNamespace(id="s1", theme="society")],
        current_rows=[SimpleNamespace(id="s1", coverage_themes=[])],
    )
    sql = cap["update_sql"]
    assert sql is not None
    assert "coverage_themes" in sql
    assert "secondary_themes" not in sql


@pytest.mark.asyncio
async def test_aggregation_query_excludes_null_and_windows():
    # Vérifie que le SQL d'agrégation ne compte QUE les contents classifiés
    # (theme IS NOT NULL) sur la fenêtre (published_at >= :cutoff).
    seen = {}

    async def _execute(statement, params=None):
        sql = str(statement)
        if "GROUP BY source_id, theme" in sql:
            seen["agg_sql"] = sql
            return _fetchall([])
        raise AssertionError(f"unexpected SQL: {sql}")

    session = AsyncMock()
    session.execute = AsyncMock(side_effect=_execute)
    session.commit = AsyncMock()

    @asynccontextmanager
    async def _sm():
        yield session

    with patch(
        "app.jobs.recompute_source_coverage_themes.safe_async_session",
        side_effect=lambda: _sm(),
    ):
        stats = await recompute_source_coverage_themes()

    assert "theme IS NOT NULL" in seen["agg_sql"]
    assert "published_at >= :cutoff" in seen["agg_sql"]
    assert stats["total_examined"] == 0
