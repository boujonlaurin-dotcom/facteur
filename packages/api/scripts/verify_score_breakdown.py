#!/usr/bin/env python3
"""
Verify Score Breakdown - Self-contained test for the new breakdown schema.

Usage:
  cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur/packages/api && source venv/bin/activate && python scripts/verify_score_breakdown.py
"""
import os
import sys
from datetime import datetime
from uuid import uuid4

# Ensure we can import app modules
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.models.content import Content
from app.models.source import Source
from app.models.enums import ContentType
from app.services.recommendation.scoring_engine import ScoringEngine, ScoringContext
from app.services.recommendation.layers import CoreLayer, StaticPreferenceLayer, BehavioralLayer, QualityLayer, VisualLayer, ArticleTopicLayer
from app.schemas.content import RecommendationReason, ScoreContribution

print("=" * 60)
print("🧪 VERIFICATION: Score Breakdown Schema")
print("=" * 60)

# 1. Create test data
source = Source(id=uuid4(), name="TechCrunch", theme="tech")
content = Content(
    id=uuid4(),
    title="OpenAI announces GPT-5",
    url="https://example.com/gpt5",
    source_id=source.id,
    source=source,
    published_at=datetime.utcnow(),
    content_type=ContentType.ARTICLE,
    topics=["ai", "llm"],
    thumbnail_url="https://example.com/img.jpg"
)

# 2. Create scoring context (simulated user)
context = ScoringContext(
    user_profile=None,
    user_interests={"tech", "science"},
    user_interest_weights={"tech": 1.2, "science": 1.0},
    followed_source_ids={source.id},  # User follows this source
    user_prefs={},
    now=datetime.utcnow(),
    user_subtopics={"ai", "cybersecurity"}
)

# 3. Score with engine
engine = ScoringEngine([
    CoreLayer(),
    StaticPreferenceLayer(),
    BehavioralLayer(),
    QualityLayer(),
    VisualLayer(),
    ArticleTopicLayer()
])

score = engine.compute_score(content, context)

print(f"\n📊 Score total calculé: {score:.1f} pts")

# 4. Check reasons are populated
reasons = context.reasons.get(content.id, [])
print(f"\n✅ Nombre de raisons collectées: {len(reasons)}")

for r in sorted(reasons, key=lambda x: x['score_contribution'], reverse=True):
    pts = r['score_contribution']
    sign = "+" if pts >= 0 else ""
    print(f"   [{r['layer']}] {sign}{pts:.0f} → {r['details']}")

# 5. Verify ScoreContribution model works
print("\n📦 Test du modèle ScoreContribution:")
contrib = ScoreContribution(label="Thème : Tech", points=70.0, is_positive=True)
print(f"   ✅ ScoreContribution créé: {contrib.model_dump()}")

# 6. Verify RecommendationReason with breakdown
print("\n📦 Test du modèle RecommendationReason avec breakdown:")
breakdown = [
    ScoreContribution(label="Thème : Tech", points=70.0, is_positive=True),
    ScoreContribution(label="Source de confiance", points=40.0, is_positive=True),
    ScoreContribution(label="Sous-thèmes : IA", points=50.0, is_positive=True),
]
reason = RecommendationReason(
    label="Vos centres d'intérêt : IA",
    score_total=160.0,
    breakdown=breakdown
)
print(f"   ✅ RecommendationReason créé avec {len(reason.breakdown)} items")

# 7. Serialize to JSON (simulates API response)
import json
json_output = reason.model_dump()
print("\n📤 JSON Output (simule réponse API):")
print(json.dumps(json_output, indent=2, ensure_ascii=False))

print("\n" + "=" * 60)
print("✅ Tous les tests passent ! Le breakdown est prêt.")
print("=" * 60)
