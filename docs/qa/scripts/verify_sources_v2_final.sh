#!/bin/bash

# Verification Script for Sources V2 (RSS, Auto-theme, Recommendation Bonus)
# Protocol: BMAD
# Usage: ./docs/qa/scripts/verify_sources_v2_final.sh

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting BMAD Verification for Sources Refactor...${NC}"
echo "---------------------------------------------------"

# 1. ENVIRONMENT CHECK
echo -e "🔍 [Step 1] Checking Environment..."
cd packages/api

if [ -z "$GITHUB_ACTIONS" ]; then
    if [ ! -d "venv" ]; then
        echo "Creating venv..."
        python3 -m venv venv
    fi
    source venv/bin/activate
    # pip install -r requirements.txt > /dev/null
else
    echo "Running in GitHub Actions - using pre-installed environment."
fi

export PYTHONPATH=$PYTHONPATH:$(pwd)
echo -e "${GREEN}✅ Environment Ready.${NC}"

# 2. BACKEND UNIT TESTS (RSS Parser + Theme Guessing)
echo -e "🔍 [Step 2] Running Backend Tests..."
# We expect these tests to pass if the implementation is correct
pytest tests/test_rss_parser.py -v

# 3. YOUTUBE REJECTION CHECK
echo -e "🔍 [Step 3] Verifying YouTube Rejection via SourceService..."
python3 - <<EOF
import asyncio
from app.services.source_service import SourceService
from unittest.mock import MagicMock

async def check():
    service = SourceService(db=MagicMock())
    try:
        await service.detect_source("https://www.youtube.com/@Underscore_")
        print("❌ Rejection failed: YouTube was accepted by SourceService")
        exit(1)
    except ValueError as e:
        if "YouTube handles are currently disabled" in str(e):
            print("✅ YouTube correctly rejected with pedagogical message")
        else:
            print(f"❌ Wrong error message: {e}")
            exit(1)

asyncio.run(check())
EOF

# 4. AUTO-THEME CHECK
echo -e "🔍 [Step 4] Verifying Auto-theme Logic..."
python3 - <<EOF
from app.services.source_service import SourceService
from unittest.mock import MagicMock

def check():
    # Mock DB for SourceService
    service = SourceService(db=MagicMock())
    
    # Test cases
    cases = [
        ("Journal du Geek", "Actualité high-tech et innovation", "tech"),
        ("Vert Le Média", "Le média de l'écologie et du climat", "environment"),
        ("Les Echos", "Actualité économique et financière", "economy"),
        ("Random Blog", "Interesting stuff", "society"), # Default
    ]
    
    for name, desc, expected in cases:
        result = service._guess_theme(name, desc)
        if result == expected:
            print(f"✅ Theme correctly guessed for '{name}': {result}")
        else:
            print(f"❌ Theme MISMATCH for '{name}': expected {expected}, got {result}")
            exit(1)

check()
EOF

# 5. RECOMMENDATION BONUS CHECK
echo -e "🔍 [Step 5] Verifying Recommendation Weights..."
python3 - <<EOF
from app.services.recommendation.scoring_config import ScoringWeights
def check():
    if hasattr(ScoringWeights, 'CUSTOM_SOURCE_BONUS') and ScoringWeights.CUSTOM_SOURCE_BONUS == 12:
        print("✅ CUSTOM_SOURCE_BONUS is defined as +12 (Phase 2 rebalance)")
    else:
        print("❌ CUSTOM_SOURCE_BONUS is missing or incorrect")
        exit(1)
check()
EOF

# 6. FRONTEND CHECKS
echo "🔍 [Step 6] Verifying Frontend Files..."
cd ../..
for f in "apps/mobile/lib/features/sources/models/source_model.dart" \
         "apps/mobile/lib/features/sources/widgets/source_preview_card.dart" \
         "apps/mobile/lib/features/sources/screens/add_source_screen.dart"; do
    if [ -f "$f" ]; then
        echo -e "✅ $f exists."
    else
        echo -e "❌ $f missing."
        exit 1
    fi
done

echo "---------------------------------------------------"
echo -e "${GREEN}🎉 PROOF OF WORK VALIDATED.${NC}"
echo -e "All BMAD criteria for Sources V2 have been met."
echo -e "Ready for atomic commits."
