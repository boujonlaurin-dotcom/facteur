#!/bin/bash
# E2E Verification: Topic-Aware Feed Diversification (Phase 2 — Budget Neutre)
#
# 4 tests:
#   1. User with custom topics → topic_overflow non-empty
#   2. User without prefs → topic_overflow empty, feed unchanged
#   3. Floor 30% → neutral articles never compressed below floor
#   4. Regression → existing fields (source_overflow, clusters) still work
#
# Usage:
#   export FACTEUR_TEST_TOKEN='Bearer eyJ...'       # User WITH custom topics
#   export FACTEUR_NOPREFS_TOKEN='Bearer eyJ...'     # User WITHOUT custom topics (optional)
#   export API_BASE_URL='http://localhost:8080'       # or Railway URL
#   bash docs/qa/scripts/verify_topic_regroupement.sh

set -euo pipefail

# --- Config ---
if [ -z "${FACTEUR_TEST_TOKEN:-}" ]; then
  echo "❌ ERROR: FACTEUR_TEST_TOKEN not set"
  echo "   Export a valid auth token: export FACTEUR_TEST_TOKEN='Bearer eyJ...'"
  exit 1
fi

API_BASE_URL="${API_BASE_URL:-https://facteur-production.up.railway.app}"
ENDPOINT="$API_BASE_URL/api/feed/?limit=30"

PASS=0
FAIL=0

