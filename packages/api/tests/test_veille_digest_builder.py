"""Tests pour `VeilleDigestBuilder` (Story 18.2 / Phase 3 / Stream A).

Couvre :
- chargement contexte (config + topics + sources)
- fetch contents avec filtre source_id × published_at × ARRAY OVERLAP topics
- filtrage clusters pertinents + top-N
- LLM mocké (réponse OK / réponse None / pas ready)
- format items
- anti-régression : ZÉRO session DB tenue pendant l'appel LLM
"""

from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
import pytest_asyncio

from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.models.user import UserProfile
from app.models.veille import (
    VeilleConfig,
    VeilleFrequency,
    VeilleSource,
    VeilleSourceKind,
    VeilleStatus,
    VeilleTopic,
    VeilleTopicKind,
)
from app.services.veille.digest_builder import VeilleDigestBuilder


@pytest_asyncio.fixture
async def test_user(db_session):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Builder User",
            onboarding_completed=True,
        )
    )
    await db_session.commit()
    return user_id


@pytest_asyncio.fixture
async def test_sources(db_session):
    sources = [
        Source(
            id=uuid4(),
            name=f"Source {i}",
            url=f"https://s{i}.example.com",
            feed_url=f"https://s{i}.example.com/feed-{uuid4()}.xml",
            type=SourceType.ARTICLE,
            theme="education",
            is_active=True,
            is_curated=True,
        )
        for i in range(3)
    ]
    for s in sources:
        db_session.add(s)
    await db_session.commit()
    return sources


@pytest_asyncio.fixture
async def veille_config(db_session, test_user, test_sources):
    """Config avec 2 topics et les 3 sources."""
    cfg = VeilleConfig(
        id=uuid4(),
        user_id=test_user,
        theme_id="education",
        theme_label="Éducation",
        frequency=VeilleFrequency.WEEKLY,
        day_of_week=0,
        delivery_hour=7,
        timezone="Europe/Paris",
        status=VeilleStatus.ACTIVE,
    )
    db_session.add(cfg)
    await db_session.flush()

    db_session.add_all(
        [
            VeilleTopic(
                veille_config_id=cfg.id,
                topic_id="t-eval",
                label="Évaluation",
                kind=VeilleTopicKind.PRESET,
            ),
            VeilleTopic(
                veille_config_id=cfg.id,
                topic_id="sub-dys",
                label="Dys",
                kind=VeilleTopicKind.PRESET,
            ),
        ]
    )
    db_session.add_all(
        [
            VeilleSource(
                veille_config_id=cfg.id,
                source_id=s.id,
                kind=VeilleSourceKind.FOLLOWED,
            )
            for s in test_sources
        ]
    )
    await db_session.commit()
    await db_session.refresh(cfg)
    return cfg


def _make_content(
    *,
    source_id,
    title: str,
    topics: list[str],
    published_at: datetime | None = None,
    description: str = "Lorem ipsum",
):
    return Content(
        id=uuid4(),
        source_id=source_id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        description=description,
        published_at=published_at or datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid=f"guid-{uuid4()}",
        topics=topics,
    )


@pytest_asyncio.fixture
async def matching_contents(db_session, test_sources):
    """Articles répartis sur 3 sources, plusieurs avec titre proche (cluster)."""
    base = datetime.now(UTC) - timedelta(hours=2)
    items = [
        _make_content(
            source_id=test_sources[0].id,
            title="Réforme évaluation collège annoncée",
            topics=["t-eval"],
            published_at=base + timedelta(minutes=10),
        ),
        _make_content(
            source_id=test_sources[1].id,
            title="Réforme évaluation collège : détails",
            topics=["t-eval"],
            published_at=base + timedelta(minutes=20),
        ),
        _make_content(
            source_id=test_sources[2].id,
            title="Évaluation au collège, ce qui change",
            topics=["t-eval"],
            published_at=base + timedelta(minutes=30),
        ),
        _make_content(
            source_id=test_sources[0].id,
            title="Dyslexie : étude longitudinale relayée",
            topics=["sub-dys"],
            published_at=base + timedelta(minutes=40),
        ),
        _make_content(
            source_id=test_sources[1].id,
            title="Hors topic — sport scolaire revisited",
            topics=["t-sport"],
            published_at=base + timedelta(minutes=50),
        ),
    ]
    for c in items:
        db_session.add(c)
    await db_session.commit()
    return items


