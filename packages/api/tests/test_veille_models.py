"""Tests pour les modèles SQLAlchemy de « Ma veille » (Story 23.1).

Couvre :
- CRUD basique sur les 4 tables (config / topics / sources / keywords).
- Partial UNIQUE constraint `uq_veille_configs_user_active` (1 active par user).
- Cascade ondelete CASCADE depuis veille_configs vers topics/sources/keywords.
"""

from uuid import uuid4

import pytest
import pytest_asyncio
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.models.enums import SourceType
from app.models.source import Source
from app.models.user import UserProfile
from app.models.veille import (
    VeilleConfig,
    VeilleKeyword,
    VeilleSource,
    VeilleSourceKind,
    VeilleStatus,
    VeilleTopic,
    VeilleTopicKind,
)


@pytest_asyncio.fixture
async def test_user(db_session):
    user_id = uuid4()
    profile = UserProfile(
        user_id=user_id,
        display_name="Veille Test User",
        onboarding_completed=True,
    )
    db_session.add(profile)
    await db_session.commit()
    return profile


@pytest_asyncio.fixture
async def test_source(db_session):
    source = Source(
        id=uuid4(),
        name="Edu Daily",
        url="https://edu.example.com",
        feed_url=f"https://edu.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="education",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.commit()
    return source


class TestVeilleConfigCRUD:
    @pytest.mark.asyncio
    async def test_create_minimal_config(self, db_session, test_user):
        cfg = VeilleConfig(
            user_id=test_user.user_id,
            theme_id="education",
            theme_label="Éducation",
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(cfg)
        await db_session.commit()
        await db_session.refresh(cfg)

        assert cfg.id is not None
        assert cfg.user_id == test_user.user_id
        assert cfg.theme_id == "education"
        assert cfg.status == VeilleStatus.ACTIVE
        assert cfg.created_at is not None

    @pytest.mark.asyncio
    async def test_partial_unique_one_active_per_user(self, db_session, test_user):
        """Le partial UNIQUE empêche 2 configs ACTIVE pour le même user,
        mais autorise 1 active + N archived."""
        user_id = test_user.user_id
        active = VeilleConfig(
            user_id=user_id,
            theme_id="education",
            theme_label="Éducation",
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(active)
        await db_session.commit()

        dupe = VeilleConfig(
            user_id=user_id,
            theme_id="health",
            theme_label="Santé",
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(dupe)
        with pytest.raises(IntegrityError):
            await db_session.commit()
        await db_session.rollback()

        archived = VeilleConfig(
            user_id=user_id,
            theme_id="health",
            theme_label="Santé",
            status=VeilleStatus.ARCHIVED,
        )
        db_session.add(archived)
        await db_session.commit()
        await db_session.refresh(archived)
        assert archived.status == VeilleStatus.ARCHIVED


class TestVeilleTopicAndSource:
    @pytest_asyncio.fixture
    async def cfg(self, db_session, test_user):
        c = VeilleConfig(
            user_id=test_user.user_id,
            theme_id="education",
            theme_label="Éducation",
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(c)
        await db_session.commit()
        await db_session.refresh(c)
        return c

    @pytest.mark.asyncio
    async def test_attach_topics(self, db_session, cfg):
        topics = [
            VeilleTopic(
                veille_config_id=cfg.id,
                topic_id="t-eval",
                label="Évaluations",
                kind=VeilleTopicKind.PRESET,
                position=0,
            ),
            VeilleTopic(
                veille_config_id=cfg.id,
                topic_id="sub-dys",
                label="Dys (TDA/H, dyslexie)",
                kind=VeilleTopicKind.SUGGESTED,
                reason="Pertinent vu tes lectures",
                position=1,
            ),
        ]
        db_session.add_all(topics)
        await db_session.commit()

        result = await db_session.execute(
            select(VeilleTopic).where(VeilleTopic.veille_config_id == cfg.id)
        )
        rows = list(result.scalars().all())
        assert len(rows) == 2
        assert {r.topic_id for r in rows} == {"t-eval", "sub-dys"}

    @pytest.mark.asyncio
    async def test_topic_unique_per_config(self, db_session, cfg):
        db_session.add(
            VeilleTopic(
                veille_config_id=cfg.id,
                topic_id="t-eval",
                label="Évaluations",
                kind=VeilleTopicKind.PRESET,
            )
        )
        await db_session.commit()

        db_session.add(
            VeilleTopic(
                veille_config_id=cfg.id,
                topic_id="t-eval",
                label="Évaluations bis",
                kind=VeilleTopicKind.PRESET,
            )
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()
        await db_session.rollback()

    @pytest.mark.asyncio
    async def test_attach_source(self, db_session, cfg, test_source):
        link = VeilleSource(
            veille_config_id=cfg.id,
            source_id=test_source.id,
            kind=VeilleSourceKind.FOLLOWED,
            position=0,
        )
        db_session.add(link)
        await db_session.commit()
        await db_session.refresh(link)
        assert link.kind == VeilleSourceKind.FOLLOWED


class TestVeilleKeyword:
    @pytest_asyncio.fixture
    async def cfg(self, db_session, test_user):
        c = VeilleConfig(
            user_id=test_user.user_id,
            theme_id="tech",
            theme_label="Tech",
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(c)
        await db_session.commit()
        await db_session.refresh(c)
        return c

    @pytest.mark.asyncio
    async def test_create_keyword(self, db_session, cfg):
        db_session.add(
            VeilleKeyword(
                veille_config_id=cfg.id,
                keyword="ia générative",
                position=0,
            )
        )
        await db_session.commit()

        rows = (
            (
                await db_session.execute(
                    select(VeilleKeyword).where(
                        VeilleKeyword.veille_config_id == cfg.id
                    )
                )
            )
            .scalars()
            .all()
        )
        assert len(rows) == 1
        assert rows[0].keyword == "ia générative"

    @pytest.mark.asyncio
    async def test_keyword_unique_per_topic(self, db_session, cfg):
        """Unique = (config, topic_id, keyword) — collision sous un même angle."""
        topic = VeilleTopic(
            veille_config_id=cfg.id,
            topic_id="climat",
            label="Climat",
            kind=VeilleTopicKind.PRESET,
            position=0,
        )
        db_session.add(topic)
        await db_session.commit()
        await db_session.refresh(topic)

        db_session.add(
            VeilleKeyword(
                veille_config_id=cfg.id,
                veille_topic_id=topic.id,
                keyword="climat",
                position=0,
            )
        )
        await db_session.commit()

        db_session.add(
            VeilleKeyword(
                veille_config_id=cfg.id,
                veille_topic_id=topic.id,
                keyword="climat",
                position=1,
            )
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()
        await db_session.rollback()

    @pytest.mark.asyncio
    async def test_same_keyword_allowed_under_two_angles(self, db_session, cfg):
        """La même clé peut vivre sous deux angles distincts (triplet unique)."""
        t1 = VeilleTopic(
            veille_config_id=cfg.id,
            topic_id="climat",
            label="Climat",
            kind=VeilleTopicKind.PRESET,
            position=0,
        )
        t2 = VeilleTopic(
            veille_config_id=cfg.id,
            topic_id="energie",
            label="Énergie",
            kind=VeilleTopicKind.PRESET,
            position=1,
        )
        db_session.add_all([t1, t2])
        await db_session.commit()
        await db_session.refresh(t1)
        await db_session.refresh(t2)

        db_session.add_all(
            [
                VeilleKeyword(
                    veille_config_id=cfg.id, veille_topic_id=t1.id, keyword="co2"
                ),
                VeilleKeyword(
                    veille_config_id=cfg.id, veille_topic_id=t2.id, keyword="co2"
                ),
                # + un mot-clé global (veille_topic_id NULL) identique : autorisé.
                VeilleKeyword(veille_config_id=cfg.id, keyword="co2"),
            ]
        )
        await db_session.commit()

        rows = (
            (
                await db_session.execute(
                    select(VeilleKeyword).where(
                        VeilleKeyword.veille_config_id == cfg.id,
                        VeilleKeyword.keyword == "co2",
                    )
                )
            )
            .scalars()
            .all()
        )
        assert len(rows) == 3


class TestCascade:
    @pytest.mark.asyncio
    async def test_delete_config_cascades_children(
        self, db_session, test_user, test_source
    ):
        cfg = VeilleConfig(
            user_id=test_user.user_id,
            theme_id="education",
            theme_label="Éducation",
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(cfg)
        await db_session.commit()
        await db_session.refresh(cfg)

        cfg_id = cfg.id

        db_session.add_all(
            [
                VeilleTopic(
                    veille_config_id=cfg_id,
                    topic_id="t-eval",
                    label="Évaluations",
                    kind=VeilleTopicKind.PRESET,
                ),
                VeilleSource(
                    veille_config_id=cfg_id,
                    source_id=test_source.id,
                    kind=VeilleSourceKind.FOLLOWED,
                ),
                VeilleKeyword(
                    veille_config_id=cfg_id,
                    keyword="évaluations",
                ),
            ]
        )
        await db_session.commit()

        await db_session.delete(cfg)
        await db_session.commit()

        topics = await db_session.execute(
            select(VeilleTopic).where(VeilleTopic.veille_config_id == cfg_id)
        )
        sources = await db_session.execute(
            select(VeilleSource).where(VeilleSource.veille_config_id == cfg_id)
        )
        keywords = await db_session.execute(
            select(VeilleKeyword).where(VeilleKeyword.veille_config_id == cfg_id)
        )
        assert list(topics.scalars().all()) == []
        assert list(sources.scalars().all()) == []
        assert list(keywords.scalars().all()) == []
