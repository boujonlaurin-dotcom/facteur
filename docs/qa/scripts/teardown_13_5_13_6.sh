#!/usr/bin/env bash
# =============================================================================
# Teardown : Nettoyage données test Learning Checkpoint (13.5-13.6)
# =============================================================================
#
# Supprime toutes les données insérées par seed_13_5_13_6.sh.
# Ne touche PAS les tables auth.users.
#
# Usage:
#   bash docs/qa/scripts/teardown_13_5_13_6.sh
#
# =============================================================================

set -euo pipefail

SECRETS_FILE="$HOME/.facteur-secrets"

# --- Load secrets ---
if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ Missing ~/.facteur-secrets"
  exit 1
fi
source "$SECRETS_FILE"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ DATABASE_URL not set in ~/.facteur-secrets"
  exit 1
fi

PSQL_URL="${DATABASE_URL//postgresql+psycopg/postgresql}"

# --- Test UUIDs (same as seed script) ---
USER_A="a0000000-1356-4000-a000-000000000001"
USER_B="b0000000-1356-4000-b000-000000000002"
USER_C="c0000000-1356-4000-c000-000000000003"
USER_D="d0000000-1356-4000-d000-000000000004"
USER_E="e0000000-1356-4000-e000-000000000005"

UUIDS="'$USER_A','$USER_B','$USER_C','$USER_D','$USER_E'"

echo "═══════════════════════════════════════════════════════════════"
echo "🧹 Teardown : Learning Checkpoint 13.5-13.6"
echo "═══════════════════════════════════════════════════════════════"

# --- Delete test data ---
DELETED_PREFS=$(psql "$PSQL_URL" -tAc "
  DELETE FROM user_entity_preferences WHERE user_id IN ($UUIDS);
  SELECT changes();
" 2>/dev/null || echo "0")

DELETED_PROPOSALS=$(psql "$PSQL_URL" -tAc "
  DELETE FROM user_learning_proposals WHERE user_id IN ($UUIDS);
  SELECT changes();
" 2>/dev/null || echo "0")

# Verify
REMAINING=$(psql "$PSQL_URL" -tAc "
  SELECT COUNT(*) FROM user_learning_proposals WHERE user_id IN ($UUIDS);
" 2>/dev/null || echo "?")

echo "   Proposals supprimées : $REMAINING restantes"
echo ""
echo "✅ Teardown 13.5-13.6 terminé"
