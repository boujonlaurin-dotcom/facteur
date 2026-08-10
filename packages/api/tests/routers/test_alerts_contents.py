"""`GET /api/alerts` porte les contenus déclencheurs (story 30.4).

La carte « Tes alertes » de la Tournée ne pouvait pas montrer l'article : le
payload n'en contenait aucun. Ces tests verrouillent les trois propriétés qui
comptent — le contenu est là, l'ancien client ne casse pas, et le coût en
requêtes reste borné par le plafond de 5 cloches.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import event

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.models.user_topic_profile import UserTopicProfile
from app.routers.alerts import ALERT_CONTENT_LIMIT
from app.services.alert_cadence import ALERT_CAP

NOW = datetime.now(UTC)

#: Champs que le client `production` (une semaine de retard sur `main`) lit sans
#: condition. Aucun ne doit disparaître ni changer de type.
V1_ITEM_FIELDS = {
    "kind",
    "source_id",
    "source_name",
    "source_logo_url",
    "filtered",
    "articles_30d",
    "cadence_per_week",
    "last_published_at",
    "last_alert_sent_at",
    "new_content",
}


class _QueryCounter:
    """Compteur de requêtes SQL réelles (hors SAVEPOINT de la fixture)."""

    def __init__(self) -> None:
        self.count = 0

    def _on_execute(self, conn, cursor, statement, parameters, context, executemany):
        upper = statement.lstrip().upper()
        if upper.startswith(("SAVEPOINT", "RELEASE", "ROLLBACK")):
            return
        self.count += 1

    def attach(self, sync_conn):
        event.listen(sync_conn, "before_cursor_execute", self._on_execute)

    def detach(self, sync_conn):
        event.remove(sync_conn, "before_cursor_execute", self._on_execute)


@pytest_asyncio.fixture
async def alert_user(db_session):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Alert Contents User",
            onboarding_completed=True,
        )
    )
    await db_session.commit()

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    try:
        yield user_id
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _make_source(db_session, *, name: str) -> Source:
    source = Source(
        id=uuid4(),
        name=name,
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
        logo_url=f"https://logo.example/{name}.png",
    )
    db_session.add(source)
    await db_session.flush()
    return source


async def _add_content(
    db_session,
    source: Source,
    *,
    title: str,
    hours_ago: float = 1,
    entity: str | None = None,
) -> Content:
    content = Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        thumbnail_url="https://img.example/x.jpg",
        guid=str(uuid4()),
        published_at=NOW - timedelta(hours=hours_ago),
        content_type=ContentType.ARTICLE,
        theme="society",
        entities=[f'{{"name": "{entity}", "type": "EVENT"}}'] if entity else None,
    )
    db_session.add(content)
    await db_session.flush()
    return content


async def _bell_on_source(db_session, user_id, source: Source) -> None:
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            notify=True,
        )
    )


async def _bell_on_topic(db_session, user_id, *, name: str) -> UserTopicProfile:
    profile = UserTopicProfile(
        user_id=user_id,
        topic_name=name,
        slug_parent="sport",
        canonical_name=name,
        keywords=[],
        state=InterestState.FOLLOWED,
        notify=True,
    )
    db_session.add(profile)
    await db_session.flush()
    return profile


@pytest.mark.asyncio
async def test_source_alert_carries_its_fresh_contents(alert_user, db_session):
    """La cloche source ramène ses articles frais, du plus récent au plus vieux."""
    source = await _make_source(db_session, name="Le Mensuel")
    await _add_content(db_session, source, title="Vieux titre", hours_ago=5)
    await _add_content(db_session, source, title="Titre du milieu", hours_ago=3)
    await _add_content(db_session, source, title="Titre le plus frais", hours_ago=1)
    await _bell_on_source(db_session, alert_user, source)
    await db_session.commit()

    async with _client() as client:
        response = await client.get("/api/alerts")

    item = response.json()["items"][0]
    assert item["new_content"] == 3
    titles = [c["title"] for c in item["contents"]]
    assert titles == ["Titre le plus frais", "Titre du milieu", "Vieux titre"]
    first = item["contents"][0]
    assert first["source_name"] == "Le Mensuel"
    assert first["source_logo_url"].endswith("Le Mensuel.png")
    assert first["content_id"]
    assert first["url"]
    assert first["content_type"] == "article"


@pytest.mark.asyncio
async def test_contents_are_capped_and_exclude_read_articles(alert_user, db_session):
    """Plafond à `ALERT_CONTENT_LIMIT`, et un article lu ne remonte pas."""
    source = await _make_source(db_session, name="La Revue")
    read = await _add_content(db_session, source, title="Déjà lu", hours_ago=0.5)
    for i in range(5):
        await _add_content(db_session, source, title=f"Frais {i}", hours_ago=i + 1)
    db_session.add(
        UserContentStatus(
            user_id=alert_user,
            content_id=read.id,
            status=ContentStatus.CONSUMED,
        )
    )
    await _bell_on_source(db_session, alert_user, source)
    await db_session.commit()

    async with _client() as client:
        response = await client.get("/api/alerts")

    item = response.json()["items"][0]
    assert item["new_content"] == 5
    assert len(item["contents"]) == ALERT_CONTENT_LIMIT
    assert "Déjà lu" not in [c["title"] for c in item["contents"]]


@pytest.mark.asyncio
async def test_topic_alert_carries_contents_from_varied_sources(alert_user, db_session):
    """Le vrai gain d'une alerte sujet : voir *qui* a publié quoi.

    C'est aussi la fin du bug « liste vide » — la cible d'un tap n'est plus un
    `source_id` inventé à partir de `user_topic_profiles.id`, c'est un contenu.
    """
    lequipe = await _make_source(db_session, name="L'Équipe")
    ouest = await _make_source(db_session, name="Ouest-France")
    await _add_content(
        db_session,
        lequipe,
        title="Ligue 1 chez L'Équipe",
        hours_ago=2,
        entity="Ligue 1",
    )
    await _add_content(
        db_session, ouest, title="Ligue 1 chez Ouest", hours_ago=1, entity="Ligue 1"
    )
    await _bell_on_topic(db_session, alert_user, name="Ligue 1")
    await db_session.commit()

    async with _client() as client:
        response = await client.get("/api/alerts")

    item = next(i for i in response.json()["items"] if i["kind"] == "topic")
    assert item["source_name"] == "Ligue 1"  # la cloche porte le sujet…
    # …mais chaque contenu porte le média qui a réellement publié.
    assert {c["source_name"] for c in item["contents"]} == {
        "L'Équipe",
        "Ouest-France",
    }
    assert item["contents"][0]["title"] == "Ligue 1 chez Ouest"
    assert all(c["source_id"] for c in item["contents"])


@pytest.mark.asyncio
async def test_no_contents_when_nothing_is_fresh(alert_user, db_session):
    """Cloche silencieuse : `contents` vide, pas de ligne fantôme côté carte."""
    source = await _make_source(db_session, name="Le Silencieux")
    await _add_content(db_session, source, title="Vieil article", hours_ago=72)
    await _bell_on_source(db_session, alert_user, source)
    await db_session.commit()

    async with _client() as client:
        response = await client.get("/api/alerts")

    item = response.json()["items"][0]
    assert item["new_content"] == 0
    assert item["contents"] == []


@pytest.mark.asyncio
async def test_payload_stays_backward_compatible(alert_user, db_session):
    """Un client v1 parse la réponse à l'identique : `contents` est additif."""
    source = await _make_source(db_session, name="Le Mensuel")
    await _add_content(db_session, source, title="Frais", hours_ago=1)
    await _bell_on_source(db_session, alert_user, source)
    topic = await _bell_on_topic(db_session, alert_user, name="Ligue 1")
    await db_session.commit()

    async with _client() as client:
        response = await client.get("/api/alerts")

    payload = response.json()
    assert set(payload) == {"cap", "active_count", "items"}
    assert payload["cap"] == ALERT_CAP
    for item in payload["items"]:
        # Tous les champs v1 sont là, avec le même type qu'avant.
        assert set(item) >= V1_ITEM_FIELDS
        assert isinstance(item["new_content"], int)
        assert isinstance(item["articles_30d"], int)
        assert isinstance(item["cadence_per_week"], float)
        # Le seul ajout.
        assert set(item) - V1_ITEM_FIELDS == {"contents"}
    topic_item = next(i for i in payload["items"] if i["kind"] == "topic")
    assert topic_item["source_id"] == str(topic.id)


