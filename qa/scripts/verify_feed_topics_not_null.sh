#!/bin/bash
# Verification: Feed endpoint - Aucun item ne doit avoir topics=null

set -e

echo "🧪 Testing feed topics field..."
echo ""

# Check required env vars
if [ -z "$FACTEUR_TEST_TOKEN" ]; then
  echo "❌ ERROR: FACTEUR_TEST_TOKEN not set"
  echo "   Export a valid auth token: export FACTEUR_TEST_TOKEN='Bearer eyJ...'"
  exit 1
fi

if [ -z "$API_BASE_URL" ]; then
  echo "⚠️  WARNING: API_BASE_URL not set, using default"
  API_BASE_URL="https://facteur-production.up.railway.app"
fi

echo "📍 Testing endpoint: $API_BASE_URL/api/feed/"
echo ""

# Fetch feed with higher limit to test more items
RESPONSE=$(curl -s -H "Authorization: $FACTEUR_TEST_TOKEN" \
  "$API_BASE_URL/api/feed/?limit=50")

# Check if request succeeded
if [ -z "$RESPONSE" ]; then
  echo "❌ FAIL: Empty response from API"
  exit 1
fi

# Check for error in response
ERROR=$(echo "$RESPONSE" | jq -r '.detail // .error // empty')
if [ -n "$ERROR" ]; then
  echo "❌ FAIL: API returned error: $ERROR"
  echo ""
  echo "Full response:"
  echo "$RESPONSE" | jq '.'
  exit 1
fi

# Count items with null topics
NULL_COUNT=$(echo "$RESPONSE" | jq '[.items[]? | select(.topics == null)] | length' 2>/dev/null || echo "0")

# Count total items
TOTAL_COUNT=$(echo "$RESPONSE" | jq '.items | length' 2>/dev/null || echo "0")

echo "📊 Results:"
echo "   Total items: $TOTAL_COUNT"
echo "   Items with topics=null: $NULL_COUNT"
echo ""

if [ "$NULL_COUNT" -eq 0 ]; then
  echo "✅ PASS: No null topics in feed (tested $TOTAL_COUNT items)"

  # Show a sample of topics to verify they're arrays
  echo ""
  echo "📝 Sample topics (first 3 items):"
  echo "$RESPONSE" | jq '.items[0:3] | .[] | {title: .title, topics: .topics}' 2>/dev/null || true

  exit 0
else
  echo "❌ FAIL: Found $NULL_COUNT items with null topics"
  echo ""
  echo "Items with null topics:"
  echo "$RESPONSE" | jq '.items[] | select(.topics == null) | {id, title, topics}' 2>/dev/null || true
  exit 1
fi