def _make_llm_mock(*, ready: bool = True, response=None):
    llm = MagicMock()
    llm.is_ready = ready
    llm.chat_json = AsyncMock(return_value=response)
    return llm


# ─── Tests ───────────────────────────────────────────────────────────────────


class TestLoadInput:
    async def test_loads_topics_and_sources(
        self, db_session, veille_config, fake_session_maker
    ):
        builder = VeilleDigestBuilder(
            llm=_make_llm_mock(ready=False), session_maker=fake_session_maker
        )
        async with fake_session_maker() as s:
            ctx = await builder._load_input(s, veille_config.id)

        assert ctx.config_id == veille_config.id
        assert set(ctx.user_topic_ids) == {"t-eval", "sub-dys"}
        assert len(ctx.user_source_ids) == 3
        assert ctx.theme_label == "Éducation"

    async def test_raises_when_config_missing(self, db_session, fake_session_maker):
        builder = VeilleDigestBuilder(
            llm=_make_llm_mock(ready=False), session_maker=fake_session_maker
        )
        async with fake_session_maker() as s:
            with pytest.raises(ValueError, match="introuvable"):
                await builder._load_input(s, uuid4())


class TestBuild:
    async def test_returns_empty_when_no_sources(
        self, db_session, test_user, fake_session_maker
    ):
        cfg = VeilleConfig(
            id=uuid4(),
            user_id=test_user,
            theme_id="education",
            theme_label="Éducation",
            frequency=VeilleFrequency.WEEKLY,
            day_of_week=0,
            delivery_hour=7,
            timezone="Europe/Paris",
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(cfg)
        await db_session.flush()
        db_session.add(
            VeilleTopic(
                veille_config_id=cfg.id,
                topic_id="t-eval",
                label="Eval",
                kind=VeilleTopicKind.PRESET,
            )
        )
        await db_session.commit()

        builder = VeilleDigestBuilder(
            llm=_make_llm_mock(ready=False), session_maker=fake_session_maker
        )
        items = await builder.build(cfg.id)
        assert items == []

    async def test_returns_empty_when_no_matching_contents(
        self, db_session, veille_config, fake_session_maker
    ):
        # Aucun article inséré → fetch_contents retourne []
        builder = VeilleDigestBuilder(
            llm=_make_llm_mock(ready=False), session_maker=fake_session_maker
        )
        items = await builder.build(veille_config.id)
        assert items == []

    async def test_filters_by_topic_overlap(
        self,
        db_session,
        veille_config,
        matching_contents,
        fake_session_maker,
    ):
        """L'article tagué `t-sport` ne doit pas remonter."""
        builder = VeilleDigestBuilder(
            llm=_make_llm_mock(ready=False),
            session_maker=fake_session_maker,
            top_n=10,
        )
        items = await builder.build(veille_config.id)

        all_titles = [a["title"] for it in items for a in it["articles"]]
        assert all("sport scolaire" not in t for t in all_titles)
        assert any("Réforme évaluation" in t for t in all_titles)

    async def test_top_n_caps_clusters(
        self,
        db_session,
        veille_config,
        matching_contents,
        fake_session_maker,
    ):
        builder = VeilleDigestBuilder(
            llm=_make_llm_mock(ready=False),
            session_maker=fake_session_maker,
            top_n=1,
        )
        items = await builder.build(veille_config.id)
        assert len(items) == 1

    async def test_item_format(
        self,
        db_session,
        veille_config,
        matching_contents,
        fake_session_maker,
    ):
        builder = VeilleDigestBuilder(
            llm=_make_llm_mock(ready=False),
            session_maker=fake_session_maker,
        )
        items = await builder.build(veille_config.id)
        assert items, "Expected at least one item"
        for it in items:
            assert isinstance(it["cluster_id"], str)
            assert isinstance(it["title"], str) and it["title"]
            assert isinstance(it["why_it_matters"], str)
            assert isinstance(it["articles"], list)
            for a in it["articles"]:
                assert {
                    "content_id",
                    "source_id",
                    "title",
                    "url",
                    "excerpt",
                    "published_at",
                } <= set(a)


class TestWhyItMatters:
    async def test_uses_llm_response_when_ready(
        self,
        db_session,
        veille_config,
        matching_contents,
        fake_session_maker,
    ):
        # Fake LLM renvoyant un mapping arbitraire ; on vérifie que le builder
        # consomme bien le mapping.
        captured: dict[str, str] = {}

        async def _chat_json_side_effect(**kwargs):
            # On fabrique une réponse en lisant les cluster_ids du prompt.
            import json as _json

            payload = _json.loads(kwargs["user_message"])
            mapping = {c["cluster_id"]: "LLM-WHY" for c in payload["clusters"]}
            captured.update(mapping)
            return {"clusters": mapping}

        llm = MagicMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(side_effect=_chat_json_side_effect)

        builder = VeilleDigestBuilder(llm=llm, session_maker=fake_session_maker)
        items = await builder.build(veille_config.id)
        assert items
        assert all(it["why_it_matters"] == "LLM-WHY" for it in items)
        llm.chat_json.assert_awaited_once()

    async def test_fallback_when_llm_not_ready(
        self,
        db_session,
        veille_config,
        matching_contents,
        fake_session_maker,
    ):
        builder = VeilleDigestBuilder(
            llm=_make_llm_mock(ready=False),
            session_maker=fake_session_maker,
        )
        items = await builder.build(veille_config.id)
        assert items
        for it in items:
            assert it["why_it_matters"]
            assert (
                "article" in it["why_it_matters"].lower()
                or "sources" in it["why_it_matters"].lower()
            )

    async def test_fallback_when_llm_returns_none(
        self,
        db_session,
        veille_config,
        matching_contents,
        fake_session_maker,
    ):
        llm = _make_llm_mock(ready=True, response=None)
        builder = VeilleDigestBuilder(llm=llm, session_maker=fake_session_maker)
        items = await builder.build(veille_config.id)
        assert items
        for it in items:
            assert it["why_it_matters"]


class TestPoolDbSafety:
    """Anti-régression : ZÉRO session DB tenue pendant le LLM call."""

    async def test_no_session_open_during_llm_call(
        self,
        db_session,
        veille_config,
        matching_contents,
    ):
        active_count = {"value": 0, "max": 0}
        active_during_llm: list[int] = []

        @asynccontextmanager
        async def _tracking_maker():
            active_count["value"] += 1
            active_count["max"] = max(active_count["max"], active_count["value"])
            try:
                yield db_session
            finally:
                active_count["value"] -= 1

        async def _chat_json_capture(**kwargs):
            active_during_llm.append(active_count["value"])
            import json as _json

            payload = _json.loads(kwargs["user_message"])
            return {"clusters": {c["cluster_id"]: "ok" for c in payload["clusters"]}}

        llm = MagicMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(side_effect=_chat_json_capture)

        builder = VeilleDigestBuilder(llm=llm, session_maker=_tracking_maker)
        items = await builder.build(veille_config.id)

        assert items
        assert active_during_llm, "LLM was not invoked"
        assert active_during_llm == [0], (
            f"DB session was held during LLM call: {active_during_llm}"
        )
        # Sessions sont ouvertes séquentiellement (jamais 2 en même temps).
        assert active_count["max"] == 1
        # Toutes les sessions ont été fermées proprement.
        assert active_count["value"] == 0
