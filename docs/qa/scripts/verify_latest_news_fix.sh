#!/bin/bash
# Script de vérification pour le fix de diversité du feed "Latest News"

# Path absolu vers la racine du projet
PROJECT_ROOT="/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur"
API_DIR="$PROJECT_ROOT/packages/api"

echo "🔍 Démarrage de la vérification de diversité du feed..."

# Activation du venv
source "$API_DIR/venv/bin/activate"

# Export PYTHONPATH
export PYTHONPATH="$API_DIR:$PYTHONPATH"

# Exécution du test de diversité
echo "🧪 Exécution du test unitaire de diversité..."
pytest "$API_DIR/tests/test_breaking_feed.py"

if [ $? -eq 0 ]; then
    echo "✅ Le test de diversité a réussi !"
else
    echo "❌ Le test de diversité a échoué."
    exit 1
fi

# Simulation locale du feed live (via script python rapide)
echo "📊 Analyse de la distribution des sources dans le feed BREAKING simulé..."
python3 - <<EOF
import asyncio
import sys
import os
from uuid import uuid4
from sqlalchemy import select, text
from app.database import async_session_maker
from app.models.content import Content, UserContentStatus
from app.models.source import Source
from app.models.classification_queue import ClassificationQueue
from app.models.user_personalization import UserPersonalization
from app.services.recommendation_service import RecommendationService
from app.models.enums import FeedFilterMode

async def check_live_diversity():
    async with async_session_maker() as session:
        # Get first user
        result = await session.execute(text("SELECT user_id FROM user_profiles LIMIT 1"))
        user_id = result.scalar()
        if not user_id:
             print("Skipping live check: No users in DB")
             return

        service = RecommendationService(session)
        feed = await service.get_feed(user_id, limit=20, mode=FeedFilterMode.BREAKING)
        
        sources = [c.source.name for c in feed]
        counts = {}
        for s in sources:
            counts[s] = counts.get(s, 0) + 1
            
        print(f"\nDistribution (Top 20):")
        for name, count in sorted(counts.items(), key=lambda x: x[1], reverse=True):
            print(f"- {name}: {count}")
            
        unique_count = len(counts)
        print(f"\nTotal sources uniques : {unique_count}")
        if unique_count >= 3:
            print("✅ Critère de diversité respecté (>= 3 sources).")
        else:
            print("⚠️ Attention : Diversité faible (< 3 sources).")

if __name__ == "__main__":
    asyncio.run(check_live_diversity())
EOF

echo "🏁 Fin de la vérification."