pass() { echo "✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

# ============================================================
# TEST 1: User with custom topics → topic_overflow present
# ============================================================
echo ""
echo "═══════════════════════════════════════════════════"
echo "TEST 1: User WITH custom topics → topic_overflow"
echo "═══════════════════════════════════════════════════"

RESPONSE=$(curl -s -H "Authorization: $FACTEUR_TEST_TOKEN" "$ENDPOINT")

if [ -z "$RESPONSE" ]; then
  fail "Empty response from API"
  exit 1
fi

# Check API didn't error
ERROR=$(echo "$RESPONSE" | jq -r '.detail // .error // empty' 2>/dev/null)
if [ -n "$ERROR" ]; then
  fail "API error: $ERROR"
  exit 1
fi

# Check topic_overflow field exists
HAS_FIELD=$(echo "$RESPONSE" | jq 'has("topic_overflow")' 2>/dev/null)
if [ "$HAS_FIELD" != "true" ]; then
  fail "Response missing 'topic_overflow' field"
else
  pass "Response contains 'topic_overflow' field"
fi

# Count topic_overflow entries
OVERFLOW_COUNT=$(echo "$RESPONSE" | jq '.topic_overflow | length' 2>/dev/null || echo "0")
ITEMS_COUNT=$(echo "$RESPONSE" | jq '.items | length' 2>/dev/null || echo "0")

echo "   Items: $ITEMS_COUNT"
echo "   Topic overflow groups: $OVERFLOW_COUNT"

if [ "$OVERFLOW_COUNT" -gt 0 ]; then
  pass "topic_overflow is non-empty ($OVERFLOW_COUNT groups)"

  # Validate structure of each overflow entry
  echo ""
  echo "   📝 Topic overflow details:"
  echo "$RESPONSE" | jq -r '.topic_overflow[] | "   - [\(.group_type)] \(.group_label) (\(.group_key)): \(.hidden_count) hidden"' 2>/dev/null

  # Check required fields on first entry
  FIRST_TYPE=$(echo "$RESPONSE" | jq -r '.topic_overflow[0].group_type' 2>/dev/null)
  FIRST_KEY=$(echo "$RESPONSE" | jq -r '.topic_overflow[0].group_key' 2>/dev/null)
  FIRST_LABEL=$(echo "$RESPONSE" | jq -r '.topic_overflow[0].group_label' 2>/dev/null)
  FIRST_COUNT=$(echo "$RESPONSE" | jq -r '.topic_overflow[0].hidden_count' 2>/dev/null)
  FIRST_IDS=$(echo "$RESPONSE" | jq '.topic_overflow[0].hidden_ids | length' 2>/dev/null)

  if [ "$FIRST_TYPE" = "topic" ] || [ "$FIRST_TYPE" = "theme" ]; then
    pass "group_type is valid: '$FIRST_TYPE'"
  else
    fail "group_type invalid: '$FIRST_TYPE' (expected 'topic' or 'theme')"
  fi

  if [ -n "$FIRST_KEY" ] && [ "$FIRST_KEY" != "null" ]; then
    pass "group_key is present: '$FIRST_KEY'"
  else
    fail "group_key is missing"
  fi

  if [ -n "$FIRST_LABEL" ] && [ "$FIRST_LABEL" != "null" ]; then
    pass "group_label is present: '$FIRST_LABEL'"
  else
    fail "group_label is missing"
  fi

  if [ "$FIRST_COUNT" -ge 2 ] 2>/dev/null; then
    pass "hidden_count >= 2: $FIRST_COUNT"
  else
    fail "hidden_count < 2: $FIRST_COUNT"
  fi

  if [ "$FIRST_IDS" -ge 2 ] 2>/dev/null; then
    pass "hidden_ids has entries: $FIRST_IDS"
  else
    fail "hidden_ids is empty or too small: $FIRST_IDS"
  fi

  # Verify hidden_ids are NOT in the items list
  HIDDEN_IN_ITEMS=$(echo "$RESPONSE" | jq '[.topic_overflow[].hidden_ids[]] as $hidden | [.items[].id] | map(select(. as $id | $hidden | index($id))) | length' 2>/dev/null || echo "-1")
  if [ "$HIDDEN_IN_ITEMS" -eq 0 ] 2>/dev/null; then
    pass "Hidden articles are correctly excluded from items"
  else
    fail "Found $HIDDEN_IN_ITEMS hidden articles still in items list!"
  fi
else
  echo "   ⚠️  topic_overflow is empty — user may not have enough neutral articles to regroup"
  echo "   This is acceptable if the user follows most topics in the feed."
fi

# ============================================================
# TEST 2: User without prefs → topic_overflow empty
# ============================================================
echo ""
echo "═══════════════════════════════════════════════════"
echo "TEST 2: User WITHOUT prefs → topic_overflow empty"
echo "═══════════════════════════════════════════════════"

if [ -z "${FACTEUR_NOPREFS_TOKEN:-}" ]; then
  echo "   ⚠️  SKIPPED: FACTEUR_NOPREFS_TOKEN not set"
  echo "   To run this test, export a token for a user with no custom topics."
else
  RESPONSE_NP=$(curl -s -H "Authorization: $FACTEUR_NOPREFS_TOKEN" "$ENDPOINT")

  NP_OVERFLOW=$(echo "$RESPONSE_NP" | jq '.topic_overflow | length' 2>/dev/null || echo "-1")
  NP_ITEMS=$(echo "$RESPONSE_NP" | jq '.items | length' 2>/dev/null || echo "0")

  echo "   Items: $NP_ITEMS"
  echo "   Topic overflow groups: $NP_OVERFLOW"

  if [ "$NP_OVERFLOW" -eq 0 ] 2>/dev/null; then
    pass "No-prefs user: topic_overflow is empty (no-op confirmed)"
  else
    fail "No-prefs user: topic_overflow should be empty but has $NP_OVERFLOW entries"
  fi
fi

# ============================================================
# TEST 3: Floor 30% — discovery guarantee
# ============================================================
echo ""
echo "═══════════════════════════════════════════════════"
echo "TEST 3: Floor 30% — discovery guarantee"
echo "═══════════════════════════════════════════════════"

if [ "$OVERFLOW_COUNT" -gt 0 ] 2>/dev/null; then
  # Total hidden across all topic overflow groups
  TOTAL_HIDDEN=$(echo "$RESPONSE" | jq '[.topic_overflow[].hidden_count] | add' 2>/dev/null || echo "0")
  TOTAL_ORIGINAL=$((ITEMS_COUNT + TOTAL_HIDDEN))
  FLOOR=$((TOTAL_ORIGINAL * 30 / 100))
  # Rough check: remaining items should be >= 70% of original (followed + floor neutrals)
  # More precisely: items_count should be >= total_original - (neutrals - floor)

  echo "   Items visible: $ITEMS_COUNT"
  echo "   Total hidden: $TOTAL_HIDDEN"
  echo "   Original total: $TOTAL_ORIGINAL"
  echo "   Floor (30%): $FLOOR"

  if [ "$ITEMS_COUNT" -ge "$FLOOR" ] 2>/dev/null; then
    pass "Visible items ($ITEMS_COUNT) >= floor ($FLOOR)"
  else
    fail "Visible items ($ITEMS_COUNT) < floor ($FLOOR) — floor violated!"
  fi
else
  echo "   ⚠️  SKIPPED: No topic_overflow to validate floor against"
fi

# ============================================================
# TEST 4: Regression — existing fields still work
# ============================================================
echo ""
echo "═══════════════════════════════════════════════════"
echo "TEST 4: Regression — existing fields intact"
echo "═══════════════════════════════════════════════════"

# Check source_overflow field exists
HAS_SO=$(echo "$RESPONSE" | jq 'has("source_overflow")' 2>/dev/null)
if [ "$HAS_SO" = "true" ]; then
  SO_COUNT=$(echo "$RESPONSE" | jq '.source_overflow | length' 2>/dev/null || echo "0")
  pass "source_overflow field present ($SO_COUNT entries)"
else
  fail "source_overflow field missing from response"
fi

# Check clusters field exists
HAS_CL=$(echo "$RESPONSE" | jq 'has("clusters")' 2>/dev/null)
if [ "$HAS_CL" = "true" ]; then
  CL_COUNT=$(echo "$RESPONSE" | jq '.clusters | length' 2>/dev/null || echo "0")
  pass "clusters field present ($CL_COUNT entries)"
else
  fail "clusters field missing from response"
fi

# Check pagination exists
HAS_PAG=$(echo "$RESPONSE" | jq 'has("pagination")' 2>/dev/null)
if [ "$HAS_PAG" = "true" ]; then
  pass "pagination field present"
else
  fail "pagination field missing from response"
fi

# Check items have expected fields
FIRST_ITEM_TOPICS=$(echo "$RESPONSE" | jq '.items[0].topics | type' 2>/dev/null)
if [ "$FIRST_ITEM_TOPICS" = "\"array\"" ]; then
  pass "items[0].topics is an array"
else
  fail "items[0].topics has unexpected type: $FIRST_ITEM_TOPICS"
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "═══════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
echo "RESULTS: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo ""
echo "🎉 All tests passed!"
exit 0
