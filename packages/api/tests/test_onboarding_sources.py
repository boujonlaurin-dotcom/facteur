"""Tests for onboarding source saving and theme muting."""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from sqlalchemy.dialects import postgresql

from app.models.enums import InterestState
from app.models.source import UserSource
from app.models.user_favorites import UserFavoriteInterest
from app.schemas.user import OnboardingAnswers
from app.services.user_service import UserService


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

    def test_deep_axes_fields_parsed(self):
        """independence_pref + swipe_liked/disliked parsent en snake_case."""
        liked = [str(uuid4()), str(uuid4())]
        data = {
            "objective": "noise",
            "approach": "detailed",
            "independence_pref": "independent",
            "swipe_liked": liked,
            "swipe_disliked": [str(uuid4())],
        }

        answers = OnboardingAnswers.model_validate(data)

        assert answers.independence_pref == "independent"
        assert answers.swipe_liked == liked
        assert len(answers.swipe_disliked) == 1

    def test_deep_axes_optional_backward_compat(self):
        """Un payload sans les nouveaux champs reste valide (défauts sains)."""
        data = {"objective": "noise", "approach": "direct"}

        answers = OnboardingAnswers.model_validate(data)

        assert answers.independence_pref is None
        assert answers.swipe_liked == []
        assert answers.swipe_disliked == []


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
    mock_sources_result.scalars.return_value.all.return_value = [
        source_id_1,
        source_id_2,
    ]

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
        # 1-3. delete UserPreference / UserInterest / UserSubtopic
        # 4..4+N-1. pg_insert UserInterest (one upsert per theme, N=len(themes))
        # 4+N. pg_insert UserPersonalization (muted themes)
        # then: select Source.id / select UserSource.source_id / select UserSource
        src_base = 3 + len(answers.themes) + 1
        responses_by_call = {
            src_base + 1: mock_sources_result,
            src_base + 2: mock_already_result,
            src_base + 3: mock_all_user_sources_result,
        }
        return responses_by_call.get(execute_call_count, MagicMock())

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
        assert us.state == InterestState.FOLLOWED


@pytest.mark.asyncio
async def test_save_onboarding_marks_existing_source_followed():
    """Existing hidden/unfollowed source rows are restored to followed."""
    mock_db = AsyncMock()
    mock_db.add = MagicMock()
    mock_db.scalar = AsyncMock(return_value=None)

    service = UserService(mock_db)
    mock_profile = MagicMock()
    service.get_or_create_profile = AsyncMock(return_value=mock_profile)

    source_id = uuid4()
    existing_user_source = UserSource(
        user_id=uuid4(),
        source_id=source_id,
        is_custom=False,
        state=InterestState.HIDDEN,
    )

    mock_sources_result = MagicMock()
    mock_sources_result.scalars.return_value.all.return_value = [source_id]
    mock_already_result = MagicMock()
    mock_already_result.scalars.return_value.all.return_value = [existing_user_source]
    mock_all_user_sources_result = MagicMock()
    mock_all_user_sources_result.scalars.return_value.all.return_value = [
        existing_user_source
    ]

    execute_call_count = 0

    async def mock_execute(stmt):
        nonlocal execute_call_count
        execute_call_count += 1
        # Interests are upserted via execute() (one per theme) before the
        # source selects — offset by len(themes). Cf. test above.
        src_base = 3 + len(answers.themes) + 1
        responses_by_call = {
            src_base + 1: mock_sources_result,
            src_base + 2: mock_already_result,
            src_base + 3: mock_all_user_sources_result,
        }
        return responses_by_call.get(execute_call_count, MagicMock())

    mock_db.execute = AsyncMock(side_effect=mock_execute)

    answers = OnboardingAnswers(
        objective="noise",
        approach="direct",
        response_style="decisive",
        themes=["tech"],
        preferred_sources=[str(source_id)],
    )

    result = await service.save_onboarding(str(uuid4()), answers)

    assert result["sources_created"] == 0
    assert existing_user_source.state == InterestState.FOLLOWED


@pytest.mark.asyncio
async def test_save_onboarding_seeds_theme_favorites_when_empty():
    """First onboarding seeds up to three favorite theme slots."""
    mock_db = AsyncMock()
    mock_db.add = MagicMock()
    mock_db.scalar = AsyncMock(return_value=None)
    mock_db.execute = AsyncMock(return_value=MagicMock())

    service = UserService(mock_db)
    mock_profile = MagicMock()
    service.get_or_create_profile = AsyncMock(return_value=mock_profile)

    answers = OnboardingAnswers(
        objective="noise",
        approach="direct",
        response_style="decisive",
        themes=["tech", "science", "culture", "economy"],
    )

    await service.save_onboarding(str(uuid4()), answers)

    added_objects = [call.args[0] for call in mock_db.add.call_args_list]
    favorites = [obj for obj in added_objects if isinstance(obj, UserFavoriteInterest)]

    assert [(f.interest_slug, f.position) for f in favorites] == [
        ("tech", 0),
        ("science", 1),
        ("culture", 2),
    ]

    # Interests are now persisted via atomic upserts (execute), not db.add().
    # Read the declared state back from each insert into user_interests.
    executed = [call.args[0] for call in mock_db.execute.call_args_list]
    interest_states = {}
    for stmt in executed:
        table = getattr(stmt, "table", None)
        if not getattr(stmt, "is_insert", False) or table is None:
            continue
        if table.name != "user_interests":
            continue
        params = stmt.compile(dialect=postgresql.dialect()).params
        interest_states[params["interest_slug"]] = params["state"]

    favorite_interest_states = {
        slug: state
        for slug, state in interest_states.items()
        if slug in {"tech", "science", "culture"}
    }
    assert set(favorite_interest_states.values()) == {InterestState.FAVORITE}
    # Le 4e thème reste un simple suivi.
    assert interest_states["economy"] == InterestState.FOLLOWED


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
