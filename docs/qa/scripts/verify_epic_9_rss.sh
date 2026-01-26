#!/bin/bash

# Verification Script for Epic 9: Custom RSS Feeds
# Usage: ./docs/qa/scripts/verify_epic_9_rss.sh

set -e

echo "🚀 Starting Verification for Epic 9 (RSS Feeds)..."
echo "---------------------------------------------------"

# 1. VERIFY BACKEND
echo "🔍 [Backend] Running RSS Parser Unit Tests..."
cd packages/api
if [ ! -d "venv" ]; then
    echo "Creating venv..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
else
    source venv/bin/activate
fi

# Ensure PYTHONPATH includes current dir for 'app' module resolution
export PYTHONPATH=$PYTHONPATH:$(pwd)

# Verify beautifulsoup4 is installed
pip freeze | grep beautifulsoup4 || echo "⚠️  BeautifulSoup4 not found (might be issue)"

# Run tests
pytest tests/test_rss_parser.py -v
echo "✅ [Backend] Unit Tests Passed."
deactivate
cd ../..

# 2. VERIFY FRONTEND FILES
echo "🔍 [Frontend] Verifying File Structure..."
if [ -f "apps/mobile/lib/features/sources/widgets/source_preview_card.dart" ]; then
    echo "✅ [Frontend] SourcePreviewCard exists."
else
    echo "❌ [Frontend] SourcePreviewCard missing."
    exit 1
fi

if [ -f "apps/mobile/lib/features/sources/screens/add_source_screen.dart" ]; then
    echo "✅ [Frontend] AddSourceScreen exists."
else
    echo "❌ [Frontend] AddSourceScreen missing."
    exit 1
fi

echo "---------------------------------------------------"
echo "🎉 Verification Complete. Epic 9 Ready for Manual Testing."
