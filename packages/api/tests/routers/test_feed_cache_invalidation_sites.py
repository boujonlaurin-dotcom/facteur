"""Which write endpoints purge the whole feed cache, and which purge one article.

The filet that was missing. `POST /contents/{id}/status` in SEEN is fired on
every scroll, and it used to call `FEED_CACHE.invalidate()` — scrolling three
articles annihilated the ~12 cached Tournée sections, so the cache never paid
off at cold-open. Scoping it to the touched article is the whole point of the
change; the tests below pin both halves of the rule:

- **Targeted** (`invalidate_content`) — writes that only change one article's
  display state.
- **Full** (`invalidate`) — writes that adjust `UserSubtopic.weight` /
  `UserEntityAffinity.affinity`, i.e. rebalance the **ranking** of every
  section. Scoping those would leave a stale order everywhere else, which is
  why the "stays full" cases below are explicit guards against a future
  over-optimisation.
"""

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.models.user import UserProfile
from app.services.feed_cache import FEED_CACHE

BASE_DT = datetime(2026, 6, 1, 12, 0, tzinfo=UTC)

# Two cached sections: one that displays the article being written to, one
# that does not. A targeted invalidation must purge only the first.
MATCHING_VARIANT = "p|t=tech|tp=None|s=None|sr=0|l=12"
OTHER_VARIANT = "p|t=science|tp=None|s=None|sr=0|l=12"


@pytest_asyncio.fixture
async def user_id() -> UUID:
    return uuid4()


@pytest_asyncio.fixture
async def auth_client(db_session, user_id):
    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest_asyncio.fixture
