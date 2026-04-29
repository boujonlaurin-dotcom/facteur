#!/usr/bin/env bash
# =============================================================================
# Seed : Données test pour Learning Checkpoint (Stories 13.5-13.6)
# =============================================================================
#
# Insère 5 profils test dans user_learning_proposals pour valider
# les différents scénarios E2E de la carte "Construire ton flux".
#
# Idempotent : supprime les données existantes avant insertion.
#
# Usage:
#   bash docs/qa/scripts/seed_13_5_13_6.sh
#
# Prérequis:
#   - ~/.facteur-secrets existe (DATABASE_URL)
#   - Table user_learning_proposals créée (migration ln01)
#   - psql installé
#
# Teardown:
#   bash docs/qa/scripts/teardown_13_5_13_6.sh
#
# =============================================================================

set -euo pipefail

SECRETS_FILE="$HOME/.facteur-secrets"

# --- Load secrets ---
if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ Missing ~/.facteur-secrets — see docs/qa/scripts/e2e_mobile_setup.sh"
  exit 1
fi
source "$SECRETS_FILE"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ DATABASE_URL not set in ~/.facteur-secrets"
  exit 1
fi

# Convert SQLAlchemy URL to psql-compatible URL
PSQL_URL="${DATABASE_URL//postgresql+psycopg/postgresql}"

# --- Test UUIDs (fixed, predictable) ---
USER_A="a0000000-1356-4000-a000-000000000001"  # Happy path (4 pending, high signal)
USER_B="b0000000-1356-4000-b000-000000000002"  # Gating N<2 (1 pending)
USER_C="c0000000-1356-4000-c000-000000000003"  # Gating signal<0.6 (4 pending, low signal)
USER_D="d0000000-1356-4000-d000-000000000004"  # Auto-expire shown≥3 (4 pending, shown_count=3)
USER_E="e0000000-1356-4000-e000-000000000005"  # Test apply actions (4 pending)

echo "═══════════════════════════════════════════════════════════════"
echo "🌱 Seed : Learning Checkpoint 13.5-13.6"
echo "═══════════════════════════════════════════════════════════════"

# --- Guard: check table exists ---
TABLE_EXISTS=$(psql "$PSQL_URL" -tAc "
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'user_learning_proposals'
  );
" 2>/dev/null || echo "false")

if [ "$TABLE_EXISTS" != "t" ]; then
  echo "❌ Table user_learning_proposals n'existe pas."
  echo "   → Appliquer la migration ln01_create_learning_tables via Supabase SQL Editor"
  echo "   → Ou checkout branche claude/learning-checkpoint-algo-UDwDy"
  exit 1
fi

echo "   Table user_learning_proposals trouvée ✅"

# --- Cleanup existing test data ---
echo "   Nettoyage données existantes..."
psql "$PSQL_URL" -q <<SQL
DELETE FROM user_entity_preferences
  WHERE user_id IN ('$USER_A','$USER_B','$USER_C','$USER_D','$USER_E');
DELETE FROM user_learning_proposals
  WHERE user_id IN ('$USER_A','$USER_B','$USER_C','$USER_D','$USER_E');
SQL

# --- Insert proposals ---
echo "   Insertion des propositions..."

psql "$PSQL_URL" -q <<SQL

-- ═══════════════════════════════════════════════════════════
-- User A : Happy path — 4 pending, mix 3 types, high signal
-- ═══════════════════════════════════════════════════════════
INSERT INTO user_learning_proposals
  (id, user_id, proposal_type, entity_type, entity_id, entity_label,
   current_value, proposed_value, signal_strength, signal_context,
   shown_count, status, computed_at, created_at, updated_at)
