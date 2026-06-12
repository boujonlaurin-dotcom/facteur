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

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.analytics import AnalyticsEvent
from app.models.collection import Collection, CollectionItem
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, SourceType
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


async def _add_sources(
    db_session,
    user_id: UUID,
    total: int,
    custom: int,
    *,
    added_at: datetime | None = None,
) -> None:
    """Crée `total` user_sources dont `custom` avec is_custom=True.

    `added_at` permet de simuler des ajouts antérieurs ou postérieurs au
    démarrage de la Lettre 1, ce qui matter pour `_detect_add_2_personal_sources`.
    """
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
        kwargs: dict = {
            "user_id": user_id,
            "source_id": src.id,
            "is_custom": i < custom,
        }
        if added_at is not None:
            kwargs["added_at"] = added_at
        db_session.add(UserSource(**kwargs))
    await db_session.commit()


async def _ensure_letter_1_started(db_session, user_id: UUID) -> datetime:
    """Initialise les rows letter_progress (L1 active) et retourne started_at."""
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
                status="active",
                completed_actions=[],
                started_at=now,
            ),
            UserLetterProgress(
                user_id=user_id,
                letter_id="letter_2",
                status="upcoming",
                completed_actions=[],
            ),
        ]
    )
    await db_session.commit()
    return now


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
    status: ContentStatus = ContentStatus.UNSEEN,
    reading_progress: int = 0,
    time_spent_seconds: int = 0,
    is_liked: bool = False,
    is_saved: bool = False,
    note_text: str | None = None,
    seen_at: datetime | None = None,
) -> UUID:
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
            status=status,
            reading_progress=reading_progress,
            time_spent_seconds=time_spent_seconds,
            is_liked=is_liked,
            is_saved=is_saved,
            note_text=note_text,
            seen_at=seen_at,
        )
    )
    await db_session.commit()
    return content.id


