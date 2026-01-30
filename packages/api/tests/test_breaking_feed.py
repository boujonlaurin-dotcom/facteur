import pytest
from datetime import datetime, timedelta
from uuid import uuid4
from unittest.mock import MagicMock, AsyncMock

from app.models.content import Content, UserContentStatus
from app.models.source import Source
from app.models.classification_queue import ClassificationQueue
from app.models.user_personalization import UserPersonalization
from app.models.enums import ContentType, FeedFilterMode
from app.services.recommendation_service import RecommendationService

@pytest.mark.asyncio
async def test_feed_diversity_reranking():
    """
    Verify that diversity re-ranking prevents a single source from dominating the top items.
    Even if Source A has many high-scoring items, the diversity penalty should promote
    items from other sources into the top of the feed.
    """
    # 1. Setup Mock Session and Service
    session = MagicMock()
    service = RecommendationService(session)
    
    # 2. Mock _get_candidates to return 20 items from Source A and 5 from Source B
    source_a = Source(id=uuid4(), name="Source A", theme="politics", is_curated=True)
    source_b = Source(id=uuid4(), name="Source B", theme="politics", is_curated=True)
    source_c = Source(id=uuid4(), name="Source C", theme="politics", is_curated=True)
    
    candidates = []
    # 10 very recent items from Source A (base score will be high)
    for i in range(10):
        candidates.append(Content(
            id=uuid4(),
            source_id=source_a.id,
            source=source_a,
            title=f"Source A Article {i}",
            published_at=datetime.utcnow() - timedelta(minutes=i),
            content_type=ContentType.ARTICLE,
            topics=[]
        ))
    
    # 5 items from Source B, slightly older
    for i in range(5):
        candidates.append(Content(
            id=uuid4(),
            source_id=source_b.id,
            source=source_b,
            title=f"Source B Article {i}",
            published_at=datetime.utcnow() - timedelta(minutes=30+i),
            content_type=ContentType.ARTICLE,
            topics=[]
        ))

    # 5 items from Source C, even older
    for i in range(5):
        candidates.append(Content(
            id=uuid4(),
            source_id=source_c.id,
            source=source_c,
            title=f"Source C Article {i}",
            published_at=datetime.utcnow() - timedelta(hours=1+i),
            content_type=ContentType.ARTICLE,
            topics=[]
        ))
        
    # Mock the internal _get_candidates call
    service._get_candidates = AsyncMock(return_value=candidates)
    
    # Mock user profile data
    service.session.scalar = AsyncMock(return_value=None) # No profile
    service.session.execute = AsyncMock(return_value=[]) # No followed sources
    service.session.scalars = AsyncMock(return_value=MagicMock(all=lambda: [])) # No subtopics
    
    # 3. Get Feed
    user_id = uuid4()
    feed = await service.get_feed(user_id, limit=10, mode=FeedFilterMode.BREAKING)
    
    # 4. Assertions
    # With 0.7 decay, the 2nd item of Source A gets 70%, 3rd gets 49%, 4th gets 34%...
    # Top 5 should be diverse
    top_5_sources = [c.source_id for c in feed[:5]]
    unique_sources = set(top_5_sources)
    
    print(f"Top 5 sources: {[c.source.name for c in feed[:5]]}")
    
    # Test: At least 3 distinct sources in the top 10 (as requested in objectives)
    all_sources = [c.source_id for c in feed]
    unique_all = set(all_sources)
    assert len(unique_all) >= 3, f"Expected at least 3 distinct sources, got {len(unique_all)}"
    
    # Test: Source A should not occupy all top 3 slots
    top_3_sources = [c.source_id for c in feed[:3]]
    assert len(set(top_3_sources)) > 1, f"Top 3 slots dominated by single source: {[c.source.name for c in feed[:3]]}"

    # Test: The count of Source A in top 10 should be limited
    a_count = sum(1 for cid in all_sources if cid == source_a.id)
    # With 0.7 penalty, after 3 items, A's score is < 34% of base. 
    # Items from B and C (even if older) should jump ahead.
    assert a_count <= 5, f"Source A occupies too many slots ({a_count}/10)"

if __name__ == "__main__":
    import asyncio
    asyncio.run(test_feed_diversity_reranking())
