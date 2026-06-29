#!/bin/bash
# Vérification du système de feedback utilisateur (Epic 13, story 13.1).
# - Lance les tests unitaires du router feedback (segmentation, gating, snooze).
# - Vérifie qu'il reste exactement 1 head Alembic.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
API_DIR="$PROJECT_ROOT/packages/api"

cd "$API_DIR"

echo "=== 1. Tests unitaires feedback (segmentation + gating + snooze) ==="
pytest tests/test_feedback_router.py -v

echo ""
echo "=== 2. Un seul head Alembic ? ==="
HEADS=$(alembic heads 2>/dev/null | grep -c "(head)")
echo "Nombre de heads: $HEADS"
if [ "$HEADS" != "1" ]; then
  echo "❌ Attendu 1 head, trouvé $HEADS"
  exit 1
fi
echo "✅ 1 head"

echo ""
echo "=== 3. Endpoints exposés ? ==="
grep -q "feedback.router" app/main.py && echo "✅ router feedback enregistré" \
  || { echo "❌ router feedback non enregistré dans main.py"; exit 1; }

echo ""
echo "✅ Vérification feedback OK"
