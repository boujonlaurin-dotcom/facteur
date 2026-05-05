"""Tests pour le router /api/letters (Story 19.1 — Lettres du Facteur).

Couvre :
- État initial pour un new user (L0 archived, L1 active, L2 upcoming).
- Auto-détection des 4 actions de L1.
- Chaînage L1 → L2 quand toutes les actions sont cochées.
- Idempotence du refresh.
- Cross-tenant : un user ne voit pas les rows d'un autre.
- 404 sur letter_id inconnu.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.analytics import AnalyticsEvent
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentType, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.models.user_letter_progress import UserLetterProgress
from app.models.user_topic_profile import UserTopicProfile

# ─── Fixtures ──────────────────────────────────────────────────────────────


@pytest_asyncio.fixture
async def auth_user(db_session):
    user_id = uuid4()
    profile = UserProfile(
        user_id=user_id,
        display_name="Letters Test User",
        onboarding_completed=True,
    )
    db_session.add(profile)
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
    transport = ASGITransport(app=app)
    return AsyncClient(transport=transport, base_url="http://test")


async def _add_topics(db_session, user_id: UUID, count: int) -> None:
    for i in range(count):
        db_session.add(
            UserTopicProfile(
                user_id=user_id,
                topic_name=f"Topic {i}",
                slug_parent="custom",
                source_type="explicit",
            )
        )
    await db_session.commit()


async def _add_sources(db_session, user_id: UUID, total: int, custom: int) -> None:
    """Crée `total` user_sources dont `custom` avec is_custom=True."""
    for i in range(total):
        src = Source(
            id=uuid4(),
            name=f"Source {i}",
            url=f"https://src-{i}.example.com",
            feed_url=f"https://src-{i}.example.com/feed-{uuid4()}.xml",
            type=SourceType.ARTICLE,
            theme="society",
            is_active=True,
        )
        db_session.add(src)
        await db_session.flush()
        db_session.add(
            UserSource(
                user_id=user_id,
                source_id=src.id,
                is_custom=i < custom,
            )
        )
    await db_session.commit()


async def _add_perspectives_event(db_session, user_id: UUID) -> None:
    db_session.add(
        AnalyticsEvent(
            user_id=user_id,
            event_type="perspectives_opened",
            event_data={"content_id": str(uuid4())},
        )
    )
    await db_session.commit()


async def _add_event(db_session, user_id: UUID, event_type: str) -> None:
    db_session.add(
        AnalyticsEvent(
            user_id=user_id,
            event_type=event_type,
            event_data={},
        )
    )
    await db_session.commit()


async def _make_source(db_session) -> Source:
    src = Source(
        id=uuid4(),
        name=f"Src {uuid4()}",
        url=f"https://src-{uuid4()}.example.com",
        feed_url=f"https://src-{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
    )
    db_session.add(src)
    await db_session.flush()
    return src


async def _add_user_content_status(
    db_session,
    user_id: UUID,
    *,
    content_type: ContentType,
    reading_progress: int = 0,
    time_spent_seconds: int = 0,
    is_liked: bool = False,
) -> None:
    src = await _make_source(db_session)
    content = Content(
        id=uuid4(),
        source_id=src.id,
        title="t",
        url=f"https://x/{uuid4()}",
        published_at=datetime.now(UTC),
        content_type=content_type,
        guid=str(uuid4()),
    )
    db_session.add(content)
    await db_session.flush()
    db_session.add(
        UserContentStatus(
            user_id=user_id,
            content_id=content.id,
            reading_progress=reading_progress,
            time_spent_seconds=time_spent_seconds,
            is_liked=is_liked,
        )
    )
    await db_session.commit()


async def _activate_l2(db_session, user_id: UUID) -> None:
    """Force L2 active (bypass auto-archivage L1) en posant les rows initiales
    avec L1 archivée et L2 active."""
    now = datetime.now(UTC)
    db_session.add_all(
        [
            UserLetterProgress(
                user_id=user_id,
                letter_id="letter_0",
                status="archived",
                completed_actions=[],
                archived_at=now,
            ),
            UserLetterProgress(
                user_id=user_id,
                letter_id="letter_1",
                status="archived",
                completed_actions=[],
                started_at=now,
                archived_at=now,
            ),
            UserLetterProgress(
                user_id=user_id,
                letter_id="letter_2",
                status="active",
                completed_actions=[],
                started_at=now,
            ),
        ]
    )
    await db_session.commit()


# ─── Tests ─────────────────────────────────────────────────────────────────


class TestInitialState:
    async def test_new_user_returns_three_letters(self, auth_user):
        async with _client() as ac:
            resp = await ac.get("/api/letters")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 3

        l0, l1, l2 = data
        assert l0["id"] == "letter_0"
        assert l0["status"] == "archived"
        assert l0["progress"] == 1.0
        assert l0["archived_at"] is not None
        assert l0["actions"] == []

        assert l1["id"] == "letter_1"
        assert l1["status"] == "active"
        assert l1["completed_actions"] == []
        assert l1["progress"] == 0.0
        assert l1["started_at"] is not None
        assert len(l1["actions"]) == 4

        assert l2["id"] == "letter_2"
        assert l2["status"] == "upcoming"

    async def test_get_is_idempotent(self, auth_user):
        async with _client() as ac:
            resp1 = await ac.get("/api/letters")
            resp2 = await ac.get("/api/letters")
        assert resp1.status_code == 200
        assert resp2.status_code == 200
        # Pas de doublons en DB après un 2e GET
        assert len(resp2.json()) == 3


class TestAutoDetection:
    async def test_define_editorial_line_detected(self, auth_user, db_session):
        await _add_topics(db_session, auth_user, 3)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_1/refresh-status")

        assert resp.status_code == 200
        assert "define_editorial_line" in resp.json()["completed_actions"]

    async def test_editorial_line_below_threshold_not_detected(
        self, auth_user, db_session
    ):
        await _add_topics(db_session, auth_user, 2)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_1/refresh-status")

        assert "define_editorial_line" not in resp.json()["completed_actions"]

    async def test_sources_actions_detected(self, auth_user, db_session):
        await _add_sources(db_session, auth_user, total=5, custom=2)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_1/refresh-status")

        completed = resp.json()["completed_actions"]
        assert "add_5_sources" in completed
        assert "add_2_personal_sources" in completed

    async def test_perspectives_event_detected(self, auth_user, db_session):
        await _add_perspectives_event(db_session, auth_user)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_1/refresh-status")

        assert "first_perspectives_open" in resp.json()["completed_actions"]


class TestChaining:
    async def test_l1_archived_unlocks_l2(self, auth_user, db_session):
        await _add_topics(db_session, auth_user, 3)
        await _add_sources(db_session, auth_user, total=5, custom=2)
        await _add_perspectives_event(db_session, auth_user)

        async with _client() as ac:
            refresh_resp = await ac.post("/api/letters/letter_1/refresh-status")
            list_resp = await ac.get("/api/letters")

        assert refresh_resp.status_code == 200
        l1_data = refresh_resp.json()
        assert l1_data["status"] == "archived"
        assert l1_data["archived_at"] is not None
        assert l1_data["progress"] == 1.0

        l0, l1, l2 = list_resp.json()
        assert l1["status"] == "archived"
        assert l2["status"] == "active"
        assert l2["started_at"] is not None


class TestIdempotence:
    async def test_refresh_twice_same_state(self, auth_user, db_session):
        await _add_topics(db_session, auth_user, 3)

        async with _client() as ac:
            r1 = await ac.post("/api/letters/letter_1/refresh-status")
            r2 = await ac.post("/api/letters/letter_1/refresh-status")

        assert r1.json()["completed_actions"] == r2.json()["completed_actions"]
        assert r1.json()["status"] == r2.json()["status"]

    async def test_archived_letter_not_unarchived_on_refresh(
        self, auth_user, db_session
    ):
        # Archive L1 manuellement
        await _add_topics(db_session, auth_user, 3)
        await _add_sources(db_session, auth_user, total=5, custom=2)
        await _add_perspectives_event(db_session, auth_user)

        async with _client() as ac:
            await ac.post("/api/letters/letter_1/refresh-status")
            # Re-call → ne change rien
            r2 = await ac.post("/api/letters/letter_1/refresh-status")

        assert r2.json()["status"] == "archived"


class TestCrossTenant:
    async def test_other_user_data_not_visible(self, auth_user, db_session):
        # Crée un autre user avec des rows
        other_id = uuid4()
        other_profile = UserProfile(
            user_id=other_id,
            display_name="Other User",
            onboarding_completed=True,
        )
        db_session.add(other_profile)
        # Ajoute des rows letter_progress pour other user
        for letter_id, status in [
            ("letter_0", "archived"),
            ("letter_1", "archived"),
            ("letter_2", "active"),
        ]:
            db_session.add(
                UserLetterProgress(
                    user_id=other_id,
                    letter_id=letter_id,
                    status=status,
                    completed_actions=[],
                    started_at=datetime.now(UTC),
                )
            )
        await db_session.commit()

        # Le user authentifié ne voit que ses propres rows (init pour lui)
        async with _client() as ac:
            resp = await ac.get("/api/letters")

        data = resp.json()
        assert len(data) == 3
        assert data[0]["status"] == "archived"  # L0
        assert data[1]["status"] == "active"  # L1 par défaut
        assert data[2]["status"] == "upcoming"  # L2 par défaut


class TestErrors:
    async def test_unknown_letter_id_returns_404(self, auth_user):
        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_xxx/refresh-status")
        assert resp.status_code == 404


# ─── Lettre 2 — Tes premières lectures ─────────────────────────────────────


class TestLetter2Detection:
    async def test_read_first_essentiel_detected(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)
        await _add_event(db_session, auth_user, "digest_opened")

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert resp.status_code == 200
        assert "read_first_essentiel" in resp.json()["completed_actions"]

    async def test_read_first_bonnes_nouvelles_detected(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)
        await _add_event(db_session, auth_user, "bonnes_nouvelles_opened")

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_first_bonnes_nouvelles" in resp.json()["completed_actions"]

    async def test_read_3_long_articles_detected(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)
        for _ in range(3):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                reading_progress=95,
                time_spent_seconds=120,
            )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_3_long_articles" in resp.json()["completed_actions"]

    async def test_read_3_long_articles_below_threshold_not_detected(
        self, auth_user, db_session
    ):
        await _activate_l2(db_session, auth_user)
        # 2 articles seulement → pas détecté
        for _ in range(2):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                reading_progress=95,
                time_spent_seconds=120,
            )
        # 1 article avec time_spent insuffisant → ne doit pas compter
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.ARTICLE,
            reading_progress=95,
            time_spent_seconds=30,
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_3_long_articles" not in resp.json()["completed_actions"]

    async def test_read_first_video_podcast_detected(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.YOUTUBE,
            time_spent_seconds=300,
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_first_video_podcast" in resp.json()["completed_actions"]

    async def test_recommend_first_article_detected(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.ARTICLE,
            is_liked=True,
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "recommend_first_article" in resp.json()["completed_actions"]


class TestLetter2Shape:
    async def test_l2_exposes_narrative_fields(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)

        async with _client() as ac:
            resp = await ac.get("/api/letters")

        l2 = next(letter for letter in resp.json() if letter["id"] == "letter_2")
        assert l2["status"] == "active"
        assert isinstance(l2.get("intro_palier"), str) and l2["intro_palier"]
        assert isinstance(l2.get("completion_voeu"), str) and l2["completion_voeu"]
        assert len(l2["actions"]) == 5
        for action in l2["actions"]:
            assert isinstance(action.get("completion_palier"), str)
            assert action["completion_palier"]

    async def test_l1_does_not_expose_l2_only_fields(self, auth_user):
        async with _client() as ac:
            resp = await ac.get("/api/letters")

        l1 = next(letter for letter in resp.json() if letter["id"] == "letter_1")
        # L1 ne définit ni intro_palier ni completion_voeu : champs absents.
        assert "intro_palier" not in l1
        assert "completion_voeu" not in l1
        for action in l1["actions"]:
            assert "completion_palier" not in action


class TestLetter2Idempotence:
    async def test_archived_l2_stays_archived(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)
        # Cocher toutes les actions
        await _add_event(db_session, auth_user, "digest_opened")
        await _add_event(db_session, auth_user, "bonnes_nouvelles_opened")
        for _ in range(3):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                reading_progress=95,
                time_spent_seconds=120,
            )
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.PODCAST,
            time_spent_seconds=300,
        )
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.ARTICLE,
            is_liked=True,
        )

        async with _client() as ac:
            r1 = await ac.post("/api/letters/letter_2/refresh-status")
            r2 = await ac.post("/api/letters/letter_2/refresh-status")

        assert r1.json()["status"] == "archived"
        assert r2.json()["status"] == "archived"
        assert len(r1.json()["completed_actions"]) == 5