async def _add_collection_items(
    db_session,
    user_id: UUID,
    *,
    content_types: list[ContentType],
    is_default: bool = False,
    is_liked_collection: bool = False,
) -> None:
    collection = Collection(
        id=uuid4(),
        user_id=user_id,
        name=f"Collection {uuid4()}",
        is_default=is_default,
        is_liked_collection=is_liked_collection,
    )
    db_session.add(collection)
    await db_session.flush()

    for content_type in content_types:
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
            CollectionItem(
                collection_id=collection.id,
                content_id=content.id,
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
    async def test_new_user_returns_five_letters(self, auth_user):
        async with _client() as ac:
            resp = await ac.get("/api/letters")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 5

        l0, l1, l2, l3, l4 = data
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
        assert [action["target_route"] for action in l1["actions"]] == [
            "/settings/interests",
            "/settings/sources",
            "/settings/sources/add",
            "/flaner",
        ]

        assert l2["id"] == "letter_2"
        assert l2["status"] == "upcoming"

        assert l3["id"] == "letter_3"
        assert l3["status"] == "upcoming"
        assert len(l3["actions"]) == 5

        assert l4["id"] == "letter_4"
        assert l4["status"] == "upcoming"
        assert len(l4["actions"]) == 4

    async def test_get_is_idempotent(self, auth_user):
        async with _client() as ac:
            resp1 = await ac.get("/api/letters")
            resp2 = await ac.get("/api/letters")
        assert resp1.status_code == 200
        assert resp2.status_code == 200
        # Pas de doublons en DB après un 2e GET
        assert len(resp2.json()) == 5


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
        # L1 doit être démarrée avant l'ajout de sources : `add_2_personal_sources`
        # ne compte que les sources ajoutées après `letter_1.started_at`.
        started_at = await _ensure_letter_1_started(db_session, auth_user)
        await _add_sources(
            db_session,
            auth_user,
            total=5,
            custom=2,
            added_at=started_at + timedelta(seconds=1),
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_1/refresh-status")

        completed = resp.json()["completed_actions"]
        assert "add_5_sources" in completed
        assert "add_2_personal_sources" in completed

    async def test_curated_sources_count_after_letter_1_started(
        self, auth_user, db_session
    ):
        """Régression : 2 sources curées (is_custom=False) ajoutées après le
        démarrage de la Lettre 1 doivent valider `add_2_personal_sources`."""
        started_at = await _ensure_letter_1_started(db_session, auth_user)
        await _add_sources(
            db_session,
            auth_user,
            total=2,
            custom=0,
            added_at=started_at + timedelta(seconds=1),
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_1/refresh-status")

        assert "add_2_personal_sources" in resp.json()["completed_actions"]

    async def test_sources_added_before_letter_1_not_counted(
        self, auth_user, db_session
    ):
        """Les sources ajoutées avant le démarrage de la Lettre 1 (ex.
        onboarding) ne valident pas `add_2_personal_sources`."""
        started_at = await _ensure_letter_1_started(db_session, auth_user)
        await _add_sources(
            db_session,
            auth_user,
            total=3,
            custom=3,
            added_at=started_at - timedelta(hours=1),
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_1/refresh-status")

        assert "add_2_personal_sources" not in resp.json()["completed_actions"]

    async def test_perspectives_event_detected(self, auth_user, db_session):
        await _add_perspectives_event(db_session, auth_user)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_1/refresh-status")

        assert "first_perspectives_open" in resp.json()["completed_actions"]


class TestChaining:
    async def test_l1_archived_unlocks_l2(self, auth_user, db_session):
        started_at = await _ensure_letter_1_started(db_session, auth_user)
        await _add_topics(db_session, auth_user, 3)
        await _add_sources(
            db_session,
            auth_user,
            total=5,
            custom=2,
            added_at=started_at + timedelta(seconds=1),
        )
        await _add_perspectives_event(db_session, auth_user)

        async with _client() as ac:
            refresh_resp = await ac.post("/api/letters/letter_1/refresh-status")
            list_resp = await ac.get("/api/letters")

        assert refresh_resp.status_code == 200
        l1_data = refresh_resp.json()
        assert l1_data["status"] == "archived"
        assert l1_data["archived_at"] is not None
        assert l1_data["progress"] == 1.0

        l0, l1, l2, l3, l4 = list_resp.json()
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
        started_at = await _ensure_letter_1_started(db_session, auth_user)
        await _add_topics(db_session, auth_user, 3)
        await _add_sources(
            db_session,
            auth_user,
            total=5,
            custom=2,
            added_at=started_at + timedelta(seconds=1),
        )
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
        assert len(data) == 5
        assert data[0]["status"] == "archived"  # L0
        assert data[1]["status"] == "active"  # L1 par défaut
        assert data[2]["status"] == "upcoming"  # L2 par défaut
        assert data[3]["status"] == "upcoming"
        assert data[4]["status"] == "upcoming"


class TestErrors:
    async def test_unknown_letter_id_returns_404(self, auth_user):
        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_xxx/refresh-status")
        assert resp.status_code == 404


# ─── Lettre 2 — Premières lectures ─────────────────────────────────────


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

    async def test_read_10_articles_detected(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)
        for idx in range(10):
            kwargs: dict = {"content_type": ContentType.ARTICLE}
            match idx % 5:
                case 0:
                    kwargs["time_spent_seconds"] = 1
                case 1:
                    kwargs["reading_progress"] = 1
                case 2:
                    kwargs["status"] = ContentStatus.SEEN
                case 3:
                    kwargs["status"] = ContentStatus.CONSUMED
                case _:
                    kwargs["seen_at"] = datetime.now(UTC)
            await _add_user_content_status(db_session, auth_user, **kwargs)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_3_long_articles" in resp.json()["completed_actions"]

    async def test_read_10_articles_below_threshold_not_detected(
        self, auth_user, db_session
    ):
        await _activate_l2(db_session, auth_user)
        for _ in range(9):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                time_spent_seconds=1,
            )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_3_long_articles" not in resp.json()["completed_actions"]

    async def test_read_10_articles_non_articles_not_counted(
        self, auth_user, db_session
    ):
        await _activate_l2(db_session, auth_user)
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.PODCAST,
            time_spent_seconds=1,
        )
        for _ in range(9):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                time_spent_seconds=1,
            )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_3_long_articles" not in resp.json()["completed_actions"]

    async def test_read_10_articles_empty_interaction_not_counted(
        self, auth_user, db_session
    ):
        await _activate_l2(db_session, auth_user)
        for _ in range(9):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                time_spent_seconds=1,
            )
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.ARTICLE,
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_3_long_articles" not in resp.json()["completed_actions"]

    async def test_saved_articles_detected(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)
        await _add_collection_items(
            db_session,
            auth_user,
            content_types=[
                ContentType.ARTICLE,
                ContentType.ARTICLE,
                ContentType.ARTICLE,
            ],
            is_default=True,
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_first_video_podcast" in resp.json()["completed_actions"]

    async def test_saved_articles_below_threshold_not_detected(
        self, auth_user, db_session
    ):
        await _activate_l2(db_session, auth_user)
        await _add_collection_items(
            db_session,
            auth_user,
            content_types=[ContentType.ARTICLE, ContentType.ARTICLE],
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_first_video_podcast" not in resp.json()["completed_actions"]

    async def test_saved_articles_in_liked_collection_not_counted(
        self, auth_user, db_session
    ):
        await _activate_l2(db_session, auth_user)
        await _add_collection_items(
            db_session,
            auth_user,
            content_types=[
                ContentType.ARTICLE,
                ContentType.ARTICLE,
                ContentType.ARTICLE,
            ],
            is_liked_collection=True,
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_first_video_podcast" not in resp.json()["completed_actions"]

    async def test_saved_non_articles_not_counted(self, auth_user, db_session):
        await _activate_l2(db_session, auth_user)
        await _add_collection_items(
            db_session,
            auth_user,
            content_types=[
                ContentType.ARTICLE,
                ContentType.PODCAST,
                ContentType.YOUTUBE,
            ],
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_2/refresh-status")

        assert "read_first_video_podcast" not in resp.json()["completed_actions"]

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
        assert l2["actions"][0]["label"] == "Lire Actu du jour"
        assert [action["target_route"] for action in l2["actions"]] == [
            "/flux-continu/section/essentiel",
            "/flux-continu/section/bonnes",
            "/flaner",
            "/flaner",
            "/flaner",
        ]
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
        for _ in range(10):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                time_spent_seconds=1,
            )
        await _add_collection_items(
            db_session,
            auth_user,
            content_types=[
                ContentType.ARTICLE,
                ContentType.ARTICLE,
                ContentType.ARTICLE,
            ],
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


# ─── Fixture sans profil ────────────────────────────────────────────────────


@pytest_asyncio.fixture
async def auth_user_no_profile(db_session):
    """User JWT valide mais sans ligne dans user_profiles."""
    user_id = uuid4()

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


class TestProvisioningGap:
    """Régression : user JWT valide sans profil → FK violation sur _init_progress."""

    async def test_new_user_without_profile_gets_200(
        self, auth_user_no_profile, db_session
    ):
        async with _client() as ac:
            resp = await ac.get("/api/letters")

        assert resp.status_code == 200
        assert len(resp.json()) == 5

        from sqlalchemy import select as sa_select

        from app.models.user import UserProfile

        profile = (
            await db_session.execute(
                sa_select(UserProfile).where(
                    UserProfile.user_id == auth_user_no_profile
                )
            )
        ).scalar_one_or_none()
        assert profile is not None

        from app.models.user_letter_progress import UserLetterProgress

        rows = (
            await db_session.execute(
                sa_select(UserLetterProgress).where(
                    UserLetterProgress.user_id == auth_user_no_profile
                )
            )
        ).scalars().all()
        assert len(rows) == 5


# ─── Lettres 3 et 4 (Story 26.2) ────────────────────────────────────────────


from app.models.user_personalization import UserPersonalization  # noqa: E402
from app.models.veille import VeilleConfig  # noqa: E402


async def _activate_letter(db_session, user_id: UUID, active_letter: str) -> None:
    """Pose les 5 rows avec les lettres précédentes archivées et
    `active_letter` active."""
    order = ["letter_0", "letter_1", "letter_2", "letter_3", "letter_4"]
    active_idx = order.index(active_letter)
    now = datetime.now(UTC)
    rows = []
    for idx, letter_id in enumerate(order):
        if idx < active_idx:
            rows.append(
                UserLetterProgress(
                    user_id=user_id,
                    letter_id=letter_id,
                    status="archived",
                    completed_actions=[],
                    archived_at=now,
                )
            )
        elif idx == active_idx:
            rows.append(
                UserLetterProgress(
                    user_id=user_id,
                    letter_id=letter_id,
                    status="active",
                    completed_actions=[],
                    started_at=now,
                )
            )
        else:
            rows.append(
                UserLetterProgress(
                    user_id=user_id,
                    letter_id=letter_id,
                    status="upcoming",
                    completed_actions=[],
                )
            )
    db_session.add_all(rows)
    await db_session.commit()


async def _add_veille_config(
    db_session, user_id: UUID, *, status: str = "active"
) -> None:
    db_session.add(
        VeilleConfig(
            user_id=user_id,
            theme_id="tech",
            theme_label="Tech",
            status=status,
        )
    )
    await db_session.commit()


async def _set_muted_sources(db_session, user_id: UUID, count: int) -> None:
    db_session.add(
        UserPersonalization(
            user_id=user_id,
            muted_sources=[uuid4() for _ in range(count)],
        )
    )
    await db_session.commit()


async def _add_youtube_sources(
    db_session, user_id: UUID, count: int, *, source_type=SourceType.YOUTUBE
) -> None:
    for i in range(count):
        src = Source(
            id=uuid4(),
            name=f"Chaine {uuid4()}",
            url=f"https://yt-{uuid4()}.example.com",
            feed_url=f"https://yt-{uuid4()}.example.com/feed.xml",
            type=source_type,
            theme="society",
            is_active=True,
        )
        db_session.add(src)
        await db_session.flush()
        db_session.add(UserSource(user_id=user_id, source_id=src.id))
    await db_session.commit()


async def _add_articles_bulk(
    db_session, user_id: UUID, count: int, **status_kwargs
) -> None:
    """Bulk : `count` articles distincts avec les kwargs passés au
    UserContentStatus (un seul commit)."""
    src = await _make_source(db_session)
    for _ in range(count):
        content = Content(
            id=uuid4(),
            source_id=src.id,
            title="t",
            url=f"https://x/{uuid4()}",
            published_at=datetime.now(UTC),
            content_type=ContentType.ARTICLE,
            guid=str(uuid4()),
        )
        db_session.add(content)
        await db_session.flush()
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=content.id,
                **status_kwargs,
            )
        )
    await db_session.commit()


class TestBackfill:
    """Users existants (3 rows pré-extension du catalogue) → backfill."""

    async def test_existing_user_three_rows_gets_five_letters(
        self, auth_user, db_session
    ):
        await _ensure_letter_1_started(db_session, auth_user)

        async with _client() as ac:
            resp = await ac.get("/api/letters")

        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 5
        assert data[1]["status"] == "active"  # L1 reste active
        assert data[3]["id"] == "letter_3"
        assert data[3]["status"] == "upcoming"
        assert data[4]["id"] == "letter_4"
        assert data[4]["status"] == "upcoming"

    async def test_finished_user_reactivates_letter_3(self, auth_user, db_session):
        """User qui avait archivé L0-L2 avant l'extension : L3 auto-activée."""
        now = datetime.now(UTC)
        db_session.add_all(
            [
                UserLetterProgress(
                    user_id=auth_user,
                    letter_id=letter_id,
                    status="archived",
                    completed_actions=[],
                    archived_at=now,
                )
                for letter_id in ("letter_0", "letter_1", "letter_2")
            ]
        )
        await db_session.commit()

        async with _client() as ac:
            resp = await ac.get("/api/letters")

        data = resp.json()
        assert [letter["status"] for letter in data[:3]] == ["archived"] * 3
        assert data[3]["status"] == "active"
        assert data[3]["started_at"] is not None
        assert data[4]["status"] == "upcoming"

    async def test_backfill_is_idempotent(self, auth_user, db_session):
        await _ensure_letter_1_started(db_session, auth_user)

        async with _client() as ac:
            r1 = await ac.get("/api/letters")
            r2 = await ac.get("/api/letters")

        assert r1.json() == r2.json()
        from sqlalchemy import select as sa_select

        rows = (
            (
                await db_session.execute(
                    sa_select(UserLetterProgress).where(
                        UserLetterProgress.user_id == auth_user
                    )
                )
            )
            .scalars()
            .all()
        )
        assert len(rows) == 5

    async def test_refresh_letter_3_on_three_row_user(self, auth_user, db_session):
        """refresh-status direct sur letter_3 pour un user 3-rows : pas de
        KeyError, la row est backfillée."""
        await _ensure_letter_1_started(db_session, auth_user)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert resp.status_code == 200
        assert resp.json()["id"] == "letter_3"
        assert resp.json()["status"] == "upcoming"


class TestLetter3Detection:
    async def test_create_first_veille_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        await _add_veille_config(db_session, auth_user)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "create_first_veille" in resp.json()["completed_actions"]

    async def test_archived_veille_still_counts(self, auth_user, db_session):
        """Pauser ou archiver sa veille ne dé-complète pas l'action."""
        await _activate_letter(db_session, auth_user, "letter_3")
        await _add_veille_config(db_session, auth_user, status="archived")

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "create_first_veille" in resp.json()["completed_actions"]

    async def test_save_5_articles_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        for _ in range(5):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                is_saved=True,
            )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "save_5_articles" in resp.json()["completed_actions"]

    async def test_save_below_threshold_not_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        for _ in range(4):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                is_saved=True,
            )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "save_5_articles" not in resp.json()["completed_actions"]

    async def test_note_on_saved_article_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.ARTICLE,
            is_saved=True,
            note_text="Une idée à creuser.",
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "write_first_note" in resp.json()["completed_actions"]

    async def test_blank_note_not_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.ARTICLE,
            is_saved=True,
            note_text="   ",
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "write_first_note" not in resp.json()["completed_actions"]

    async def test_note_on_unsaved_article_not_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.ARTICLE,
            is_saved=False,
            note_text="Note hors sauvegarde.",
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "write_first_note" not in resp.json()["completed_actions"]

    async def test_mute_3_sources_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        await _set_muted_sources(db_session, auth_user, 3)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "mute_3_sources" in resp.json()["completed_actions"]

    async def test_mute_below_threshold_not_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        await _set_muted_sources(db_session, auth_user, 2)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "mute_3_sources" not in resp.json()["completed_actions"]

    async def test_add_5_youtube_channels_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        await _add_youtube_sources(db_session, auth_user, 5)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "add_5_youtube_channels" in resp.json()["completed_actions"]

    async def test_non_youtube_sources_not_counted(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        await _add_youtube_sources(
            db_session, auth_user, 5, source_type=SourceType.ARTICLE
        )

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert "add_5_youtube_channels" not in resp.json()["completed_actions"]


class TestLetter4Detection:
    async def test_read_50_articles_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_4")
        await _add_articles_bulk(db_session, auth_user, 50, time_spent_seconds=1)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_4/refresh-status")

        assert "read_50_articles" in resp.json()["completed_actions"]

    async def test_read_below_threshold_not_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_4")
        await _add_articles_bulk(db_session, auth_user, 49, time_spent_seconds=1)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_4/refresh-status")

        assert "read_50_articles" not in resp.json()["completed_actions"]

    async def test_recommend_10_articles_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_4")
        await _add_articles_bulk(db_session, auth_user, 10, is_liked=True)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_4/refresh-status")

        assert "recommend_10_articles" in resp.json()["completed_actions"]

    async def test_recommend_below_threshold_not_detected(
        self, auth_user, db_session
    ):
        await _activate_letter(db_session, auth_user, "letter_4")
        await _add_articles_bulk(db_session, auth_user, 9, is_liked=True)

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_4/refresh-status")

        assert "recommend_10_articles" not in resp.json()["completed_actions"]

    async def test_open_10_perspectives_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_4")
        for _ in range(10):
            await _add_event(db_session, auth_user, "perspectives_opened")

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_4/refresh-status")

        assert "open_10_perspectives" in resp.json()["completed_actions"]

    async def test_perspectives_below_threshold_not_detected(
        self, auth_user, db_session
    ):
        await _activate_letter(db_session, auth_user, "letter_4")
        for _ in range(9):
            await _add_event(db_session, auth_user, "perspectives_opened")

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_4/refresh-status")

        assert "open_10_perspectives" not in resp.json()["completed_actions"]

    async def test_give_app_feedback_detected(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_4")
        await _add_event(db_session, auth_user, "app_feedback_opened")

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_4/refresh-status")

        assert "give_app_feedback" in resp.json()["completed_actions"]


class TestNewLettersShape:
    async def test_letter_3_and_4_expose_palier_fields(self, auth_user):
        async with _client() as ac:
            resp = await ac.get("/api/letters")

        data = resp.json()
        for letter in (data[3], data[4]):
            assert letter["intro_palier"]
            assert letter["completion_voeu"]
            for action in letter["actions"]:
                assert action["completion_palier"]
                assert action["target_route"]


class TestNewLettersChaining:
    async def test_letter_3_complete_unlocks_letter_4(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_3")
        await _add_veille_config(db_session, auth_user)
        await _set_muted_sources(db_session, auth_user, 3)
        await _add_youtube_sources(db_session, auth_user, 5)
        for _ in range(4):
            await _add_user_content_status(
                db_session,
                auth_user,
                content_type=ContentType.ARTICLE,
                is_saved=True,
            )
        await _add_user_content_status(
            db_session,
            auth_user,
            content_type=ContentType.ARTICLE,
            is_saved=True,
            note_text="Cinquième article, avec note.",
        )

        async with _client() as ac:
            refresh = await ac.post("/api/letters/letter_3/refresh-status")
            letters = await ac.get("/api/letters")

        assert refresh.json()["status"] == "archived"
        assert refresh.json()["progress"] == 1.0
        data = letters.json()
        assert data[4]["status"] == "active"
        assert data[4]["started_at"] is not None

    async def test_letter_4_complete_is_terminal(self, auth_user, db_session):
        await _activate_letter(db_session, auth_user, "letter_4")
        await _add_articles_bulk(db_session, auth_user, 50, time_spent_seconds=1)
        await _add_articles_bulk(db_session, auth_user, 10, is_liked=True)
        for _ in range(10):
            await _add_event(db_session, auth_user, "perspectives_opened")
        await _add_event(db_session, auth_user, "app_feedback_opened")

        async with _client() as ac:
            refresh = await ac.post("/api/letters/letter_4/refresh-status")
            letters = await ac.get("/api/letters")

        assert refresh.status_code == 200
        assert refresh.json()["status"] == "archived"
        assert len(refresh.json()["completed_actions"]) == 4
        assert letters.status_code == 200
        assert all(
            letter["status"] == "archived" for letter in letters.json()
        )


class TestNewLettersCrossTenant:
    async def test_other_user_data_not_counted(self, auth_user, db_session):
        other_id = uuid4()
        db_session.add(
            UserProfile(
                user_id=other_id,
                display_name="Other",
                onboarding_completed=True,
            )
        )
        await db_session.commit()
        await _add_veille_config(db_session, other_id)
        await _set_muted_sources(db_session, other_id, 3)
        await _activate_letter(db_session, auth_user, "letter_3")

        async with _client() as ac:
            resp = await ac.post("/api/letters/letter_3/refresh-status")

        assert resp.json()["completed_actions"] == []
