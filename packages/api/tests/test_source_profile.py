"""Tests de l'endpoint `/sources/{id}/profile` (fiche source v3).

Endpoint unifié : identité source + couverture par thèmes (30 j) +
`articles_30d` + `oldest_content_at` (hors fenêtre) + 10 articles récents
(objets `Content` complets, cliquables côté mobile ; la fiche en montre 3 par
défaut et déroule jusqu'à 10 via « Lire plus »).

Couvre :
- happy path : source + 4 contents → recent_articles (source imbriquée),
  theme_distribution cohérent (counts/parts), articles_30d correct ;
- cap : ≥10 contents → recent_articles plafonné à 10 ;
- fenêtre 30 j : un content à 40 j exclu du volume/distribution mais reflété
  par `oldest_content_at` ;
- 404 source inconnue ;
- source sans contents → listes vides, articles_30d=0, oldest_content_at=None.
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
from app.models.enums import ContentType, InterestState, SourceType
from app.models.source import Source, UserSource


def _content(source_id, *, theme, days_ago=0, title="Article"):
    """Construit un Content minimal valide pour les tests de profil."""
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
async def profile_client(db_session):
    """Source de test + client HTTP authentifié (overrides db/user)."""
    source = Source(
        id=uuid4(),
        name="Profile Source",
        url="https://profile.example.com",
        feed_url=f"https://profile.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        logo_url="https://profile.example.com/logo.png",
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
async def test_profile_happy_path(profile_client):
    """Source riche : recent_articles (≤3, source imbriquée), distribution, volume."""
    ac, source, db = profile_client
    # politics x3, tech x1 (total 4, tous < 30 j)
    for i in range(3):
        db.add(_content(source.id, theme="politics", days_ago=i, title=f"Pol {i}"))
    db.add(_content(source.id, theme="tech", days_ago=5, title="Tech"))
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/profile")
    assert resp.status_code == 200
    body = resp.json()

    # Identité source.
    assert body["source"]["id"] == str(source.id)
    assert body["source"]["name"] == "Profile Source"

    # Volume = total fenêtre 30 j.
    assert body["articles_30d"] == 4

    # Distribution : politics (3) avant tech (1), parts cohérentes.
    dist = body["theme_distribution"]
    assert [d["theme"] for d in dist] == ["politics", "tech"]
    assert [d["count"] for d in dist] == [3, 1]
    assert dist[0]["share"] == pytest.approx(0.75)
    assert dist[1]["share"] == pytest.approx(0.25)
    assert sum(d["count"] for d in dist) == body["articles_30d"]

    # Articles récents : max 10, triés desc, source imbriquée complète.
    # Ici 4 contents (< 10) → les 4 remontent.
    recent = body["recent_articles"]
    assert len(recent) == 4
    first = recent[0]
    assert first["source"]["id"] == str(source.id)
    assert first["source"]["name"] == "Profile Source"
    assert first["source"]["logo_url"] == "https://profile.example.com/logo.png"
    # Tri chronologique décroissant (days_ago 0 → 1 → 2 → 5).
    titles = [r["title"] for r in recent]
    assert titles == ["Pol 0", "Pol 1", "Pol 2", "Tech"]

    # oldest_content_at = le plus ancien (tech, 5 j).
    assert body["oldest_content_at"] is not None


@pytest.mark.asyncio
async def test_profile_recent_articles_capped_at_10(profile_client):
    """≥10 contents → recent_articles plafonné à 10 (les 10 plus récents)."""
    ac, source, db = profile_client
    # 14 contents, tous < 30 j, days_ago croissant → titres 0..13.
    for i in range(14):
        db.add(_content(source.id, theme="politics", days_ago=i, title=f"A{i}"))
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/profile")
    assert resp.status_code == 200
    body = resp.json()

    recent = body["recent_articles"]
    assert len(recent) == 10
    # Les 10 plus récents (days_ago 0..9), triés desc.
    assert [r["title"] for r in recent] == [f"A{i}" for i in range(10)]


@pytest.mark.asyncio
async def test_profile_window_excludes_old_but_oldest_reflects_it(profile_client):
    """Un content à 40 j : exclu du volume/distribution, reflété par oldest_content_at."""
    ac, source, db = profile_client
    db.add(_content(source.id, theme="politics", days_ago=1, title="Récent"))
    old = _content(source.id, theme="tech", days_ago=40, title="Vieux")
    db.add(old)
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/profile")
    assert resp.status_code == 200
    body = resp.json()

    # Volume + distribution n'incluent QUE l'article récent.
    assert body["articles_30d"] == 1
    assert [d["theme"] for d in body["theme_distribution"]] == ["politics"]

    # recent_articles ignore la fenêtre → les 2 contents remontent (≤3).
    assert len(body["recent_articles"]) == 2

    # oldest_content_at = la date du vieux content (hors fenêtre).
    oldest = datetime.fromisoformat(body["oldest_content_at"])
    assert oldest < datetime.now(UTC) - timedelta(days=35)


@pytest.mark.asyncio
async def test_profile_null_theme_excluded_from_distribution(profile_client):
    """Non classés (theme NULL) : hors distribution, mais comptés dans articles_30d.

    `articles_30d` reste le volume publié réel (frais non classé compris) pour
    ne pas fausser la fréquence ; la distribution ne porte que sur les classés,
    dont les `share` totalisent 1.0.
    """
    ac, source, db = profile_client
    for i in range(3):
        db.add(_content(source.id, theme="politics", days_ago=i, title=f"Pol {i}"))
    for i in range(2):
        db.add(_content(source.id, theme=None, days_ago=i, title=f"NULL {i}"))
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/profile")
    assert resp.status_code == 200
    body = resp.json()

    # Volume = tous les articles publiés (3 classés + 2 non classés).
    assert body["articles_30d"] == 5

    dist = body["theme_distribution"]
    assert [d["theme"] for d in dist] == ["politics"]
    assert dist[0]["count"] == 3
    # share sur les classés (3/3), pas sur le volume publié (3/5).
    assert dist[0]["share"] == pytest.approx(1.0)
    # La somme des counts de la distribution (3) est < articles_30d (5) : les
    # non classés sont exclus de la couverture mais présents dans le volume.
    assert sum(d["count"] for d in dist) < body["articles_30d"]


@pytest.mark.asyncio
async def test_profile_all_null_hides_distribution(profile_client):
    """Tout non classé → distribution vide (section masquée), volume gardé."""
    ac, source, db = profile_client
    for i in range(4):
        db.add(_content(source.id, theme=None, days_ago=i, title=f"NULL {i}"))
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/profile")
    assert resp.status_code == 200
    body = resp.json()

    assert body["theme_distribution"] == []
    assert body["articles_30d"] == 4


@pytest.mark.asyncio
async def test_profile_unknown_source_returns_404(profile_client):
    """Source inconnue → 404."""
    ac, _source, _db = profile_client
    resp = await ac.get(f"/api/sources/{uuid4()}/profile")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_profile_empty_source(profile_client):
    """Source sans contents → listes vides, volume 0, oldest None."""
    ac, source, _db = profile_client
    resp = await ac.get(f"/api/sources/{source.id}/profile")
    assert resp.status_code == 200
    body = resp.json()

    assert body["recent_articles"] == []
    assert body["theme_distribution"] == []
    assert body["articles_30d"] == 0
    assert body["oldest_content_at"] is None


@pytest.mark.asyncio
async def test_profile_follower_count_counts_followed_and_favorite(profile_client):
    """`follower_count` = utilisateurs en état suivi/favori, hors masqué/neutre."""
    ac, source, db = profile_client
    # 2 suivis + 1 favori = 3 abonnés ; 1 masqué + 1 neutre exclus.
    states = [
        InterestState.FOLLOWED,
        InterestState.FOLLOWED,
        InterestState.FAVORITE,
        InterestState.HIDDEN,
        InterestState.UNFOLLOWED,
    ]
    for st in states:
        db.add(UserSource(user_id=uuid4(), source_id=source.id, state=st))
    await db.commit()

    resp = await ac.get(f"/api/sources/{source.id}/profile")
    assert resp.status_code == 200
    assert resp.json()["source"]["follower_count"] == 3


@pytest.mark.asyncio
async def test_profile_follower_count_zero_without_followers(profile_client):
    """Aucun abonné → follower_count = 0 (et non absent)."""
    ac, source, _db = profile_client
    resp = await ac.get(f"/api/sources/{source.id}/profile")
    assert resp.status_code == 200
    assert resp.json()["source"]["follower_count"] == 0
