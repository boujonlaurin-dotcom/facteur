from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from app.models.user import UserPreference
from app.schemas.user import OnboardingAnswers
from app.services.user_service import UserService


@pytest.mark.asyncio
async def test_save_onboarding_persists_subtopics():
    # Mock DB Session
    mock_db = AsyncMock()
    # Mock get_or_create_profile to return a mock profile
    mock_profile = MagicMock()

    service = UserService(mock_db)

    # Mock internal calls
    # db.add is synchronous in SQLAlchemy sessions generally, but if we use AsyncSession it might behave differently in tests.
    # The warning said 'coroutine was never awaited'. This means our mock IS async but we called it without await.
    # UserSubtopic creation calls self.db.add().
    # If mock_db is an AsyncMock, then mock_db.add matches as AsyncMock which expects await.
    # We should configure add to be a MagicMock (synchronous).
    mock_db.add = MagicMock()

    service.get_or_create_profile = AsyncMock(return_value=mock_profile)

    user_id = str(uuid4())
    answers = OnboardingAnswers(
        objective="learn",
        age_range="25-34",
        approach="direct",
        perspective="big_picture",
        response_style="decisive",
        content_recency="recent",
        themes=["tech"],
        subtopics=["ai", "crypto"] # 2 subtopics
    )

    # Execute
    result = await service.save_onboarding(user_id, answers)

    # Verify subtopics created count in response
    assert result["subtopics_created"] == 2

    # C-1 : l'onboarding passe désormais par un upsert Postgres
    # (pg_insert ... on_conflict_do_nothing) au lieu d'un db.add brut, pour ne
    # pas échouer sur la nouvelle contrainte uq_user_subtopics_user_topic en
    # cas de double soumission. On inspecte donc les statements execute().
    from sqlalchemy.dialects import postgresql

    subtopic_slugs = []
    for call in mock_db.execute.call_args_list:
        stmt = call.args[0]
        # INSERT seulement (l'onboarding fait aussi un DELETE préalable sur la
        # même table pour repartir d'un état propre).
        if (
            getattr(stmt, "is_insert", False)
            and getattr(stmt, "table", None) is not None
            and stmt.table.name == "user_subtopics"
        ):
            params = stmt.compile(dialect=postgresql.dialect()).params
            subtopic_slugs.append(params.get("topic_slug"))

    assert len(subtopic_slugs) == 2
    assert "ai" in subtopic_slugs
    assert "crypto" in subtopic_slugs

    # Verify flush called
    assert mock_db.flush.called


def _prefs_added(mock_db) -> dict[str, str]:
    """Collecte les UserPreference passés à db.add → {key: value}."""
    return {
        obj.preference_key: obj.preference_value
        for call in mock_db.add.call_args_list
        for obj in [call.args[0]]
        if isinstance(obj, UserPreference)
    }


@pytest.mark.asyncio
async def test_save_onboarding_persists_deep_axes():
    """independence_pref + agrégats de swipe sont écrits comme UserPreference."""
    mock_db = AsyncMock()
    mock_db.add = MagicMock()
    service = UserService(mock_db)
    service.get_or_create_profile = AsyncMock(return_value=MagicMock())

    answers = OnboardingAnswers(
        objective="noise",
        approach="detailed",
        independence_pref="independent",
        swipe_liked=[str(uuid4()), str(uuid4()), str(uuid4())],
        swipe_disliked=[str(uuid4())],
        themes=["tech"],
    )

    await service.save_onboarding(str(uuid4()), answers)

    prefs = _prefs_added(mock_db)
    assert prefs.get("independence_pref") == "independent"
    # Agrégat compact (compteurs), pas les IDs bruts.
    assert prefs.get("swipe_liked_count") == "3"
    assert prefs.get("swipe_disliked_count") == "1"


@pytest.mark.asyncio
async def test_save_onboarding_without_deep_axes_is_backward_compatible():
    """Un payload sans les nouveaux champs ne crée aucune préférence parasite."""
    mock_db = AsyncMock()
    mock_db.add = MagicMock()
    service = UserService(mock_db)
    service.get_or_create_profile = AsyncMock(return_value=MagicMock())

    answers = OnboardingAnswers(
        objective="noise",
        approach="direct",
        themes=["tech"],
    )

    await service.save_onboarding(str(uuid4()), answers)

    prefs = _prefs_added(mock_db)
    assert "independence_pref" not in prefs
    assert "swipe_liked_count" not in prefs
    assert "swipe_disliked_count" not in prefs