VALUES
  -- source_priority: Le Monde (reduce priority)
  ('aa000001-1356-4000-a000-000000000001', '$USER_A',
   'source_priority', 'source',
   '11111111-0000-0000-0000-000000000001', 'Le Monde',
   '1.0', '0.5', 0.87,
   '{"articles_shown": 18, "articles_clicked": 1, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW()),

  -- mute_entity: Emmanuel Macron
  ('aa000002-1356-4000-a000-000000000002', '$USER_A',
   'mute_entity', 'entity',
   'Emmanuel Macron', 'Emmanuel Macron',
   'not_muted', 'mute', 0.75,
   '{"articles_shown": 12, "articles_clicked": 0, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW()),

  -- follow_entity: Intelligence Artificielle
  ('aa000003-1356-4000-a000-000000000003', '$USER_A',
   'follow_entity', 'entity',
   'Intelligence Artificielle', 'Intelligence Artificielle',
   'not_followed', 'follow', 0.70,
   '{"articles_shown": 10, "articles_clicked": 7, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW()),

  -- source_priority: Libération (boost priority)
  ('aa000004-1356-4000-a000-000000000004', '$USER_A',
   'source_priority', 'source',
   '11111111-0000-0000-0000-000000000002', 'Libération',
   '1.0', '2.0', 0.65,
   '{"articles_shown": 8, "articles_clicked": 6, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW());

-- ═══════════════════════════════════════════════════════════
-- User B : Gating N<2 — seulement 1 proposal
-- ═══════════════════════════════════════════════════════════
INSERT INTO user_learning_proposals
  (id, user_id, proposal_type, entity_type, entity_id, entity_label,
   current_value, proposed_value, signal_strength, signal_context,
   shown_count, status, computed_at, created_at, updated_at)
VALUES
  ('bb000001-1356-4000-b000-000000000001', '$USER_B',
   'source_priority', 'source',
   '11111111-0000-0000-0000-000000000003', 'Le Figaro',
   '1.0', '0.5', 0.85,
   '{"articles_shown": 15, "articles_clicked": 1, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW());

-- ═══════════════════════════════════════════════════════════
-- User C : Gating signal<0.6 — 4 proposals mais signal max 0.55
-- ═══════════════════════════════════════════════════════════
INSERT INTO user_learning_proposals
  (id, user_id, proposal_type, entity_type, entity_id, entity_label,
   current_value, proposed_value, signal_strength, signal_context,
   shown_count, status, computed_at, created_at, updated_at)
VALUES
  ('cc000001-1356-4000-c000-000000000001', '$USER_C',
   'source_priority', 'source',
   '11111111-0000-0000-0000-000000000004', 'France Info',
   '1.0', '0.5', 0.55,
   '{"articles_shown": 6, "articles_clicked": 2, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW()),

  ('cc000002-1356-4000-c000-000000000002', '$USER_C',
   'mute_entity', 'entity',
   'Sport', 'Sport',
   'not_muted', 'mute', 0.50,
   '{"articles_shown": 8, "articles_clicked": 0, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW()),

  ('cc000003-1356-4000-c000-000000000003', '$USER_C',
   'follow_entity', 'entity',
   'Ecologie', 'Ecologie',
   'not_followed', 'follow', 0.45,
   '{"articles_shown": 5, "articles_clicked": 3, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW()),

  ('cc000004-1356-4000-c000-000000000004', '$USER_C',
   'source_priority', 'source',
   '11111111-0000-0000-0000-000000000005', 'Mediapart',
   '1.0', '2.0', 0.40,
   '{"articles_shown": 5, "articles_clicked": 3, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW());

-- ═══════════════════════════════════════════════════════════
-- User D : Auto-expire — 4 proposals avec shown_count=3 (≥ CHECKPOINT_DISMISS_AFTER)
-- ═══════════════════════════════════════════════════════════
INSERT INTO user_learning_proposals
  (id, user_id, proposal_type, entity_type, entity_id, entity_label,
   current_value, proposed_value, signal_strength, signal_context,
   shown_count, status, computed_at, created_at, updated_at)
VALUES
  ('dd000001-1356-4000-d000-000000000001', '$USER_D',
   'source_priority', 'source',
   '11111111-0000-0000-0000-000000000006', '20 Minutes',
   '1.0', '0.5', 0.80,
   '{"articles_shown": 14, "articles_clicked": 0, "period_days": 7}',
   3, 'pending', NOW(), NOW(), NOW()),

  ('dd000002-1356-4000-d000-000000000002', '$USER_D',
   'mute_entity', 'entity',
   'Faits divers', 'Faits divers',
   'not_muted', 'mute', 0.75,
   '{"articles_shown": 10, "articles_clicked": 0, "period_days": 7}',
   3, 'pending', NOW(), NOW(), NOW()),

  ('dd000003-1356-4000-d000-000000000003', '$USER_D',
   'follow_entity', 'entity',
   'Climat', 'Climat',
   'not_followed', 'follow', 0.70,
   '{"articles_shown": 9, "articles_clicked": 7, "period_days": 7}',
   3, 'pending', NOW(), NOW(), NOW()),

  ('dd000004-1356-4000-d000-000000000004', '$USER_D',
   'source_priority', 'source',
   '11111111-0000-0000-0000-000000000007', 'Courrier International',
   '0.5', '1.5', 0.65,
   '{"articles_shown": 7, "articles_clicked": 5, "period_days": 7}',
   3, 'pending', NOW(), NOW(), NOW());

-- ═══════════════════════════════════════════════════════════
-- User E : Test apply actions — 4 pending (pour mix accept/dismiss/modify)
-- ═══════════════════════════════════════════════════════════
INSERT INTO user_learning_proposals
  (id, user_id, proposal_type, entity_type, entity_id, entity_label,
   current_value, proposed_value, signal_strength, signal_context,
   shown_count, status, computed_at, created_at, updated_at)
VALUES
  -- accept this one
  ('ee000001-1356-4000-e000-000000000001', '$USER_E',
   'source_priority', 'source',
   '11111111-0000-0000-0000-000000000008', 'Les Echos',
   '1.0', '0.5', 0.75,
   '{"articles_shown": 12, "articles_clicked": 1, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW()),

  -- dismiss this one
  ('ee000002-1356-4000-e000-000000000002', '$USER_E',
   'mute_entity', 'entity',
   'Politique', 'Politique',
   'not_muted', 'mute', 0.70,
   '{"articles_shown": 9, "articles_clicked": 0, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW()),

  -- modify this one (value=2)
  ('ee000003-1356-4000-e000-000000000003', '$USER_E',
   'source_priority', 'source',
   '11111111-0000-0000-0000-000000000009', 'Le Parisien',
   '1.0', '0.5', 0.65,
   '{"articles_shown": 10, "articles_clicked": 2, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW()),

  -- accept this one
  ('ee000004-1356-4000-e000-000000000004', '$USER_E',
   'follow_entity', 'entity',
   'Technologie', 'Technologie',
   'not_followed', 'follow', 0.62,
   '{"articles_shown": 8, "articles_clicked": 6, "period_days": 7}',
   0, 'pending', NOW(), NOW(), NOW());

SQL

# --- Summary ---
TOTAL=$(psql "$PSQL_URL" -tAc "
  SELECT COUNT(*) FROM user_learning_proposals
  WHERE user_id IN ('$USER_A','$USER_B','$USER_C','$USER_D','$USER_E');
")

echo ""
echo "   Résumé :"
echo "   ├── User A (happy path)     : 4 proposals"
echo "   ├── User B (gating N<2)     : 1 proposal"
echo "   ├── User C (signal faible)  : 4 proposals"
echo "   ├── User D (auto-expire)    : 4 proposals"
echo "   └── User E (apply actions)  : 4 proposals"
echo "   Total en base : $TOTAL rows"
echo ""
echo "✅ Seed 13.5-13.6 terminé"