@pytest.mark.asyncio
async def test_query_count_stays_bounded_by_the_cap(alert_user, db_session):
    """Le plafond de 5 cloches est le garde-fou : pas de N+1 non borné.

    Cas le plus coûteux : 5 cloches **sujet** (le prédicat sujet n'a pas de
    `source_id` à partitionner, donc chacune paie ses agrégations). Le bloc
    source, lui, tient en un nombre constant de requêtes quel que soit le
    nombre de cloches.
    """
    source = await _make_source(db_session, name="Multi")
    for i in range(ALERT_CAP):
        await _add_content(
            db_session,
            source,
            title=f"Sujet {i} vient de sortir",
            hours_ago=i + 1,
            entity=f"Sujet {i}",
        )
        await _bell_on_topic(db_session, alert_user, name=f"Sujet {i}")
    await db_session.commit()

    counter = _QueryCounter()
    raw_conn = (await db_session.connection()).sync_connection
    counter.attach(raw_conn)
    try:
        async with _client() as client:
            response = await client.get("/api/alerts")
    finally:
        counter.detach(raw_conn)

    items = response.json()["items"]
    assert len(items) == ALERT_CAP
    assert all(i["contents"] for i in items)
    # Mesuré : 18 = 1 (cloches source, vide) + 1 (profils) + 1 (dernier envoi)
    # + 5 × 3 (stats 30 j, compteur de frais, contenus).
    assert counter.count <= 20, f"{counter.count} requêtes pour {ALERT_CAP} cloches"
