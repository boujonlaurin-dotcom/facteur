"""Tests pour les modèles SQLAlchemy de « Ma veille » (Story 18.1).

Couvre :
- CRUD basique sur les 4 tables (config / topics / sources / deliveries).
- Partial UNIQUE constraint `uq_veille_configs_user_active` (1 active par user).
- Cascade ondelete CASCADE depuis veille_configs vers topics/sources/deliveries.
"""

from datetime import UTC, date, datetime, timedelta
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
    VeilleDelivery,
    VeilleFrequency,
    VeilleGenerationState,
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
            frequency=VeilleFrequency.WEEKLY,
            day_of_week=0,
            delivery_hour=7,
            timezone="Europe/Paris",
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(cfg)
        await db_session.commit()
        await db_session.refresh(cfg)

        assert cfg.id is not None
        assert cfg.user_id == test_user.user_id
        assert cfg.theme_id == "education"
        assert cfg.frequency == VeilleFrequency.WEEKLY
        assert cfg.status == VeilleStatus.ACTIVE
        assert cfg.last_delivered_at is None
        assert cfg.next_scheduled_at is None
        assert cfg.created_at is not None

    @pytest.mark.asyncio
    async def test_partial_unique_one_active_per_user(
        self, db_session, test_user
    ):
        """Le partial UNIQUE empêche 2 configs ACTIVE pour le même user,
        mais autorise 1 active + N archived."""
        user_id = test_user.user_id
        active = VeilleConfig(
            user_id=user_id,
            theme_id="education",
            theme_label="Éducation",
            frequency=VeilleFrequency.WEEKLY,
            delivery_hour=7,
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(active)
        await db_session.commit()

        # Une 2e ACTIVE doit casser la contrainte partial UNIQUE.
        dupe = VeilleConfig(
            user_id=user_id,
            theme_id="health",
            theme_label="Santé",
            frequency=VeilleFrequency.MONTHLY,
            delivery_hour=8,
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(dupe)
        with pytest.raises(IntegrityError):
            await db_session.commit()
        await db_session.rollback()

        # Une ARCHIVED en plus de l'ACTIVE doit passer.
        archived = VeilleConfig(
            user_id=user_id,
            theme_id="health",
            theme_label="Santé",
            frequency=VeilleFrequency.MONTHLY,
            delivery_hour=8,
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
            frequency=VeilleFrequency.WEEKLY,
            delivery_hour=7,
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


class TestVeilleDelivery:
    @pytest_asyncio.fixture
    async def cfg(self, db_session, test_user):
        c = VeilleConfig(
            user_id=test_user.user_id,
            theme_id="education",
            theme_label="Éducation",
            frequency=VeilleFrequency.WEEKLY,
            delivery_hour=7,
            status=VeilleStatus.ACTIVE,
        )
        db_session.add(c)
        await db_session.commit()
        await db_session.refresh(c)
        return c

    @pytest.mark.asyncio
    async def test_create_delivery_default_state(self, db_session, cfg):
        delivery = VeilleDelivery(
            veille_config_id=cfg.id,
            target_date=date.today(),
        )
        db_session.add(delivery)
        await db_session.commit()
        await db_session.refresh(delivery)

        assert delivery.generation_state == VeilleGenerationState.PENDING
        assert delivery.items == []
        assert delivery.attempts == 0
        assert delivery.version == 1

    @pytest.mark.asyncio
    async def test_unique_per_config_date(self, db_session, cfg):
        target = date.today()
        db_session.add(
            VeilleDelivery(veille_config_id=cfg.id, target_date=target)
        )
        await db_session.commit()

        db_session.add(
            VeilleDelivery(veille_config_id=cfg.id, target_date=target)
        )
        with pytest.raises(IntegrityError):
            await db_session.commit()
        await db_session.rollback()

    @pytest.mark.asyncio
    async def test_state_transitions(self, db_session, cfg):
        delivery = VeilleDelivery(
            veille_config_id=cfg.id,
            target_date=date.today(),
        )
        db_session.add(delivery)
        await db_session.commit()

        delivery.generation_state = VeilleGenerationState.RUNNING
        delivery.started_at = datetime.now(UTC)
        await db_session.commit()
        await db_session.refresh(delivery)
        assert delivery.generation_state == VeilleGenerationState.RUNNING

        delivery.generation_state = VeilleGenerationState.SUCCEEDED
        delivery.finished_at = datetime.now(UTC)
        await db_session.commit()
        await db_session.refresh(delivery)
        assert delivery.generation_state == VeilleGenerationState.SUCCEEDED


class TestCascade:
    @pytest.mark.asyncio
    async def test_delete_config_cascades_children(
        self, db_session, test_user, test_source
    ):
        cfg = VeilleConfig(
            user_id=test_user.user_id,
            theme_id="education",
            theme_label="Éducation",
            frequency=VeilleFrequency.WEEKLY,
            delivery_hour=7,
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
                VeilleDelivery(
                    veille_config_id=cfg_id,
                    target_date=date.today() - timedelta(days=1),
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
        deliveries = await db_session.execute(
            select(VeilleDelivery).where(
                VeilleDelivery.veille_config_id == cfg_id
            )
        )
        assert list(topics.scalars().all()) == []
        assert list(sources.scalars().all()) == []
        assert list(deliveries.scalars().all()) == []