async def article(db_session, user_id) -> Content:
    # `user_interests` FKs to `user_profiles`; the weight-adjusting writes
    # below insert into it.
    db_session.add(UserProfile(user_id=user_id))
    source = Source(
        id=uuid4(),
        name="Test Source",
        url="https://example.com",
        feed_url=f"https://example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.flush()
    content = Content(
        id=uuid4(),
        source_id=source.id,
        title="Un article",
        url=f"https://example.com/{uuid4()}",
        published_at=BASE_DT - timedelta(hours=2),
        content_type=ContentType.ARTICLE,
        guid=str(uuid4()),
        is_serene=True,
    )
    db_session.add(content)
    await db_session.commit()
    # Tests and endpoints share one session (the `get_db` override). Left in
    # the identity map, `session.get(Content, ...)` inside
    # `_adjust_subtopic_weights` would return this instance without applying
    # its `selectinload(Content.source)`, and reading `content.source` would
    # then lazy-load outside a greenlet. Production gets a fresh session per
    # request; expunging reproduces that.
    db_session.expunge_all()
    return content


@pytest.fixture
def seed_cache(feed_cache_payload):
    """Cache two sections for a user: one showing the article, one not."""

    def _seed(user_id: UUID, content_id: UUID) -> None:
        FEED_CACHE.put(
            user_id, feed_cache_payload(content_id), variant=MATCHING_VARIANT
        )
        FEED_CACHE.put(user_id, feed_cache_payload(uuid4()), variant=OTHER_VARIANT)

    return _seed


def _assert_targeted(user_id: UUID) -> None:
    assert FEED_CACHE.get(user_id, variant=MATCHING_VARIANT) is None
    assert FEED_CACHE.get(user_id, variant=OTHER_VARIANT) is not None


def _assert_full(user_id: UUID) -> None:
    assert FEED_CACHE.get(user_id, variant=MATCHING_VARIANT) is None
    assert FEED_CACHE.get(user_id, variant=OTHER_VARIANT) is None


# --- Targeted: display-state-only writes -----------------------------------


@pytest.mark.asyncio
async def test_seen_status_purges_only_matching_sections(
    auth_client, article, user_id, seed_cache
):
    """The dominant write — emitted on every scroll."""
    seed_cache(user_id, article.id)

    resp = await auth_client.post(
        f"/api/contents/{article.id}/status", json={"status": "seen"}
    )

    assert resp.status_code == 200, resp.text
    assert resp.json()["transitioned_to_consumed"] is False
    _assert_targeted(user_id)


@pytest.mark.asyncio
async def test_impress_purges_only_matching_sections(
    auth_client, article, user_id, seed_cache
):
    seed_cache(user_id, article.id)

    resp = await auth_client.post(f"/api/contents/{article.id}/impress")

    assert resp.status_code == 200, resp.text
    _assert_targeted(user_id)


@pytest.mark.asyncio
async def test_unsave_purges_only_matching_sections(
    auth_client, article, user_id, seed_cache
):
    await auth_client.post(f"/api/contents/{article.id}/save")
    seed_cache(user_id, article.id)

    resp = await auth_client.delete(f"/api/contents/{article.id}/save")

    assert resp.status_code == 200, resp.text
    _assert_targeted(user_id)


@pytest.mark.asyncio
async def test_unhide_purges_only_matching_sections(
    auth_client, article, user_id, seed_cache
):
    await auth_client.post(f"/api/contents/{article.id}/hide")
    seed_cache(user_id, article.id)

    resp = await auth_client.delete(f"/api/contents/{article.id}/hide")

    assert resp.status_code == 200, resp.text
    _assert_targeted(user_id)


@pytest.mark.asyncio
async def test_note_delete_purges_only_matching_sections(
    auth_client, article, user_id, seed_cache
):
    """Erasing `note_text` does not undo the weights boosted at upsert."""
    await auth_client.put(
        f"/api/contents/{article.id}/note", json={"note_text": "ma note"}
    )
    seed_cache(user_id, article.id)

    resp = await auth_client.delete(f"/api/contents/{article.id}/note")

    assert resp.status_code == 200, resp.text
    _assert_targeted(user_id)


# --- Full: ranking-affecting writes ----------------------------------------


@pytest.mark.asyncio
async def test_consumed_status_purges_everything(
    auth_client, article, user_id, seed_cache
):
    """The CONSUMED transition adjusts subtopic weights + entity affinity."""
    seed_cache(user_id, article.id)

    resp = await auth_client.post(
        f"/api/contents/{article.id}/status",
        json={"status": "consumed", "time_spent_seconds": 60},
    )

    assert resp.status_code == 200, resp.text
    assert resp.json()["transitioned_to_consumed"] is True
    _assert_full(user_id)


@pytest.mark.asyncio
async def test_like_stays_full(auth_client, article, user_id, seed_cache):
    seed_cache(user_id, article.id)

    resp = await auth_client.post(f"/api/contents/{article.id}/like")

    assert resp.status_code == 200, resp.text
    _assert_full(user_id)


@pytest.mark.asyncio
async def test_save_stays_full(auth_client, article, user_id, seed_cache):
    seed_cache(user_id, article.id)

    resp = await auth_client.post(f"/api/contents/{article.id}/save")

    assert resp.status_code == 200, resp.text
    _assert_full(user_id)


@pytest.mark.asyncio
async def test_hide_stays_full(auth_client, article, user_id, seed_cache):
    seed_cache(user_id, article.id)

    resp = await auth_client.post(f"/api/contents/{article.id}/hide")

    assert resp.status_code == 200, resp.text
    _assert_full(user_id)


@pytest_asyncio.fixture
async def article_feedback_table(db_session):
    """`article_feedback` is Alembic-only — it is not registered in
    `Base.metadata`, so conftest's `create_all` never creates it and
    `POST /feedback` would 500 on an undefined relation.

    Created on the test's own connection, so the DDL rolls back with the
    surrounding transaction. Imported lazily: at module scope it would land
    in `Base.metadata` before the session-scoped `create_tables` runs and
    silently change the schema of the whole suite.
    """
    from app.models.article_feedback import ArticleFeedback

    conn = await db_session.connection()
    await conn.run_sync(ArticleFeedback.__table__.create, checkfirst=True)


@pytest.mark.asyncio
async def test_feedback_stays_full(
    auth_client, article, user_id, seed_cache, article_feedback_table
):
    seed_cache(user_id, article.id)

    resp = await auth_client.post(
        f"/api/contents/{article.id}/feedback", json={"sentiment": "positive"}
    )

    assert resp.status_code == 200, resp.text
    _assert_full(user_id)


@pytest.mark.asyncio
async def test_note_upsert_purges_everything(auth_client, article, user_id, seed_cache):
    """Boosts subtopic weights like a bookmark. Invalidated nothing before."""
    seed_cache(user_id, article.id)

    resp = await auth_client.put(
        f"/api/contents/{article.id}/note", json={"note_text": "ma note"}
    )

    assert resp.status_code == 200, resp.text
    _assert_full(user_id)


# --- Cross-user ------------------------------------------------------------


@pytest.mark.asyncio
async def test_report_not_serene_purges_every_user(
    auth_client, article, user_id, seed_cache
):
    """`is_serene=False` is a global flip on the Content — purging only the
    reporter would keep serving the article to the other users."""
    other_user = uuid4()
    seed_cache(user_id, article.id)
    seed_cache(other_user, article.id)

    resp = await auth_client.post(f"/api/contents/{article.id}/report-not-serene")

    assert resp.status_code == 200, resp.text
    _assert_targeted(user_id)
    _assert_targeted(other_user)


# --- The invariant the byte scan rests on ----------------------------------


def test_cached_payload_item_ids_match_str_uuid(feed_response_factory):
    """`invalidate_content` scans the serialized payload for `str(content_id)`.

    Pin the serialization it depends on: a change that stopped emitting ids
    verbatim (compression, int ids, a binary codec) would silently turn every
    scoped invalidation into a no-op — stale content served after a write,
    with no test failing. This is that test.
    """
    content_id = uuid4()
    response = feed_response_factory(content_ids=[content_id])

    # Exactly the serialization `get_personalized_feed` caches.
    payload = json.dumps(response.model_dump(mode="json")).encode("utf-8")

    assert str(content_id).encode() in payload
