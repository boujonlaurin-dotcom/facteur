#!/usr/bin/env bash
# verify_letters.sh — E2E QA for the « Lettres du Facteur » feature (Story 19.1).
#
# Stratégie : on n'a pas de moyen simple de fabriquer un JWT Supabase valide
# en local. On valide donc la chaîne :
#   1. Smoke : la route est enregistrée et exige un token (401 sans auth).
#   2. Logique : on lance la suite pytest dédiée — qui couvre :
#      - L1 : init, 4 détecteurs, chaînage, idempotence, cross-tenant, 404.
#      - L2 (PR4) : 5 détecteurs (digest_opened, bonnes_nouvelles_opened,
#        ≥3 long articles, vidéo/podcast 4min, like 🌻), shape JSON
#        (intro_palier + completion_voeu + completion_palier par action),
#        idempotence post-archivage.
#
# Usage:
#   ./docs/qa/scripts/verify_letters.sh [API_BASE_URL]
#   Default: http://localhost:8080/api
#
# DATABASE_URL doit pointer sur la DB de test (cf conftest.py). Sur poste
# local, par défaut :
#   export DATABASE_URL="postgresql+psycopg://laurinboujon@localhost:5432/facteur_test?sslmode=disable"

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
API="${1:-http://localhost:8080/api}"
PASS=0
FAIL=0

green() { printf "\033[32m✅ %s\033[0m\n" "$1"; PASS=$((PASS+1)); }
red()   { printf "\033[31m❌ %s\033[0m\n" "$1"; FAIL=$((FAIL+1)); }
info()  { printf "\033[34mℹ️  %s\033[0m\n" "$1"; }

echo "=== Lettres du Facteur — Verification ==="
echo "API: $API"
echo ""

# --- 1. Pytest suite (logique métier complète) ---
info "1. Running pytest suite tests/routers/test_letters_routes.py..."
pushd "$REPO_ROOT/packages/api" >/dev/null
if PYTHONPATH=. pytest tests/routers/test_letters_routes.py -v -x \
    --no-header 2>&1 | tail -20; then
  green "All letters tests passed"
else
  red "Pytest suite failed"
fi
popd >/dev/null
echo ""

# --- 2. Smoke route enregistrée (auth required) ---
info "2. GET /api/letters without auth → expect 401/403..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$API/letters" 2>/dev/null || true)
if [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
  green "GET /api/letters returns $HTTP (auth required, route is wired)"
elif [ -z "$HTTP" ] || [ "$HTTP" = "000" ]; then
  info "API not reachable at $API — skipping smoke (start with: uvicorn app.main:app --port 8080)"
else
  red "GET /api/letters returned unexpected $HTTP"
fi
echo ""

# --- 3. Smoke refresh-status route (L1) ---
info "3. POST /api/letters/letter_1/refresh-status without auth → expect 401/403..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/letters/letter_1/refresh-status" 2>/dev/null || true)
if [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
  green "POST /api/letters/.../refresh-status returns $HTTP"
elif [ -z "$HTTP" ] || [ "$HTTP" = "000" ]; then
  info "API not reachable — skipping smoke"
else
  red "POST refresh-status returned unexpected $HTTP"
fi
echo ""

# --- 4. Smoke refresh-status route (L2 — PR4) ---
info "4. POST /api/letters/letter_2/refresh-status without auth → expect 401/403..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/letters/letter_2/refresh-status" 2>/dev/null || true)
if [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
  green "POST /api/letters/letter_2/refresh-status returns $HTTP"
elif [ -z "$HTTP" ] || [ "$HTTP" = "000" ]; then
  info "API not reachable — skipping smoke"
else
  red "POST refresh-status (L2) returned unexpected $HTTP"
fi
echo ""

# --- Bilan ---
echo "=== Résultats : $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
