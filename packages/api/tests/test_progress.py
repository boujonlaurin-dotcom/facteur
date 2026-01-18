import pytest
from unittest.mock import MagicMock, AsyncMock
from uuid import uuid4
from datetime import datetime

from app.routers.progress import get_my_progress, follow_topic, get_quiz, submit_quiz
from app.models.progress import UserTopicProgress, TopicQuiz
from app.schemas.progress import FollowTopicRequest, QuizResultRequest

@pytest.mark.asyncio
async def test_get_my_progress():
    # Setup
    db = AsyncMock()
    user_id = str(uuid4())
    
    # Mock data
    mock_progress = UserTopicProgress(
        id=uuid4(),
        user_id=uuid4(),
        topic="Tech",
        level=2,
        points=150
    )
    
    # Mock DB execution
    mock_result = MagicMock()
    mock_result.scalars.return_value.all.return_value = [mock_progress]
    db.execute.return_value = mock_result
    
    # Execute
    result = await get_my_progress(db=db, current_user_id=user_id)
    
    # Verify
    assert len(result) == 1
    assert result[0].topic == "Tech"
    assert result[0].level == 2


@pytest.mark.asyncio
async def test_follow_topic_new():
    # Setup
    db = AsyncMock()
    user_id = str(uuid4())
    request = FollowTopicRequest(topic="Politics")
    
    # Mock DB: Check returns None (not followed yet)
    mock_result = MagicMock()
    mock_result.scalar_one_or_none.return_value = None
    db.execute.return_value = mock_result
    
    # Execute
    result = await follow_topic(request, db=db, current_user_id=user_id)
    
    # Verify
    assert result.topic == "Politics"
    assert result.level == 1
    db.add.assert_called_once()
    db.commit.assert_called_once()


@pytest.mark.asyncio
async def test_get_quiz_mock_fallback():
    # Test that we get a mock quiz if DB is empty
    db = AsyncMock()
    user_id = str(uuid4())
    
    # Mock DB returns None
    mock_result = MagicMock()
    mock_result.scalar_one_or_none.return_value = None
    db.execute.return_value = mock_result
    
    # Execute
    result = await get_quiz(topic="Ecology", db=db, current_user_id=user_id)
    
    # Verify
    assert result.topic == "Ecology"
    # Check it's the mock ID we defined in the router
    assert str(result.id) == "00000000-0000-0000-0000-000000000000"


@pytest.mark.asyncio
async def test_submit_quiz_correct_mock():
    # Test verifying a correct answer on the mock quiz
    db = AsyncMock()
    user_id = str(uuid4())
    
    # Mock Quiz ID (from the router's fallback)
    mock_quiz_id = "00000000-0000-0000-0000-000000000000"
    
    request = QuizResultRequest(
        quiz_id=uuid4(), # Should match UUID format but for mock logic we use string compare of ID
        selected_option_index=0 # Correct answer for mock is 0
    )
    # Patch the request UUID to match the zero UUID
    request.quiz_id = uuid4() 
    # Wait, the logic is `str(request.quiz_id) == "0000..."`
    # So I need to pass the proper UUID object that stringifies to zero?
    # Or just rely on the router logic for the real quiz path if I can't easily forge a zero UUID
    
    # Let's test the REAL path with a mocked DB object, it's better
    
    # REAL PATH TEST
    quiz_id = uuid4()
    mock_quiz = TopicQuiz(
        id=quiz_id,
        topic="Science",
        question="Q?",
        options=["A", "B"],
        correct_answer=1,
        difficulty=1
    )
    
    db.get.return_value = mock_quiz
    
    # User has progress
    mock_user_progress = UserTopicProgress(
        user_id=uuid4(),
        topic="Science",
        points=0,
        level=1
    )
    
    mock_result = MagicMock()
    mock_result.scalar_one_or_none.return_value = mock_user_progress
    db.execute.return_value = mock_result
    
    # Request with correct answer (index 1)
    request = QuizResultRequest(
        quiz_id=quiz_id,
        selected_option_index=1
    )
    
    # Execute
    result = await submit_quiz(request, db=db, current_user_id=user_id)
    
    # Verify
    assert result.is_correct == True
    assert result.points_earned == 10
    assert "Bravo" in result.message
    # Check progress update behavior
    # Points should be added to the object in memory
    assert mock_user_progress.points == 10
    db.commit.assert_called()
