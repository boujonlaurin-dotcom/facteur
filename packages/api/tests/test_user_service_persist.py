import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4
from app.services.user_service import UserService
from app.schemas.user import OnboardingAnswers
from app.models.user import UserSubtopic

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
    
    # Verify db.add was called for UserSubtopic
    # gathered all calls to db.add
    added_objects = [call.args[0] for call in mock_db.add.call_args_list]
    
    subtopics_added = [obj for obj in added_objects if isinstance(obj, UserSubtopic)]
    
    assert len(subtopics_added) == 2
    slugs = [s.topic_slug for s in subtopics_added]
    assert "ai" in slugs
    assert "crypto" in slugs
    
    # Verify flush called
    assert mock_db.flush.called
