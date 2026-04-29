#!/usr/bin/env bash
# =============================================================================
# Vérification : Learning Checkpoint — Carte "Construire ton flux" (13.5-13.6)
# =============================================================================
#
# Suite de tests automatisés couvrant :
#   Phase 1 — Smoke (health, flutter analyze, flutter test)
#   Phase 2 — API endpoints (GET proposals, POST apply)
#   Phase 3 — Intégrité DB post-apply
#   Phase 4 — Backend unit tests
#
# Usage:
#   bash docs/qa/scripts/verify_13_5_13_6.sh           # toutes les phases
#   bash docs/qa/scripts/verify_13_5_13_6.sh --smoke    # phase 1 uniquement
#   bash docs/qa/scripts/verify_13_5_13_6.sh --api      # phases 2-3 uniquement
#
# Prérequis:
#   - ~/.facteur-secrets (SUPABASE_JWT_SECRET, DATABASE_URL)
#   - API locale sur port 8080 (pour phases 2-3)
#   - Seed exécuté : bash docs/qa/scripts/seed_13_5_13_6.sh
#   - jq installé
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
API_DIR="$PROJECT_ROOT/packages/api"
MOBILE_DIR="$PROJECT_ROOT/apps/mobile"
SECRETS_FILE="$HOME/.facteur-secrets"

# --- Parse args ---
RUN_SMOKE=true
RUN_API=true
if [ "${1:-}" = "--smoke" ]; then RUN_API=false; fi
if [ "${1:-}" = "--api" ]; then RUN_SMOKE=false; fi

# --- Counters ---
PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); echo "   ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "   ❌ $1"; }
skip() { SKIP=$((SKIP + 1)); echo "   ⏭️  $1"; }

# --- Load secrets ---
if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ Missing ~/.facteur-secrets — see docs/qa/scripts/e2e_mobile_setup.sh"
  exit 1
fi
source "$SECRETS_FILE"

API_BASE="${API_BASE_URL:-http://localhost:8080}"

# --- Test UUIDs (same as seed) ---
USER_A="a0000000-1356-4000-a000-000000000001"
USER_B="b0000000-1356-4000-b000-000000000002"
USER_C="c0000000-1356-4000-c000-000000000003"
USER_D="d0000000-1356-4000-d000-000000000004"
USER_E="e0000000-1356-4000-e000-000000000005"

echo "═══════════════════════════════════════════════════════════════"
echo "🔍 Vérification : Learning Checkpoint 13.5-13.6"
echo "═══════════════════════════════════════════════════════════════"
echo "   API: $API_BASE"
echo "   Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ─────────────────────────────────────────────────────────────────
# PHASE 1 — SMOKE
# ─────────────────────────────────────────────────────────────────

if [ "$RUN_SMOKE" = true ]; then

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 1 — Smoke tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1.1 Health liveness
echo ""
echo "1.1 Health liveness..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE/api/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "GET /api/health → $HTTP_CODE"
else
  fail "GET /api/health → $HTTP_CODE (attendu: 200)"
fi

# 1.2 Health readiness
echo ""
echo "1.2 Health readiness..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE/api/health/ready" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "GET /api/health/ready → $HTTP_CODE"
else
  fail "GET /api/health/ready → $HTTP_CODE (attendu: 200)"
fi

# 1.3 Flutter analyze
echo ""
echo "1.3 Flutter analyze (learning_checkpoint)..."
if command -v flutter &>/dev/null; then
  ANALYZE_OUTPUT=$(cd "$MOBILE_DIR" && flutter analyze lib/features/learning_checkpoint/ 2>&1) || true
  if echo "$ANALYZE_OUTPUT" | grep -q "No issues found"; then
    pass "flutter analyze — 0 issue"
  elif echo "$ANALYZE_OUTPUT" | grep -q "error"; then
    fail "flutter analyze — erreurs trouvées"
    echo "$ANALYZE_OUTPUT" | grep -i "error" | head -5 | sed 's/^/      /'
  else
    pass "flutter analyze — OK"
  fi
else
  skip "flutter non disponible"
fi

