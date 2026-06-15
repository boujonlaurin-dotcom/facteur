"""Tests modèle UserFavoriteInterest — 3-way XOR + cascade veille (Story 23.1 PR-3).

Couvre la contrainte CHECK et la FK ON DELETE CASCADE introduites par la
migration `vf02_favorite_veille_target`.
"""

from uuid import uuid4

import pytest
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError

from app.models.user import UserProfile
from app.models.user_favorites import UserFavoriteInterest
from app.models.veille import VeilleConfig, VeilleStatus


async def _make_user(db_session) -> UserProfile:
    user = UserProfile(user_id=uuid4(), onboarding_completed=True)
    db_session.add(user)
    await db_session.commit()
    return user


async def _make_veille(db_session, user_id) -> VeilleConfig:
    cfg = VeilleConfig(
        id=uuid4(),
        user_id=user_id,
        theme_id="tech",
        theme_label="Tech",
        status=VeilleStatus.ACTIVE.value,
    )
    db_session.add(cfg)
    await db_session.commit()
    return cfg


@pytest.mark.asyncio
async def test_3way_xor_accepts_veille_only(db_session):
    user = await _make_user(db_session)
    cfg = await _make_veille(db_session, user.user_id)
    db_session.add(
        UserFavoriteInterest(
            user_id=user.user_id, position=0, veille_config_id=cfg.id
        )
    )
    await db_session.commit()

    row = (
        await db_session.execute(
            select(UserFavoriteInterest).where(
                UserFavoriteInterest.user_id == user.user_id
            )
        )
    ).scalar_one()
    assert row.veille_config_id == cfg.id
    assert row.interest_slug is None
    assert row.custom_topic_id is None


@pytest.mark.asyncio
async def test_3way_xor_rejects_double_target(db_session):
    user = await _make_user(db_session)
    cfg = await _make_veille(db_session, user.user_id)
    db_session.add(
        UserFavoriteInterest(
            user_id=user.user_id,
            position=0,
            interest_slug="tech",
            veille_config_id=cfg.id,
        )
    )
    with pytest.raises(IntegrityError):
        await db_session.commit()
    await db_session.rollback()


@pytest.mark.asyncio
async def test_3way_xor_rejects_no_target(db_session):
    user = await _make_user(db_session)
    db_session.add(UserFavoriteInterest(user_id=user.user_id, position=0))
    with pytest.raises(IntegrityError):
        await db_session.commit()
    await db_session.rollback()


@pytest.mark.asyncio
async def test_favorite_cascade_delete_on_veille_hard_delete(db_session):
    user = await _make_user(db_session)
    cfg = await _make_veille(db_session, user.user_id)
    db_session.add(
        UserFavoriteInterest(
            user_id=user.user_id, position=0, veille_config_id=cfg.id
        )
    )
    await db_session.commit()

    await db_session.execute(delete(VeilleConfig).where(VeilleConfig.id == cfg.id))
    await db_session.commit()

    remaining = (
        await db_session.execute(
            select(UserFavoriteInterest).where(
                UserFavoriteInterest.user_id == user.user_id
            )
        )
    ).all()
    assert remaining == []
