
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

@pytest.mark.asyncio
async def test_persona_ranking_weights():
    """
    Validation "Bout-en-bout" (Simulée) des pondérations.
    Objectif : Vérifier que les Thèmes ressortent AVANT les sources suivies, 
    et que la Confiance (High Quality) a un impact tangible.
    
    Weights Configured:
    - Theme: 70
    - Followed (Use Source): 30
    - Global Trust (High Qual): 15
    - Standard Source: 10
    """
    service = RecommendationService(MagicMock())
    now = datetime.utcnow()
    user_interests = {"tech"} # User likes Tech
    followed_source_id = uuid4() # User trusts this source (UserSource)
    
    # 1. THE PERFECT MATCH: Theme + Followed + High Quality
    # Score = 70 (Theme) + 30 (Followed) + 15 (High Qual) + ~30 (Recency) = ~145
    s1 = Source(id=followed_source_id, theme="tech", reliability_score="high")
    c1 = Content(id=uuid4(), source_id=s1.id, source=s1, published_at=now)
    score1 = service._score_content(c1, user_interests, {followed_source_id}, now)
    
    # 2. THEME ONLY: Theme + Random Source (Standard)
    # Score = 70 (Theme) + 10 (Standard) + ~30 (Recency) = ~110
    s2 = Source(id=uuid4(), theme="tech", reliability_score="medium")
    c2 = Content(id=uuid4(), source_id=s2.id, source=s2, published_at=now)
    score2 = service._score_content(c2, user_interests, {followed_source_id}, now)

    # 3. FOLLOWED ONLY: No Theme + Followed + Medium Quality
    # Score = 0 (Theme) + 30 (Followed) + ~30 (Recency) = ~60
    s3 = Source(id=followed_source_id, theme="politics", reliability_score="medium")
    c3 = Content(id=uuid4(), source_id=s3.id, source=s3, published_at=now)
    score3 = service._score_content(c3, user_interests, {followed_source_id}, now)
    
    # 4. TRUSTED (GLOBAL) ONLY: No Theme + Not Followed + High Quality
    # Score = 0 (Theme) + 10 (Standard) + 15 (High Qual) + ~30 (Recency) = ~55
    s4 = Source(id=uuid4(), theme="politics", reliability_score="high")
    c4 = Content(id=uuid4(), source_id=s4.id, source=s4, published_at=now)
    score4 = service._score_content(c4, user_interests, {followed_source_id}, now)
    
    print(f"\n--- Scores ---")
    print(f"1. Perfect Match: {score1}")
    print(f"2. Theme Only   : {score2}")
    print(f"3. Followed Only: {score3}")
    print(f"4. Global Trust : {score4}")
    
    # ASSERTIONS
    
    # 1. Theme Supremacy: Theme Only (110) >> Followed Only (60)
    assert score2 > score3 + 30, "Thèmes suivis doivent dominer les sources suivies (Feedback User)"
    
    # 2. Trust Impact: Global Trust (55) vs Standard (40)
    # Standard would be 10 + 30 = 40. Trust is 55. +15 diff.
    # Let's compare to a purely standard random item
    s_trash = Source(id=uuid4(), theme="politics", reliability_score="low")
    c_trash = Content(id=uuid4(), source_id=s_trash.id, source=s_trash, published_at=now)
    score_trash = service._score_content(c_trash, user_interests, {followed_source_id}, now)
    # Trash score = 0 (Theme) + 10 (Standard) - 30 (Low Malus) + 30 (Recency) = 10
    
    assert score4 > score_trash + 30, "Trusted content must be significantly visible above trash"
    
    # 3. Trust vs Followed gap
    # Followed (60) vs Global Trust (55). 
    # Gap is now small (5 points). Before it was 25 points.
    assert abs(score3 - score4) < 10, "Gap between User-Selected Trust and Global Trust should be small"

