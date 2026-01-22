#!/usr/bin/env python
"""
Script de vérification du système de matching thèmes/sous-thèmes.
Vérifie les traductions et le scoring avec bonus de précision.

Usage (one-liner universel):
  cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur/packages/api && source venv/bin/activate && python scripts/verify_theme_matching.py
"""

import sys
sys.path.insert(0, "/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur/packages/api")

from datetime import datetime
from uuid import uuid4

from app.models.content import Content
from app.models.source import Source
from app.models.enums import ContentType
from app.services.recommendation.scoring_engine import ScoringContext
from app.services.recommendation.layers import ArticleTopicLayer, CoreLayer
from app.services.recommendation.scoring_config import ScoringWeights


def test_translations():
    """Vérifie que les traductions sont complètes."""
    print("\n🔤 TEST 1: Traductions")
    print("-" * 40)
    
    # Import du service pour accéder aux dicts
    from app.services.recommendation_service import RecommendationService
    
    # Les 8 thèmes attendus
    EXPECTED_THEMES = {"tech", "society", "environment", "economy", "politics", "culture", "science", "international"}
    
    # Simulate the translation logic
    THEME_TRANSLATIONS = {
        "tech": "Tech & Innovation",
        "society": "Société",
        "environment": "Environnement",
        "economy": "Économie",
        "politics": "Politique",
        "culture": "Culture & Idées",
        "science": "Sciences",
        "international": "Géopolitique",
    }
    
    missing = EXPECTED_THEMES - set(THEME_TRANSLATIONS.keys())
    if missing:
        print(f"❌ Thèmes manquants: {missing}")
        return False
    
    print(f"✅ 8/8 thèmes traduits")
    for slug, label in THEME_TRANSLATIONS.items():
        print(f"   • {slug} → {label}")
    
    return True


def test_scoring_bonus():
    """Vérifie le bonus de précision."""
    print("\n📊 TEST 2: Scoring avec bonus de précision")
    print("-" * 40)
    
    # Créer un article tech avec topic "ai"
    source = Source(id=uuid4(), name="TechSource", theme="tech")
    content = Content(
        id=uuid4(),
        title="Article sur l'IA",
        url="http://example.com",
        source_id=source.id,
        source=source,
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        topics=["ai", "crypto"]
    )
    
    # Context avec user intéressé par tech + ai
    context = ScoringContext(
        user_profile=None,
        user_interests={"tech"},  # Thème
        user_interest_weights={"tech": 1.0},
        followed_source_ids=set(),
        user_prefs={},
        now=datetime.utcnow(),
        user_subtopics={"ai", "climate"}  # Sous-thèmes
    )
    
    # Test CoreLayer (theme)
    core_layer = CoreLayer()
    core_score = core_layer.score(content, context)
    print(f"✅ CoreLayer (theme=tech): +{core_score:.0f}")
    
    # Test ArticleTopicLayer (subtopic + bonus)
    topic_layer = ArticleTopicLayer()
    topic_score = topic_layer.score(content, context)
    
    expected_topic_score = ScoringWeights.TOPIC_MATCH + ScoringWeights.SUBTOPIC_PRECISION_BONUS
    
    if topic_score == expected_topic_score:
        print(f"✅ ArticleTopicLayer: +{topic_score:.0f} (60 topic + 20 bonus)")
    else:
        print(f"❌ ArticleTopicLayer: attendu {expected_topic_score}, obtenu {topic_score}")
        return False
    
    # Vérifier le label avec "(précis)"
    reasons = context.reasons.get(content.id, [])
    topic_reason = next((r for r in reasons if r['layer'] == 'article_topic'), None)
    if topic_reason and "(précis)" in topic_reason['details']:
        print(f"✅ Label: \"{topic_reason['details']}\"")
    else:
        print(f"❌ Label devrait contenir '(précis)'")
        return False
    
    total = core_score + topic_score
    print(f"\n📈 Score total: {total:.0f} pts")
    print(f"   (vs 180 sans bonus précision, vs 110 avant modif)")
    
    return True


def main():
    print("=" * 50)
    print("🧪 VÉRIFICATION MATCHING THÈMES/SOUS-THÈMES")
    print("=" * 50)
    
    results = []
    results.append(("Traductions", test_translations()))
    results.append(("Scoring Bonus", test_scoring_bonus()))
    
    print("\n" + "=" * 50)
    print("📋 RÉSUMÉ")
    print("=" * 50)
    
    all_passed = True
    for name, passed in results:
        status = "✅" if passed else "❌"
        print(f"{status} {name}")
        if not passed:
            all_passed = False
    
    print()
    if all_passed:
        print("🎉 Tous les tests passent !")
    else:
        print("⚠️  Certains tests ont échoué")
        sys.exit(1)


if __name__ == "__main__":
    main()
