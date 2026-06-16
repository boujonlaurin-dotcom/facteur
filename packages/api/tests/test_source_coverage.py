"""Tests de l'endpoint coverage et de l'extension `theme` sur recent-items.

Story 7.8 — Refonte fiche source v2 (WS-A backend).

Couvre :
- agrégation par thème (counts, pct, tri décroissant) ;
- exclusion de la fenêtre temporelle (articles plus vieux que `days`) ;
- regroupement de la longue traîne (>top N) + thèmes NULL dans « autres » ;
- source vide → rows: [], total 0 ;
- `recent-items` renvoie désormais `theme` (et None si content.theme est NULL).
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source


def _content(source_id, *, theme, days_ago=0, title="Article"):
    """Construit un Content minimal valide pour les tests d'agrégation."""
    return Content(
        id=uuid4(),
        source_id=source_id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=datetime.now(UTC) - timedelta(days=days_ago),
        content_type=ContentType.ARTICLE,
        theme=theme,
    )


@pytest_asyncio.fixture
async def coverage_client(db_session):
    """Source de test + client HTTP authentifié, avec overrides db/user."""
    source = Source(
        id=uuid4(),
        name="Coverage Source",
        url="https://coverage.example.com",
        feed_url=f"https://coverage.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()

    user_id = uuid4()

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac, source, db_session
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_coverage_aggregates_themes_with_pct_and_order(coverage_client):
    """Plusieurs thèmes : counts exacts, pct arrondis, tri décroissant."""
    ac, source, db = coverage_client
    # politics x5, tech x3, science x2 (total 10) → pct 50/30/20
    for _ in range(5):
        db.add(_content(source.id, theme="politics", days_ago=1))
    for _ in range(3):
        db.add(_content(source.id, theme="tech", days_ago=1))
    for _ in range(2):
        db.add(_content(source.id, theme="science", days_ago=1))
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/coverage?days=30")
    assert resp.status_code == 200
    body = resp.json()

    assert body["period_label"] == "30 derniers jours"
    assert body["total_count"] == 10
    # Espace fine insécable (U+202F) absente pour <1000, mais pluriel respecté.
    assert body["caption"] == "10 articles publiés sur la période"

    rows = body["rows"]
    assert [r["theme"] for r in rows] == ["politics", "tech", "science"]
    assert [r["count"] for r in rows] == [5, 3, 2]
    assert [r["pct"] for r in rows] == [50, 30, 20]


@pytest.mark.asyncio
async def test_coverage_excludes_articles_outside_window(coverage_client):
    """Les articles plus vieux que `days` ne comptent pas."""
    ac, source, db = coverage_client
    db.add(_content(source.id, theme="politics", days_ago=2))  # dans la fenêtre
    db.add(_content(source.id, theme="politics", days_ago=2))  # dans la fenêtre
    db.add(_content(source.id, theme="tech", days_ago=20))  # hors fenêtre (days=7)
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/coverage?days=7")
    assert resp.status_code == 200
    body = resp.json()

    assert body["period_label"] == "7 derniers jours"
    assert body["total_count"] == 2
    assert [r["theme"] for r in body["rows"]] == ["politics"]
    assert body["rows"][0]["count"] == 2


@pytest.mark.asyncio
async def test_coverage_long_tail_grouped_into_autres(coverage_client):
    """Au-delà du top 6, la traîne et les thèmes NULL vont dans « autres »."""
    ac, source, db = coverage_client
    # 8 thèmes nommés à volumes décroissants : t1=8 ... t8=1, + 4 NULL.
    for idx, count in enumerate(range(8, 0, -1), start=1):
        for _ in range(count):
            db.add(_content(source.id, theme=f"t{idx}", days_ago=1))
    for _ in range(4):
        db.add(_content(source.id, theme=None, days_ago=1))
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/coverage?days=30")
    assert resp.status_code == 200
    body = resp.json()

    # total = sum(8..1) + 4 NULL = 36 + 4 = 40
    assert body["total_count"] == 40

    rows = body["rows"]
    # 6 thèmes en tête + 1 ligne « autres »
    assert len(rows) == 7
    assert [r["theme"] for r in rows[:6]] == ["t1", "t2", "t3", "t4", "t5", "t6"]
    autres = rows[-1]
    assert autres["theme"] == "autres"
    # « autres » = t7(2) + t8(1) + 4 NULL = 7
    assert autres["count"] == 7
    # Tri décroissant strict en tête
    counts = [r["count"] for r in rows[:6]]
    assert counts == sorted(counts, reverse=True)


@pytest.mark.asyncio
async def test_coverage_empty_source_returns_empty(coverage_client):
    """Source sans article dans la fenêtre → rows: [], total 0."""
    ac, source, _db = coverage_client
    resp = await ac.get(f"/api/sources/{source.id}/coverage?days=30")
    assert resp.status_code == 200
    body = resp.json()

    assert body["rows"] == []
    assert body["total_count"] == 0
    assert body["caption"] == "Aucun article publié sur la période"
    assert body["period_label"] == "30 derniers jours"


@pytest.mark.asyncio
async def test_coverage_thousands_separator_and_singular(coverage_client):
    """Caption FR : espace fine insécable pour >=1000, singulier pour 1."""
    ac, source, db = coverage_client
    db.add(_content(source.id, theme="politics", days_ago=1))
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/coverage?days=30")
    body = resp.json()
    assert body["total_count"] == 1
    assert body["caption"] == "1 article publié sur la période"


@pytest.mark.asyncio
async def test_coverage_days_param_validation(coverage_client):
    """`days` hors bornes (ge=1, le=365) → 422."""
    ac, source, _db = coverage_client
    assert (
        await ac.get(f"/api/sources/{source.id}/coverage?days=0")
    ).status_code == 422
    assert (
        await ac.get(f"/api/sources/{source.id}/coverage?days=366")
    ).status_code == 422


@pytest.mark.asyncio
async def test_recent_items_includes_theme(coverage_client):
    """recent-items renvoie `theme` (présent et None quand content.theme NULL)."""
    ac, source, db = coverage_client
    db.add(_content(source.id, theme="politics", days_ago=0, title="Avec thème"))
    db.add(_content(source.id, theme=None, days_ago=1, title="Sans thème"))
    await db.commit()

    resp = await ac.post(
        "/api/sources/recent-items",
        json={"source_ids": [str(source.id)], "per_source": 3},
    )
    assert resp.status_code == 200
    body = resp.json()

    assert len(body["sources"]) == 1
    items = body["sources"][0]["items"]
    # Tri par published_at desc : "Avec thème" (0j) en premier.
    by_title = {it["title"]: it for it in items}
    assert "theme" in by_title["Avec thème"]
    assert by_title["Avec thème"]["theme"] == "politics"
    assert by_title["Sans thème"]["theme"] is None
