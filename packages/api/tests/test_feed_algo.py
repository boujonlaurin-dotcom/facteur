
import pytest
from datetime import datetime, timedelta
from uuid import uuid4
from unittest.mock import MagicMock

from app.models.content import Content
from app.models.source import Source
from app.services.recommendation_service import RecommendationService

@pytest.mark.asyncio
async def test_score_content_logic():
    service = RecommendationService(MagicMock())
    
    # Setup
    now = datetime.utcnow()
    user_interests = {"tech", "science"}
    followed_source_id = uuid4()
    other_source_id = uuid4()
    
    # Case 1: Perfect Match (Interest + Trusted + Recent)
    # Score = 50 (Theme) + 30 (Trusted) + ~30 (Fresh) = ~110
    source1 = Source(id=followed_source_id, theme="tech")
    content1 = Content(
        id=uuid4(),
        source_id=followed_source_id,
        source=source1,
        published_at=now - timedelta(minutes=10)
    )
    score1 = service._score_content(content1, user_interests, {followed_source_id}, now)
    
    # Case 2: Interest Only (Interest + Untrusted + Recent)
    # Score = 50 (Theme) + 10 (Untrusted) + ~30 (Fresh) = ~90
    source2 = Source(id=other_source_id, theme="tech")
    content2 = Content(
        id=uuid4(), 
        source_id=other_source_id, 
        source=source2, 
        published_at=now - timedelta(minutes=10)
    )
    score2 = service._score_content(content2, user_interests, {followed_source_id}, now)
    
    # Case 3: Trusted Only (No Interest + Trusted + Recent)
    # Score = 0 (Theme) + 30 (Trusted) + ~30 (Fresh) = ~60
    source3 = Source(id=followed_source_id, theme="politics")
    content3 = Content(
        id=uuid4(), 
        source_id=followed_source_id, 
        source=source3, 
        published_at=now - timedelta(minutes=10)
    )
    score3 = service._score_content(content3, user_interests, {followed_source_id}, now)

    # Case 4: Old Content (Interest + Trusted + Old)
    # Score = 50 + 30 + (30 / (24/24 + 1)) = 80 + 15 = 95
    # Let's make it very old -> 48 hours
    # Score = 50 + 30 + (30 / (48/24 + 1)) = 80 + 10 = 90
    content4 = Content(
        id=uuid4(), 
        source_id=followed_source_id, 
        source=source1, 
        published_at=now - timedelta(hours=48)
    )
    score4 = service._score_content(content4, user_interests, {followed_source_id}, now)

    print(f"Score 1 (Perfect): {score1}")
    print(f"Score 2 (Interest): {score2}")
    print(f"Score 3 (Trusted): {score3}")
    print(f"Score 4 (Old): {score4}")

    assert score1 > score2, "Trusted source should boost score"
    assert score1 > score3, "Interest match should boost score"
    assert score1 > score4, "Recency should boost score"
    assert score2 > score3, "Interest match (50) should outweigh Trusted (30-10=20)"