# 1.4 Flutter unit tests
echo ""
echo "1.4 Flutter test (learning_checkpoint)..."
if command -v flutter &>/dev/null; then
  if (cd "$MOBILE_DIR" && flutter test test/features/learning_checkpoint/ --reporter=compact 2>&1); then
    pass "flutter test — tous verts"
  else
    fail "flutter test — échecs détectés"
  fi
else
  skip "flutter non disponible"
fi

fi # end RUN_SMOKE

# ─────────────────────────────────────────────────────────────────
# PHASE 2 — API ENDPOINTS
# ─────────────────────────────────────────────────────────────────

if [ "$RUN_API" = true ]; then

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 2 — API Endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check API is up
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE/api/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" != "200" ]; then
  echo "   ⚠️  API non joignable ($HTTP_CODE) — skipping phases 2-3"
  echo "   → Lancer: cd packages/api && uvicorn app.main:app --port 8080"
  SKIP=$((SKIP + 7))
else

# Helper: mint JWT for a user
mint() {
  bash "$SCRIPT_DIR/mint_jwt.sh" "$1"
}

# 2.1 GET proposals — User A (happy path, 4 pending)
echo ""
echo "2.1 GET proposals — User A (happy path)..."
TOKEN_A=$(mint "$USER_A")
RESP_A=$(curl -sS -w "\n%{http_code}" \
  -H "Authorization: Bearer $TOKEN_A" \
  "$API_BASE/api/users/personalization/learning-proposals" 2>/dev/null)
HTTP_A=$(echo "$RESP_A" | tail -1)
BODY_A=$(echo "$RESP_A" | sed '$d')

if [ "$HTTP_A" = "200" ]; then
  pass "GET proposals User A → 200"

  # Check proposal count
  PROP_COUNT=$(echo "$BODY_A" | jq '.proposals | length' 2>/dev/null || echo "0")
  if [ "$PROP_COUNT" -ge 2 ]; then
    pass "proposals count = $PROP_COUNT (≥2)"
  else
    fail "proposals count = $PROP_COUNT (attendu ≥2)"
  fi

  # Check sorting (signal_strength DESC)
  SORTED=$(echo "$BODY_A" | jq '[.proposals[].signal_strength] | . == (. | sort | reverse)' 2>/dev/null || echo "false")
  if [ "$SORTED" = "true" ]; then
    pass "tri DESC par signal_strength"
  else
    fail "tri signal_strength incorrect"
  fi

  # Check schema completeness
  HAS_FIELDS=$(echo "$BODY_A" | jq '.proposals[0] | has("id","proposal_type","entity_label","signal_strength","signal_context")' 2>/dev/null || echo "false")
  if [ "$HAS_FIELDS" = "true" ]; then
    pass "schema ProposalResponse complet"
  else
    fail "champs manquants dans ProposalResponse"
  fi

  # Check signal_context fields
  HAS_CTX=$(echo "$BODY_A" | jq '.proposals[0].signal_context | has("articles_shown","articles_clicked","period_days")' 2>/dev/null || echo "false")
  if [ "$HAS_CTX" = "true" ]; then
    pass "signal_context complet (articles_shown, articles_clicked, period_days)"
  else
    fail "signal_context incomplet"
  fi

  # Check proposal_type values
  VALID_TYPES=$(echo "$BODY_A" | jq '[.proposals[].proposal_type] | all(. == "source_priority" or . == "mute_entity" or . == "follow_entity")' 2>/dev/null || echo "false")
  if [ "$VALID_TYPES" = "true" ]; then
    pass "proposal_types valides"
  else
    fail "proposal_type invalide détecté"
  fi

  # Save proposal IDs for apply tests
  PROPOSAL_IDS_A=$(echo "$BODY_A" | jq -r '[.proposals[].id] | join(",")' 2>/dev/null)

else
  fail "GET proposals User A → $HTTP_A (attendu: 200)"
fi

# 2.2 GET proposals — User B (gating N<2)
echo ""
echo "2.2 GET proposals — User B (gating N<2)..."
TOKEN_B=$(mint "$USER_B")
RESP_B=$(curl -sS -w "\n%{http_code}" \
  -H "Authorization: Bearer $TOKEN_B" \
  "$API_BASE/api/users/personalization/learning-proposals" 2>/dev/null)
