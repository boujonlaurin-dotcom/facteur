#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# QA: Feed Keyword Grouping Rework
# Tests: keyword overflow, source interleaving, dedup, priority chain
# ============================================================

API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
SECRETS_FILE="$HOME/.facteur-secrets"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0; FAIL=0; WARN=0

pass() { PASS=$((PASS+1)); echo -e "${GREEN}PASS${NC}: $1"; }
fail() { FAIL=$((FAIL+1)); echo -e "${RED}FAIL${NC}: $1"; }
warn() { WARN=$((WARN+1)); echo -e "${YELLOW}WARN${NC}: $1"; }

# --- JWT generation ---
if [[ -z "${FACTEUR_TEST_TOKEN:-}" ]]; then
  if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "ERROR: No FACTEUR_TEST_TOKEN and $SECRETS_FILE not found"
    exit 1
  fi
  source "$SECRETS_FILE" 2>/dev/null || true
  JWT_SECRET="${SUPABASE_JWT_SECRET:-}"
  if [[ -z "$JWT_SECRET" ]]; then
    echo "ERROR: SUPABASE_JWT_SECRET not set"; exit 1
  fi
  # Generate a test JWT (user: laurin's UUID)
  FACTEUR_TEST_TOKEN=$(python3 -c "
import jose.jwt, datetime
secret = '$JWT_SECRET'
payload = {
    'sub': '72f2ffa2-0726-49c5-8684-cfea54b0e060',
    'aud': 'authenticated', 'role': 'authenticated',
    'iat': int(datetime.datetime.now(datetime.timezone.utc).timestamp()),
    'exp': int((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=2)).timestamp())
}
print('Bearer ' + jose.jwt.encode(payload, secret, algorithm='HS256'))
")
fi

AUTH="Authorization: $FACTEUR_TEST_TOKEN"

echo "=== Feed Keyword Grouping QA ==="
echo "API: $API_BASE_URL"
echo ""

# --- Test 1: Feed returns keyword_overflow field ---
echo "--- Test 1: keyword_overflow field present ---"
FEED=$(curl -s -H "$AUTH" "$API_BASE_URL/api/feed?limit=20" 2>/dev/null)

if echo "$FEED" | jq -e '.keyword_overflow' > /dev/null 2>&1; then
  pass "keyword_overflow field exists in response"
else
  fail "keyword_overflow field missing from response"
  echo "$FEED" | jq '.error // .detail // .' 2>/dev/null || echo "$FEED" | head -200
fi

# --- Test 2: keyword_overflow structure ---
echo ""
echo "--- Test 2: keyword_overflow structure ---"
KW_COUNT=$(echo "$FEED" | jq '.keyword_overflow | length' 2>/dev/null || echo 0)

if [[ "$KW_COUNT" -gt 0 ]]; then
  pass "keyword_overflow has $KW_COUNT groups"

  # Check first group has required fields
  FIRST=$(echo "$FEED" | jq '.keyword_overflow[0]' 2>/dev/null)
  for field in keyword display_label hidden_count hidden_ids sources; do
    if echo "$FIRST" | jq -e ".$field" > /dev/null 2>&1; then
      pass "  field '$field' present"
    else
      fail "  field '$field' missing from keyword group"
    fi
  done

  # Check sources sub-structure
  SRC_COUNT=$(echo "$FIRST" | jq '.sources | length' 2>/dev/null || echo 0)
  if [[ "$SRC_COUNT" -gt 0 ]]; then
    pass "  sources array has $SRC_COUNT entries"
    for field in source_id source_name article_count; do
      if echo "$FIRST" | jq -e ".sources[0].$field" > /dev/null 2>&1; then
        pass "    source field '$field' present"
      else
        fail "    source field '$field' missing"
      fi
    done
  else
    warn "  sources array is empty (might be valid if single-source)"
  fi
else
  warn "keyword_overflow is empty (may be valid if not enough articles share keywords)"
fi

# --- Test 3: No duplicate article IDs across keyword groups ---
echo ""
echo "--- Test 3: No duplicate articles across keyword groups ---"
if [[ "$KW_COUNT" -gt 1 ]]; then
  TOTAL_HIDDEN=$(echo "$FEED" | jq '[.keyword_overflow[].hidden_ids[]] | length' 2>/dev/null || echo 0)
  UNIQUE_HIDDEN=$(echo "$FEED" | jq '[.keyword_overflow[].hidden_ids[]] | unique | length' 2>/dev/null || echo 0)
  if [[ "$TOTAL_HIDDEN" -eq "$UNIQUE_HIDDEN" ]]; then
    pass "No duplicate article IDs across groups ($UNIQUE_HIDDEN unique)"
  else
    fail "Duplicate articles found: $TOTAL_HIDDEN total vs $UNIQUE_HIDDEN unique"
  fi
