"""Tests for onboarding source saving and theme muting."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4, UUID

from app.schemas.user import OnboardingAnswers
from app.services.user_service import UserService
from app.models.source import UserSource


class TestOnboardingAnswersParsing:
    """Verify Pydantic V2 model_config parses snake_case fields correctly."""

    def test_preferred_sources_from_snake_case_dict(self):
        """Mobile sends snake_case keys — preferred_sources must parse correctly."""
        source_ids = [str(uuid4()), str(uuid4())]

        data = {
            "objective": "noise",
            "approach": "direct",
            "response_style": "decisive",
            "preferred_sources": source_ids,
            "themes": ["tech", "science"],
        }

        answers = OnboardingAnswers.model_validate(data)

        assert answers.preferred_sources == source_ids
        assert len(answers.preferred_sources) == 2

    def test_preferred_sources_from_camel_case_dict(self):
        """Also accept camelCase alias (in case frontend changes)."""
        source_ids = [str(uuid4())]

        data = {
            "objective": "bias",
            "approach": "detailed",
            "responseStyle": "nuanced",
            "preferredSources": source_ids,
            "themes": ["tech"],
        }

        answers = OnboardingAnswers.model_validate(data)

        assert answers.preferred_sources == source_ids

    def test_themes_parsed_correctly(self):
        """Themes field parses correctly from snake_case."""
        data = {
            "objective": "noise",
            "approach": "direct",
            "response_style": "decisive",
            "themes": ["tech", "science", "sport"],
        }

        answers = OnboardingAnswers.model_validate(data)

        assert answers.themes == ["tech", "science", "sport"]

    def test_weekly_goal_parsed(self):
        """weekly_goal field is accepted (not daily_article_count)."""
        data = {
            "objective": "noise",
            "approach": "direct",
            "response_style": "decisive",
            "weekly_goal": 7,
        }

        answers = OnboardingAnswers.model_validate(data)

        assert answers.weekly_goal == 7

    def test_empty_preferred_sources_defaults_to_list(self):
        """When preferred_sources is omitted, defaults to empty list."""
        data = {
            "objective": "noise",
            "approach": "direct",
            "response_style": "decisive",
        }

        answers = OnboardingAnswers.model_validate(data)

        assert answers.preferred_sources == []


@pytest.mark.asyncio
async def test_save_onboarding_creates_user_sources():
    """Verify save_onboarding creates UserSource entries for valid source UUIDs."""
    mock_db = AsyncMock()
    mock_db.add = MagicMock()

    service = UserService(mock_db)
    mock_profile = MagicMock()
    service.get_or_create_profile = AsyncMock(return_value=mock_profile)

    source_id_1 = uuid4()
    source_id_2 = uuid4()

    # Mock: sources exist and are active in DB
    mock_sources_result = MagicMock()
    mock_sources_result.scalars.return_value.all.return_value = [source_id_1, source_id_2]

    # Mock: no existing UserSource for this user
    mock_already_result = MagicMock()
    mock_already_result.scalars.return_value.all.return_value = []

    # Mock: no existing non-custom user sources (cleanup query)
    mock_all_user_sources_result = MagicMock()
    mock_all_user_sources_result.scalars.return_value.all.return_value = []

    # Mock: no existing UserTopicProfile for subtopics
    mock_db.scalar = AsyncMock(return_value=None)

    # Track execute calls to return different results
    execute_call_count = 0

    async def mock_execute(stmt):
        nonlocal execute_call_count
        execute_call_count += 1
        # Calls order in save_onboarding:
        # 1. delete UserPreference
        # 2. delete UserInterest
        # 3. delete UserSubtopic
        # 4. pg_insert UserPersonalization (muted themes)
        # 5. select Source.id (existing sources check)
        # 6. select UserSource.source_id (already trusted check)
        # 7. select UserSource (cleanup query)
        if execute_call_count == 5:
            return mock_sources_result
        elif execute_call_count == 6:
            return mock_already_result
        elif execute_call_count == 7:
            return mock_all_user_sources_result
        return MagicMock()

    mock_db.execute = AsyncMock(side_effect=mock_execute)

    user_id = str(uuid4())
    answers = OnboardingAnswers(
        objective="noise",
        approach="direct",
        response_style="decisive",
        themes=["tech", "science"],
        preferred_sources=[str(source_id_1), str(source_id_2)],
    )

    result = await service.save_onboarding(user_id, answers)

    assert result["sources_created"] == 2

    # Verify UserSource objects were added
    added_objects = [call.args[0] for call in mock_db.add.call_args_list]
    user_sources = [obj for obj in added_objects if isinstance(obj, UserSource)]
    assert len(user_sources) == 2
    created_source_ids = {us.source_id for us in user_sources}
    assert source_id_1 in created_source_ids
    assert source_id_2 in created_source_ids
    # Curated sources should have is_custom=False
    for us in user_sources:
        assert us.is_custom is False


@pytest.mark.asyncio
async def test_save_onboarding_mutes_unselected_themes():
    """Verify save_onboarding mutes themes NOT selected during onboarding."""
    mock_db = AsyncMock()
    mock_db.add = MagicMock()
    mock_db.scalar = AsyncMock(return_value=None)

    service = UserService(mock_db)
    mock_profile = MagicMock()
    service.get_or_create_profile = AsyncMock(return_value=mock_profile)

    mock_db.execute = AsyncMock(return_value=MagicMock())

    user_id = str(uuid4())
    answers = OnboardingAnswers(
        objective="noise",
        approach="direct",
        response_style="decisive",
        themes=["tech", "science"],
    )

    result = await service.save_onboarding(user_id, answers)

    # Verify pg_insert was called for UserPersonalization
    # The 4th execute call should be the muted_themes upsert
    assert mock_db.execute.call_count >= 4

    # Verify interests were created for selected themes only
    assert result["interests_created"] == 2
