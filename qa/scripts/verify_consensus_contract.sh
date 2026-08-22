#!/bin/bash
# Vérification live du contrat `consensus` + `display` sur un vrai serveur HTTP.
#
# Story : docs/stories/core/35.2.reader-analyse-des-angles-exposition-reader.md
# Contrat : pour GET /contents/{id}/perspectives,
#   - plafonds servis ≤ 3 accords / ≤ 2 désaccords / CTA ≤ 1+1 ;
#   - display_domains ⊆ corpus servi, plus_count == max(0, support-2) ;
#   - états available/pending/unavailable, qualificatif absent hors available ;
#   - gates `display` dérivées du même coverage_count que la réponse.
#
# Prérequis :
#   - Postgres local avec la base `facteur_test` migrée (`alembic upgrade head`)
#   - QA_EMAIL / QA_PASSWORD : compte de test Supabase (hors dépôt, cf. mémoire
#     agent `reference_qa_staging_account`)
#
# Usage : QA_EMAIL=… QA_PASSWORD=… bash docs/qa/scripts/verify_consensus_contract.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
API_DIR="$PROJECT_ROOT/packages/api"
PY="$API_DIR/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

: "${DATABASE_URL:=postgresql+psycopg://$(whoami)@localhost:5432/facteur_test}"
: "${SUPABASE_URL:=https://ykuadtelnzavrqzbfdve.supabase.co}"
: "${API_PORT:=8080}"
: "${API_BASE_URL:=http://127.0.0.1:${API_PORT}/api}"
# `SUPABASE_URL` alimente aussi `settings.supabase_url` : sans lui, l'API locale
# construit une URL JWKS relative et répond 501 sur tout endpoint authentifié.
export DATABASE_URL API_BASE_URL SUPABASE_URL

echo "1/5 · Jeton Supabase pour le compte de test"
QA_ACCESS_TOKEN="$(curl -s -X POST \
  "${SUPABASE_URL}/auth/v1/token?grant_type=password" \
  -H "apikey: ${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY manquant}" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${QA_EMAIL:?}\",\"password\":\"${QA_PASSWORD:?}\"}" \
  | "$PY" -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))')"
[ -n "$QA_ACCESS_TOKEN" ] || { echo "   ❌ login Supabase échoué"; exit 1; }
export QA_ACCESS_TOKEN
QA_USER_ID="$("$PY" - <<'EOF'
import base64, json, os
payload = os.environ["QA_ACCESS_TOKEN"].split(".")[1]
payload += "=" * (-len(payload) % 4)
print(json.loads(base64.urlsafe_b64decode(payload))["sub"])
EOF
)"
export QA_ACCESS_TOKEN QA_USER_ID
echo "   ✅ user_id=${QA_USER_ID}"

echo "2/5 · Jeu d'essai : sujet nominal (analyse), sujet sans analyse, sujet solo"
"$PY" "$SCRIPT_DIR/verify_consensus_contract.py" seed

cleanup() {
  [ -n "${UVICORN_PID:-}" ] && kill "$UVICORN_PID" 2>/dev/null || true
  "$PY" "$SCRIPT_DIR/verify_consensus_contract.py" cleanup || true
}
trap cleanup EXIT

echo "3/5 · Démarrage de l'API locale sur :${API_PORT}"
(cd "$API_DIR" && "$PY" -m uvicorn app.main:app --port "$API_PORT" --log-level warning) &
UVICORN_PID=$!
for _ in $(seq 1 40); do
  curl -sf "http://127.0.0.1:${API_PORT}/api/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "http://127.0.0.1:${API_PORT}/api/health" >/dev/null || { echo "   ❌ API non démarrée"; exit 1; }
echo "   ✅ API up"

echo "4/5 · Contrat consensus/display sur les 3 sujets (x2, cache compris)"
"$PY" "$SCRIPT_DIR/verify_consensus_contract.py" verify

echo "5/5 · Nettoyage"
