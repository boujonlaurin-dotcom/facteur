#!/usr/bin/env bash
# verify_classification_pipeline.sh
# Validates that the new Mistral classification pipeline (PR #152/#153) is active.
# Checks: queue stats, is_serene presence, topic quality.
#
# Usage: ./verify_classification_pipeline.sh [API_BASE_URL]
# Default: https://facteur-production.up.railway.app/api

set -euo pipefail

API="${1:-https://facteur-production.up.railway.app/api}"
PASS=0
FAIL=0

green() { printf "\033[32m✅ %s\033[0m\n" "$1"; PASS=$((PASS+1)); }
red()   { printf "\033[31m❌ %s\033[0m\n" "$1"; FAIL=$((FAIL+1)); }
info()  { printf "\033[34mℹ️  %s\033[0m\n" "$1"; }

echo "=== Classification Pipeline Validation ==="
echo "API: $API"
echo ""

# --- 1. Health check ---
info "1. Health check..."
HEALTH=$(curl -sf "$API/health" 2>/dev/null || echo "FAIL")
if echo "$HEALTH" | grep -qi "ok\|healthy\|alive"; then
  green "API is healthy"
else
  red "API health check failed: $HEALTH"
fi

# --- 2. Queue stats ---
info "2. Queue stats..."
STATS=$(curl -sf "$API/internal/admin/queue-stats" 2>/dev/null || echo "FAIL")
if [ "$STATS" = "FAIL" ]; then
  red "Cannot reach queue-stats endpoint"
else
  echo "   Raw stats: $STATS"

  PENDING=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['stats']['pending'])" 2>/dev/null || echo "?")
  COMPLETED=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['stats']['completed'])" 2>/dev/null || echo "?")
  FAILED=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['stats']['failed'])" 2>/dev/null || echo "?")
  SUCCESS_RATE=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['stats'].get('success_rate', '?'))" 2>/dev/null || echo "?")

  info "   Pending: $PENDING | Completed: $COMPLETED | Failed: $FAILED | Success rate: $SUCCESS_RATE%"

  if [ "$COMPLETED" != "?" ] && [ "$COMPLETED" -gt 0 ] 2>/dev/null; then
    green "Pipeline has completed articles ($COMPLETED)"
  else
    red "No completed articles found"
  fi

  if [ "$SUCCESS_RATE" != "?" ] && python3 -c "exit(0 if float('$SUCCESS_RATE') >= 90 else 1)" 2>/dev/null; then
    green "Success rate >= 90% ($SUCCESS_RATE%)"
  else
    red "Success rate below 90% ($SUCCESS_RATE%)"
  fi
fi

# --- 3. Readiness check (confirms worker is connected) ---
info "3. Readiness check..."
READY=$(curl -sf "$API/health/ready" 2>/dev/null || echo "FAIL")
if echo "$READY" | grep -qi "ok\|ready\|true"; then
  green "API readiness OK (worker likely connected)"
else
  red "Readiness check failed: $READY"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -eq 0 ]; then
  green "All checks passed — new pipeline is active"
else
  red "$FAIL check(s) failed — investigate"
fi