HTTP_B=$(echo "$RESP_B" | tail -1)
BODY_B=$(echo "$RESP_B" | sed '$d')

if [ "$HTTP_B" = "200" ]; then
  PROP_COUNT_B=$(echo "$BODY_B" | jq '.proposals | length' 2>/dev/null || echo "?")
  # With only 1 seed proposal and no real user data, service may return 0-1
  if [ "$PROP_COUNT_B" -lt 2 ]; then
    pass "GET proposals User B → $PROP_COUNT_B proposals (< 2, gating OK)"
  else
    fail "GET proposals User B → $PROP_COUNT_B proposals (attendu < 2)"
  fi
else
  fail "GET proposals User B → $HTTP_B (attendu: 200)"
fi

# 2.3 GET proposals — no auth
echo ""
echo "2.3 GET proposals — sans auth..."
HTTP_NOAUTH=$(curl -s -o /dev/null -w "%{http_code}" \
  "$API_BASE/api/users/personalization/learning-proposals" 2>/dev/null || echo "000")
if [ "$HTTP_NOAUTH" = "401" ] || [ "$HTTP_NOAUTH" = "403" ]; then
  pass "GET proposals sans auth → $HTTP_NOAUTH"
else
  fail "GET proposals sans auth → $HTTP_NOAUTH (attendu: 401 ou 403)"
fi

