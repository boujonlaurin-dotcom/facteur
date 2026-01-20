"""
Script de validation multi-scénarios pour le scoring et l'affichage des raisons.
Valide que le tag 'Theme match' est prioritaire sur 'Source suivie'.
"""
import asyncio
import os
import sys
from uuid import uuid4
from datetime import datetime
from typing import List, Dict, Set

# Setup path
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.models.content import Content
from app.models.source import Source
from app.models.user import UserProfile, UserInterest
from app.models.enums import ContentType, ReliabilityScore
from app.services.recommendation.scoring_engine import ScoringEngine, ScoringContext
from app.services.recommendation.layers import CoreLayer
from app.services.recommendation.scoring_config import ScoringWeights

# Mocking Context to avoid DB dependnecy for unit-style logic check
class MockContext(ScoringContext):
   pass

def run_scenario(scenario_name: str, interest_slugs: Set[str], followed_source_ids: Set[str], source_theme: str, source_id: str):
    print(f"\n--- Scenario: {scenario_name} ---")
    
    # 1. Setup Data
    source = Source(id=source_id, name="Test Source", theme=source_theme)
    content = Content(
        id=uuid4(),
        title="Test Article",
        source=source,
        source_id=source.id,
        published_at=datetime.utcnow()
    )
    
    # 2. Setup Context
    context = MockContext(
        user_profile=UserProfile(), # Dummy
        user_interests=interest_slugs,
        user_interest_weights={s: 1.0 for s in interest_slugs},
        followed_source_ids=followed_source_ids,
        user_prefs={},
        now=datetime.utcnow()
    )
    
    # 3. Running Core Layer
    layer = CoreLayer()
    score = layer.score(content, context)
    
    # 4. Analyze Reasons
    reasons = context.reasons.get(content.id, [])
    # Sort like RecommendationService
    reasons.sort(key=lambda x: x['score_contribution'], reverse=True)
    
    top_reason = reasons[0] if reasons else None
    
    print(f"   Interest Slugs: {interest_slugs}")
    print(f"   Followed IDs: {followed_source_ids}")
    print(f"   Source Theme: '{source_theme}' (ID: {source_id})")
    print(f"   Total Score: {score}")
    print(f"   Reasons: {[r['details'] + ' (' + str(r['score_contribution']) + ')' for r in reasons]}")
    
    if top_reason:
        print(f"   🏆 WINNER (UI Label): {top_reason['details']}")
    
    return top_reason

def main():
    # ID for our test source
    src_id = uuid4()
    
    # Scenario 1: Interest Match Only
    # Source Theme: "Tech & Futur" -> Mapper -> "tech", "science"
    # User Interest: "tech"
    r1 = run_scenario(
        "Interest Only", 
        interest_slugs={"tech"}, 
        followed_source_ids=set(), 
        source_theme="Tech & Futur", 
        source_id=src_id
    )
    assert "Theme match" in r1['details']

    # Scenario 2: Follow Only
    # User Interest: None
    # Followed: Yes
    r2 = run_scenario(
        "Follow Only", 
        interest_slugs=set(), 
        followed_source_ids={src_id}, 
        source_theme="Tech & Futur", 
        source_id=src_id
    )
    assert "Followed source" in r2['details']

    # Scenario 3: BOTH (The User's likely case)
    # Should get both bonuses. Theme Match (70) > Followed (30).
    r3 = run_scenario(
        "Both Interest & Follow", 
        interest_slugs={"tech"}, 
        followed_source_ids={src_id}, 
        source_theme="Tech & Futur", 
        source_id=src_id
    )
    
    # CRITICAL CHECK
    if "Theme match" in r3['details']:
        print("\n✅ SUCCESS: Theme match overrides Followed source.")
    else:
        print("\n❌ FAILURE: Theme match did NOT override Followed source.")

if __name__ == "__main__":
    main()
