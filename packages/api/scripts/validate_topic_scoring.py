#!/usr/bin/env python3
"""
validate_topic_scoring.py - E2E Validation for Story 4.1d

Validates that ArticleTopicLayer correctly scores articles based on
topic intersection with user subtopics.

Scenario:
- User has subtopic preferences: {ai}
- Article 1: Topics = [ai, crypto] → Should get +40pts
- Article 2: Topics = [space, biodiversity] → Should get 0pts

Expected: Article 1 score > Article 2 score by exactly 40 points.

Usage:
    cd packages/api
    source .venv/bin/activate
    python scripts/validate_topic_scoring.py
"""

import sys
from datetime import datetime
from uuid import uuid4

# Add project root to path for imports
sys.path.insert(0, '.')

from app.models.content import Content
from app.models.source import Source
from app.models.enums import ContentType
from app.services.recommendation.scoring_engine import ScoringEngine, ScoringContext
from app.services.recommendation.layers import (
    CoreLayer, 
    StaticPreferenceLayer, 
    BehavioralLayer, 
    QualityLayer, 
    VisualLayer,
    ArticleTopicLayer
)


def create_test_content(title: str, topics: list[str], source_theme: str = "tech") -> Content:
    """Create a test Content object with specific topics."""
    source = Source(
        id=uuid4(),
        name=f"TestSource-{source_theme}",
        theme=source_theme,
        is_curated=True
    )
    return Content(
        id=uuid4(),
        title=title,
        url=f"http://example.com/{title.lower().replace(' ', '-')}",
        source_id=source.id,
        source=source,
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        topics=topics,
        thumbnail_url="http://example.com/thumb.jpg"
    )


def create_test_context(user_subtopics: set[str], user_interests: set[str] = None) -> ScoringContext:
    """Create a ScoringContext with specified subtopics."""
    return ScoringContext(
        user_profile=None,
        user_interests=user_interests or {"tech"},
        user_interest_weights={"tech": 1.0},
        followed_source_ids=set(),
        user_prefs={},
        now=datetime.utcnow(),
        user_subtopics=user_subtopics
    )


def main():
    print("=" * 60)
    print("🎯 ArticleTopicLayer Validation (Story 4.1d)")
    print("=" * 60)
    
    # Create scoring engine with ArticleTopicLayer
    engine = ScoringEngine([
        CoreLayer(),
        StaticPreferenceLayer(),
        BehavioralLayer(),
        QualityLayer(),
        VisualLayer(),
        ArticleTopicLayer()
    ])
    
    # User profile: interested in "tech" theme, prefers "ai" subtopic
    context = create_test_context(user_subtopics={"ai"})
    
    # Test Articles
    article_ai = create_test_content(
        title="L'IA révolutionne la santé",
        topics=["ai", "health"],
        source_theme="tech"
    )
    
    article_space = create_test_content(
        title="SpaceX lance une nouvelle fusée",
        topics=["space", "innovation"],
        source_theme="tech"
    )
    
    # Compute scores
    score_ai = engine.compute_score(article_ai, context)
    score_space = engine.compute_score(article_space, context)
    
    delta = score_ai - score_space
    
    print(f"\n📊 Résultats de Scoring:")
    print(f"   Article AI     : {score_ai:.1f} pts")
    print(f"   Article Space  : {score_space:.1f} pts")
    print(f"   Delta          : +{delta:.1f} pts")
    
    # Verify delta is +40 (TOPIC_MATCH value)
    expected_delta = 40.0
    tolerance = 0.1
    
    print(f"\n🔍 Validation:")
    
    if abs(delta - expected_delta) <= tolerance:
        print(f"   ✅ Delta = +{delta:.1f}pts (attendu: +{expected_delta:.1f}pts)")
        print(f"\n✅ ArticleTopicLayer fonctionne correctement!")
        
        # Show reasons breakdown
        print(f"\n📋 Reasons (Article AI):")
        for reason in context.reasons.get(article_ai.id, []):
            print(f"   - [{reason['layer']}] +{reason['score_contribution']:.1f} : {reason['details']}")
        
        return 0
    else:
        print(f"   ❌ Delta = +{delta:.1f}pts (attendu: +{expected_delta:.1f}pts)")
        print(f"\n❌ ÉCHEC: ArticleTopicLayer ne fonctionne pas comme attendu!")
        return 1


if __name__ == "__main__":
    sys.exit(main())
