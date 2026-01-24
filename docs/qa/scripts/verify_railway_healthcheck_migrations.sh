#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "== Railway status =="
railway status

echo ""
echo "== Latest deployment logs (migrations) =="
DEPLOYMENT_ID="$(
  railway deployment list --limit 1 --json | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
print(data[0]["id"] if data else "")
PY
)"

if [ -z "$DEPLOYMENT_ID" ]; then
  echo "ERROR: Impossible de recuperer le dernier deployment."
  exit 1
fi

echo "Deployment ID: $DEPLOYMENT_ID"
if railway logs --deployment "$DEPLOYMENT_ID" | rg -n "Can't locate revision identified by|Pending migrations detected"; then
  echo "ERROR: Erreur de migrations detectee dans les logs."
  exit 1
fi

echo ""
echo "== Healthcheck =="
HTTP_STATUS="$(
  curl -s -o /tmp/facteur_health.json -w "%{http_code}" \
    https://facteur-production.up.railway.app/api/health
)"
echo "HTTP status: $HTTP_STATUS"
cat /tmp/facteur_health.json
echo ""

if [ "$HTTP_STATUS" != "200" ]; then
  echo "ERROR: Healthcheck non OK."
  exit 1
fi

echo "OK: Healthcheck 200 et pas d'erreur migrations dans les logs."
