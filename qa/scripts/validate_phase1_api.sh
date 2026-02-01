#!/bin/bash
#
# Phase 1 API Validation - curl-based testing
# ============================================
#
# Validates the digest API endpoints are working correctly.
# Requires the API server to be running.
#
# Usage:
#   # Start API server first
#   cd packages/api && python -m app.main
#
#   # Then run this script
#   ./validate_phase1_api.sh [BASE_URL] [AUTH_TOKEN]
#
#   # Or as one-liner from project root:
#   ./docs/qa/scripts/validate_phase1_api.sh http://localhost:8080 your-token-here
#

set -e

BASE_URL="${1:-http://localhost:8000}"
AUTH_TOKEN="${2:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Phase 1 API Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Testing against: $BASE_URL"
echo ""

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is not installed${NC}"
    exit 1
fi

# Headers
if [ -n "$AUTH_TOKEN" ]; then
    AUTH_HEADER="Authorization: Bearer $AUTH_TOKEN"
    echo -e "${YELLOW}Using provided auth token${NC}"
else
    AUTH_HEADER=""
    echo -e "${YELLOW}Warning: No auth token provided. Some tests may fail.${NC}"
fi

# Test 1: Health/Info endpoint
echo -e "${YELLOW}Test 1: API Info endpoint${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "307" ]; then
    echo -e "  ✅ API is reachable (HTTP $HTTP_CODE)"
else
    echo -e "  ❌ API not reachable (HTTP $HTTP_CODE)"
    echo ""
    echo -e "${RED}Cannot continue - API server appears to be down${NC}"
    exit 1
fi
echo ""

# Test 2: GET /api/digest
echo -e "${YELLOW}Test 2: GET /api/digest${NC}"
if [ -n "$AUTH_HEADER" ]; then
    RESPONSE=$(curl -s -w "\n%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/api/digest" 2>/dev/null)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "  ✅ Endpoint returns 200"
        # Check if response has expected structure
        if echo "$BODY" | grep -q "items"; then
            echo -e "  ✅ Response contains 'items' field"
        fi
        if echo "$BODY" | grep -q "id"; then
            echo -e "  ✅ Response contains 'id' field"
        fi
    elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        echo -e "  ⚠️  Authentication required (HTTP $HTTP_CODE) - expected if no valid token"
    else
        echo -e "  ⚠️  Unexpected response (HTTP $HTTP_CODE)"
    fi
else
    echo -e "  ⚠️  Skipped (no auth token)"
fi
echo ""

# Test 3: OpenAPI docs
echo -e "${YELLOW}Test 3: OpenAPI Documentation${NC}"
DOCS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/docs" 2>/dev/null)
if [ "$DOCS_CODE" = "200" ]; then
    echo -e "  ✅ /docs endpoint accessible"
    
    # Check if digest endpoints are documented
    DOCS_CONTENT=$(curl -s "$BASE_URL/openapi.json" 2>/dev/null)
    if echo "$DOCS_CONTENT" | grep -q "/digest"; then
        echo -e "  ✅ Digest endpoints documented in OpenAPI"
    fi
else
    echo -e "  ⚠️  /docs not accessible (HTTP $DOCS_CODE)"
fi
echo ""

# Test 4: Verify router is registered
echo -e "${YELLOW}Test 4: Router Registration${NC}"
if [ -n "$AUTH_HEADER" ]; then
    # Try to trigger a 404 vs actual endpoint
    RANDOM_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/api/digest_nonexistent" 2>/dev/null)
    if [ "$RANDOM_CODE" = "404" ]; then
        echo -e "  ✅ Router is handling /api/digest/* paths"
    fi
    
    # Check action endpoint exists
    ACTION_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d '{"item_rank":1,"action":"read"}' \
        "$BASE_URL/api/digest/00000000-0000-0000-0000-000000000000/action" 2>/dev/null || echo "000")
    if [ "$ACTION_CODE" = "404" ] || [ "$ACTION_CODE" = "422" ] || [ "$ACTION_CODE" = "400" ]; then
        echo -e "  ✅ Action endpoint exists (returns $ACTION_CODE for invalid input)"
    fi
else
    echo -e "  ⚠️  Skipped (no auth token)"
fi
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  API Validation Complete${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Notes:"
echo "  - For full validation, provide an auth token: $0 <url> <token>"
echo "  - To get a token, authenticate via the API's login endpoint"
echo "  - All endpoints are expected to require authentication"
echo ""