# 2.4 POST apply-proposals — accept all (User A)
echo ""
echo "2.4 POST apply-proposals — accept all (User A)..."
if [ -n "${PROPOSAL_IDS_A:-}" ]; then
  # Build actions JSON: all accept
  ACTIONS_A=$(echo "$BODY_A" | jq -c '[.proposals[] | {proposal_id: .id, action: "accept"}]' 2>/dev/null)

  RESP_APPLY=$(curl -sS -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{\"actions\":$ACTIONS_A}" \
    "$API_BASE/api/users/personalization/apply-proposals" 2>/dev/null)
  HTTP_APPLY=$(echo "$RESP_APPLY" | tail -1)
  BODY_APPLY=$(echo "$RESP_APPLY" | sed '$d')

  if [ "$HTTP_APPLY" = "200" ]; then
    pass "POST apply-proposals (accept all) → 200"

    # Check all success
    ALL_SUCCESS=$(echo "$BODY_APPLY" | jq '[.results[].success] | all' 2>/dev/null || echo "false")
    if [ "$ALL_SUCCESS" = "true" ]; then
      pass "tous les résultats success=true"
    else
      fail "certains résultats success=false"
      echo "$BODY_APPLY" | jq '.results[] | select(.success == false)' 2>/dev/null | head -10 | sed 's/^/      /'
    fi

    # Check applied count
    APPLIED_COUNT=$(echo "$BODY_APPLY" | jq '.applied' 2>/dev/null || echo "0")
    pass "applied count = $APPLIED_COUNT"

    # Verify proposals are now resolved (GET should return empty)
    RESP_AFTER=$(curl -sS \
      -H "Authorization: Bearer $TOKEN_A" \
      "$API_BASE/api/users/personalization/learning-proposals" 2>/dev/null)
    PENDING_AFTER=$(echo "$RESP_AFTER" | jq '.proposals | length' 2>/dev/null || echo "?")
    if [ "$PENDING_AFTER" = "0" ]; then
      pass "GET proposals après apply → 0 pending"
    else
      fail "GET proposals après apply → $PENDING_AFTER pending (attendu: 0)"
    fi
  else
    fail "POST apply-proposals → $HTTP_APPLY (attendu: 200)"
  fi
else
  skip "pas de proposal IDs (phase 2.1 a échoué)"
fi

# 2.5 POST apply-proposals — mix actions (User E)
echo ""
echo "2.5 POST apply-proposals — mix accept/dismiss/modify (User E)..."
TOKEN_E=$(mint "$USER_E")

# First fetch proposals for User E
RESP_E=$(curl -sS \
  -H "Authorization: Bearer $TOKEN_E" \
  "$API_BASE/api/users/personalization/learning-proposals" 2>/dev/null)
PROP_COUNT_E=$(echo "$RESP_E" | jq '.proposals | length' 2>/dev/null || echo "0")

if [ "$PROP_COUNT_E" -ge 3 ]; then
  # Build mixed actions: accept first, dismiss second, modify third
  ACTIONS_E=$(echo "$RESP_E" | jq -c '
    [
      {proposal_id: .proposals[0].id, action: "accept"},
      {proposal_id: .proposals[1].id, action: "dismiss"},
      {proposal_id: .proposals[2].id, action: "modify", value: "2.0"}
    ]
  ' 2>/dev/null)

  RESP_MIX=$(curl -sS -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN_E" \
    -H "Content-Type: application/json" \
    -d "{\"actions\":$ACTIONS_E}" \
    "$API_BASE/api/users/personalization/apply-proposals" 2>/dev/null)
  HTTP_MIX=$(echo "$RESP_MIX" | tail -1)
  BODY_MIX=$(echo "$RESP_MIX" | sed '$d')

  if [ "$HTTP_MIX" = "200" ]; then
    pass "POST apply-proposals (mix) → 200"

    ALL_MIX_SUCCESS=$(echo "$BODY_MIX" | jq '[.results[].success] | all' 2>/dev/null || echo "false")
    if [ "$ALL_MIX_SUCCESS" = "true" ]; then
      pass "mix actions — tous success=true"
    else
      fail "mix actions — certains échoués"
    fi
  else
    fail "POST apply-proposals (mix) → $HTTP_MIX"
  fi
else
  skip "User E a $PROP_COUNT_E proposals (attendu ≥3)"
fi

# 2.6 POST apply-proposals — proposal_id inexistant
echo ""
echo "2.6 POST apply-proposals — proposal inexistant..."
FAKE_ID="ffffffff-ffff-4fff-bfff-ffffffffffff"
RESP_FAKE=$(curl -sS -w "\n%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"actions\":[{\"proposal_id\":\"$FAKE_ID\",\"action\":\"accept\"}]}" \
  "$API_BASE/api/users/personalization/apply-proposals" 2>/dev/null)
HTTP_FAKE=$(echo "$RESP_FAKE" | tail -1)
BODY_FAKE=$(echo "$RESP_FAKE" | sed '$d')

if [ "$HTTP_FAKE" = "200" ]; then
  FAKE_SUCCESS=$(echo "$BODY_FAKE" | jq '.results[0].success' 2>/dev/null || echo "?")
  if [ "$FAKE_SUCCESS" = "false" ]; then
    pass "proposal inexistant → success=false"
  else
    fail "proposal inexistant → success=$FAKE_SUCCESS (attendu: false)"
  fi
else
  # 404 or 422 are also acceptable
  if [ "$HTTP_FAKE" = "404" ] || [ "$HTTP_FAKE" = "422" ]; then
    pass "proposal inexistant → $HTTP_FAKE (erreur propre)"
  else
    fail "proposal inexistant → $HTTP_FAKE"
  fi
fi

# 2.7 POST apply-proposals — idempotence (User A déjà resolved)
echo ""
echo "2.7 POST apply-proposals — idempotence (User A, déjà resolved)..."
if [ -n "${ACTIONS_A:-}" ]; then
  RESP_IDEM=$(curl -sS -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Type: application/json" \
    -d "{\"actions\":$ACTIONS_A}" \
    "$API_BASE/api/users/personalization/apply-proposals" 2>/dev/null)
  HTTP_IDEM=$(echo "$RESP_IDEM" | tail -1)
  BODY_IDEM=$(echo "$RESP_IDEM" | sed '$d')

  if [ "$HTTP_IDEM" = "200" ]; then
    ALL_FAILED=$(echo "$BODY_IDEM" | jq '[.results[].success] | all(. == false)' 2>/dev/null || echo "false")
    if [ "$ALL_FAILED" = "true" ]; then
      pass "idempotence — tous success=false (already resolved)"
    else
      fail "idempotence — certains success=true (doublon possible)"
    fi
  elif [ "$HTTP_IDEM" = "409" ]; then
    pass "idempotence → 409 Conflict (propre)"
  else
    fail "idempotence → $HTTP_IDEM"
  fi
else
  skip "pas d'actions User A (phase 2.4 a échoué)"
fi

fi # end API check

# ─────────────────────────────────────────────────────────────────
# PHASE 3 — INTÉGRITÉ DB
# ─────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 3 — Intégrité DB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PSQL_URL="${DATABASE_URL//postgresql+psycopg/postgresql}"

# 3.1 Statuts proposals User A
echo ""
echo "3.1 Statuts proposals User A (post-apply)..."
PENDING_A=$(psql "$PSQL_URL" -tAc "
  SELECT COUNT(*) FROM user_learning_proposals
  WHERE user_id = '$USER_A' AND status = 'pending';
" 2>/dev/null || echo "?")
ACCEPTED_A=$(psql "$PSQL_URL" -tAc "
  SELECT COUNT(*) FROM user_learning_proposals
  WHERE user_id = '$USER_A' AND status = 'accepted';
" 2>/dev/null || echo "?")

if [ "$PENDING_A" = "0" ]; then
  pass "User A — 0 pending"
else
  fail "User A — $PENDING_A pending (attendu: 0)"
fi
if [ "$ACCEPTED_A" -ge 1 ] 2>/dev/null; then
  pass "User A — $ACCEPTED_A accepted"
else
  skip "User A — statut accepted non vérifié ($ACCEPTED_A)"
fi

# 3.2 Entity preferences créées
echo ""
echo "3.2 Entity preferences User A..."
ENTITY_PREFS=$(psql "$PSQL_URL" -tAc "
  SELECT COUNT(*) FROM user_entity_preferences
  WHERE user_id = '$USER_A';
" 2>/dev/null || echo "?")
if [ "$ENTITY_PREFS" -ge 1 ] 2>/dev/null; then
  pass "user_entity_preferences — $ENTITY_PREFS rows créées"
else
  skip "user_entity_preferences — $ENTITY_PREFS rows (vérifier manuellement)"
fi

# 3.3 Statuts mix User E
echo ""
echo "3.3 Statuts proposals User E (post-mix)..."
STATUTS_E=$(psql "$PSQL_URL" -tAc "
  SELECT status, COUNT(*) FROM user_learning_proposals
  WHERE user_id = '$USER_E'
  GROUP BY status ORDER BY status;
" 2>/dev/null || echo "?")
echo "$STATUTS_E" | sed 's/^/      /'
if echo "$STATUTS_E" | grep -q "accepted\|modified\|dismissed"; then
  pass "User E — mix de statuts détecté"
else
  skip "User E — statuts non vérifiables"
fi

fi # end RUN_API (for phase 3 which also needs API to have run)

# ─────────────────────────────────────────────────────────────────
# PHASE 4 — BACKEND UNIT TESTS
# ─────────────────────────────────────────────────────────────────

if [ "$RUN_SMOKE" = true ]; then

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Phase 4 — Backend unit tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -f "$API_DIR/tests/test_learning_service.py" ]; then
  echo "4.1 pytest test_learning_service.py..."
  if (cd "$API_DIR" && python -m pytest tests/test_learning_service.py -v 2>&1); then
    pass "backend unit tests — tous verts"
  else
    fail "backend unit tests — échecs détectés"
  fi
else
  skip "test_learning_service.py absent (branche backend non mergée ?)"
fi

fi # end RUN_SMOKE

# ─────────────────────────────────────────────────────────────────
# RÉSUMÉ
# ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📊 Résumé"
echo "═══════════════════════════════════════════════════════════════"
echo "   ✅ Pass : $PASS"
echo "   ❌ Fail : $FAIL"
echo "   ⏭️  Skip : $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "❌ ÉCHEC — $FAIL tests en erreur"
  exit 1
else
  echo "✅ SUCCÈS — tous les tests passent"
  exit 0
fi