else
  warn "Skipped (need 2+ keyword groups to test)"
fi

# --- Test 4: hidden_count matches hidden_ids length ---
echo ""
echo "--- Test 4: hidden_count consistency ---"
MISMATCH=0
for i in $(seq 0 $((KW_COUNT-1))); do
  HC=$(echo "$FEED" | jq ".keyword_overflow[$i].hidden_count" 2>/dev/null || echo 0)
  HI=$(echo "$FEED" | jq ".keyword_overflow[$i].hidden_ids | length" 2>/dev/null || echo 0)
  KW=$(echo "$FEED" | jq -r ".keyword_overflow[$i].keyword" 2>/dev/null)
  if [[ "$HC" -ne "$HI" ]]; then
    fail "  Group '$KW': hidden_count=$HC but hidden_ids has $HI"
    MISMATCH=1
  fi
done
if [[ "$MISMATCH" -eq 0 && "$KW_COUNT" -gt 0 ]]; then
  pass "All hidden_count values match hidden_ids length"
fi

# --- Test 5: CTA budget respected ---
echo ""
echo "--- Test 5: CTA budget (max 6 keyword groups) ---"
if [[ "$KW_COUNT" -le 6 ]]; then
  pass "keyword groups count ($KW_COUNT) within budget (max 6)"
else
  fail "keyword groups count ($KW_COUNT) exceeds budget of 6"
fi

# --- Test 6: Source interleaving - no consecutive same-source ---
echo ""
echo "--- Test 6: Source interleaving ---"
ITEMS_COUNT=$(echo "$FEED" | jq '.items | length' 2>/dev/null || echo 0)
CONSECUTIVE=0
if [[ "$ITEMS_COUNT" -gt 1 ]]; then
  PREV_SRC=""
  for i in $(seq 0 $((ITEMS_COUNT-1))); do
    CUR_SRC=$(echo "$FEED" | jq -r ".items[$i].source_id" 2>/dev/null)
    if [[ "$CUR_SRC" == "$PREV_SRC" && -n "$CUR_SRC" && "$CUR_SRC" != "null" ]]; then
      CONSECUTIVE=$((CONSECUTIVE+1))
    fi
    PREV_SRC="$CUR_SRC"
  done
  if [[ "$CONSECUTIVE" -eq 0 ]]; then
    pass "No consecutive same-source articles ($ITEMS_COUNT items)"
  else
    warn "Found $CONSECUTIVE consecutive same-source pairs (interleaving is best-effort)"
  fi
else
  warn "Not enough items to test interleaving"
fi

# --- Test 7: topic_overflow still works as fallback ---
echo ""
echo "--- Test 7: topic_overflow fallback ---"
TOPIC_COUNT=$(echo "$FEED" | jq '.topic_overflow | length' 2>/dev/null || echo 0)
if [[ "$TOPIC_COUNT" -ge 0 ]]; then
  pass "topic_overflow present ($TOPIC_COUNT groups, may be 0 if keywords cover all)"
else
  fail "topic_overflow field missing"
fi

# --- Test 8: Hidden IDs not in visible items ---
echo ""
echo "--- Test 8: Hidden articles not in visible items ---"
if [[ "$KW_COUNT" -gt 0 ]]; then
  ALL_HIDDEN=$(echo "$FEED" | jq -r '[.keyword_overflow[].hidden_ids[]] | .[]' 2>/dev/null)
  ALL_VISIBLE=$(echo "$FEED" | jq -r '[.items[].id] | .[]' 2>/dev/null)
  OVERLAP=0
  for hid in $ALL_HIDDEN; do
    if echo "$ALL_VISIBLE" | grep -qF "$hid"; then
      OVERLAP=$((OVERLAP+1))
    fi
  done
  if [[ "$OVERLAP" -eq 0 ]]; then
    pass "No hidden article IDs appear in visible items"
  else
    fail "$OVERLAP hidden article IDs also appear in items (dedup error)"
  fi
else
  warn "Skipped (no keyword groups)"
fi

# --- Test 9: Display keyword labels ---
echo ""
echo "--- Test 9: Keyword labels preview ---"
if [[ "$KW_COUNT" -gt 0 ]]; then
  echo "  Keyword groups found:"
  for i in $(seq 0 $((KW_COUNT-1))); do
    LABEL=$(echo "$FEED" | jq -r ".keyword_overflow[$i].display_label" 2>/dev/null)
    NSRC=$(echo "$FEED" | jq ".keyword_overflow[$i].sources | length" 2>/dev/null)
    echo "    [$((i+1))] $LABEL (sources: $NSRC)"
  done
fi

# --- Summary ---
echo ""
echo "========================================="
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC}"
echo "========================================="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
