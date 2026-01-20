#!/usr/bin/env python3
"""
Local test script for ClassificationService with REAL CamemBERT model.

NOT for CI/CD - downloads ~440MB model on first run.

Usage:
    cd packages/api
    source venv/bin/activate
    ML_ENABLED=true python scripts/test_ml_local.py
"""

import os
import sys

# Ensure ML is enabled for this test
os.environ["ML_ENABLED"] = "true"

# Add parent to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    print("🧠 Testing ClassificationService with CamemBERT...")
    print("=" * 60)
    print("⏳ Loading model (first run downloads ~440MB)...\n")
    
    from app.services.ml.classification_service import ClassificationService
    
    service = ClassificationService()
    
    if not service.is_ready():
        print("❌ Model not loaded! Check ML_ENABLED env var.")
        sys.exit(1)
    
    print("✅ Model loaded successfully!\n")
    
    # Test cases
    test_cases = [
        {
            "title": "OpenAI lance GPT-5, le modèle d'IA le plus avancé",
            "description": "La nouvelle version surpasse tous les benchmarks existants",
            "expected": ["ai", "tech"],
        },
        {
            "title": "Le réchauffement climatique s'accélère selon le dernier rapport du GIEC",
            "description": "Les températures pourraient augmenter de 2°C d'ici 2050",
            "expected": ["climate", "environment"],
        },
        {
            "title": "Macron annonce une réforme majeure des retraites",
            "description": "Le gouvernement prévoit de repousser l'âge de départ à 65 ans",
            "expected": ["politics", "economy", "work"],
        },
    ]
    
    print("Testing classification on 3 example articles:\n")
    
    all_passed = True
    for i, case in enumerate(test_cases, 1):
        topics = service.classify(
            title=case["title"],
            description=case.get("description", ""),
        )
        
        # Check if at least one expected topic is present
        expected_present = any(exp in topics for exp in case["expected"])
        status = "✅" if expected_present else "⚠️"
        
        if not expected_present:
            all_passed = False
        
        print(f"{i}. \"{case['title'][:50]}...\"")
        print(f"   → Topics: {topics}")
        print(f"   → Expected any of: {case['expected']}")
        print(f"   → Status: {status}\n")
    
    print("=" * 60)
    if all_passed:
        print("✅ Classification working! All tests passed.")
    else:
        print("⚠️  Some classifications didn't match expected topics.")
        print("   This may be normal - CamemBERT is probabilistic.")
    
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
