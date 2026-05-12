"""Verrouille la migration vp01 : les 4 colonnes V1 sur veille_configs et le
toggle notif_veille_enabled sur user_notification_preferences existent et
acceptent la persistance des valeurs cibles.
"""

from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.user import UserProfile
from app.models.user_notification_preferences import UserNotificationPreferences
from app.models.veille import VeilleConfig, VeilleStatus


@pytest.mark.asyncio
async def test_veille_config_persists_v1_personalization_fields(db_session):
    user = UserProfile(
        user_id=uuid4(),
        display_name="vp01 user",
        onboarding_completed=True,
    )
    db_session.add(user)
    await db_session.commit()

    cfg = VeilleConfig(
        id=uuid4(),
        user_id=user.user_id,
        theme_id="tech",
        theme_label="Technologie",
        frequency="weekly",
        day_of_week=0,
        delivery_hour=7,
        timezone="Europe/Paris",
        status=VeilleStatus.ACTIVE.value,
        purpose="progresser_au_travail",
        purpose_other=None,
        editorial_brief="Plutôt analyses concrètes que hype.",
        preset_id="ia_agentique",
    )
    db_session.add(cfg)
    await db_session.commit()
    await db_session.refresh(cfg)

    assert cfg.purpose == "progresser_au_travail"
    assert cfg.purpose_other is None
    assert cfg.editorial_brief == "Plutôt analyses concrètes que hype."
    assert cfg.preset_id == "ia_agentique"


@pytest.mark.asyncio
async def test_notif_veille_enabled_default_false_and_writable(db_session):
    user = UserProfile(
        user_id=uuid4(),
        display_name="notif vp01 user",
        onboarding_completed=True,
    )
    db_session.add(user)
    await db_session.commit()

    prefs = UserNotificationPreferences(user_id=user.user_id)
    db_session.add(prefs)
    await db_session.commit()
    await db_session.refresh(prefs)
    assert prefs.notif_veille_enabled is False

    prefs.notif_veille_enabled = True
    await db_session.commit()

    fetched = (
        (
            await db_session.execute(
                select(UserNotificationPreferences).where(
                    UserNotificationPreferences.user_id == user.user_id
                )
            )
        )
        .scalars()
        .first()
    )
    assert fetched is not None
    assert fetched.notif_veille_enabled is True
