#!/bin/bash
# Story 23.1 PR-3 — smoke E2E : veille comme 3ᵉ type de favori.
#
# Vérifie que :
#  1. POST /api/veille/config crée automatiquement un favori dans
#     user_favorite_interests.
#  2. GET /api/user/interests retourne ce favori avec kind=veille.
#  3. GET /api/users/top-themes le sérialise avec kind=veille + veille_config_id.
#  4. DELETE /api/veille/config retire le favori dans la même transaction.
#
# Pré-requis : `uvicorn app.main:app --port 8080` en cours, $JWT exporté
# (token Supabase Bearer pour un user existant en DB).
#
# Usage :
#   export JWT="..."
#   bash docs/qa/scripts/verify_veille_favorite.sh

set -euo pipefail

API="${API:-http://localhost:8080}"
JWT="${JWT:?JWT env var required (Supabase Bearer token)}"

if ! command -v jq &>/dev/null; then
  echo "❌ jq requis (brew install jq)"
  exit 1
fi

auth=(-H "Authorization: Bearer $JWT" -H "Content-Type: application/json")

# Source curated nécessaire pour le payload — on prend la première disponible.
SOURCE_ID=$(curl -s "${auth[@]}" "$API/api/sources/curated?theme=tech&limit=1" | jq -r '.[0].id // empty')
if [[ -z "$SOURCE_ID" ]]; then
  echo "❌ Aucune source curated tech disponible — la DB de test n'est pas seedée."
  exit 1
fi

echo "→ POST /api/veille/config (theme=tech, source=$SOURCE_ID)…"
cfg=$(curl -s "${auth[@]}" -X POST "$API/api/veille/config" -d "{
  \"theme_id\": \"tech\",
  \"theme_label\": \"Tech\",
  \"topics\": [],
  \"source_selections\": [{\"kind\":\"followed\",\"source_id\":\"$SOURCE_ID\"}],
  \"keywords\": [{\"keyword\":\"GPT-5\"}]
}")
CFG_ID=$(echo "$cfg" | jq -r '.id')
[[ -n "$CFG_ID" && "$CFG_ID" != "null" ]] || { echo "❌ POST échoue : $cfg"; exit 1; }
echo "✓ veille_config_id=$CFG_ID"

echo "→ GET /api/user/interests — vérifie kind=veille présent…"
interests=$(curl -s "${auth[@]}" "$API/api/user/interests")
veille_fav=$(echo "$interests" | jq --arg id "$CFG_ID" \
  '.favorites[] | select(.kind=="veille" and .target_id==$id)')
[[ -n "$veille_fav" ]] || {
  echo "❌ Favori veille absent de /api/user/interests"
  echo "$interests" | jq '.favorites'
  exit 1
}
echo "✓ favori veille présent"

echo "→ GET /api/users/top-themes — vérifie kind=veille + veille_config_id…"
top=$(curl -s "${auth[@]}" "$API/api/users/top-themes")
slot=$(echo "$top" | jq --arg id "$CFG_ID" \
  '.[] | select(.kind=="veille" and .veille_config_id==$id)')
[[ -n "$slot" ]] || {
  echo "❌ Slot veille absent de /api/users/top-themes"
  echo "$top"
  exit 1
}
echo "✓ slot veille présent dans la Tournée"

echo "→ DELETE /api/veille/config…"
status=$(curl -s -o /dev/null -w "%{http_code}" "${auth[@]}" -X DELETE "$API/api/veille/config")
[[ "$status" == "204" ]] || { echo "❌ DELETE status=$status"; exit 1; }
echo "✓ DELETE 204"

echo "→ GET /api/user/interests — vérifie que le favori a disparu…"
interests=$(curl -s "${auth[@]}" "$API/api/user/interests")
gone=$(echo "$interests" | jq --arg id "$CFG_ID" \
  '[.favorites[] | select(.kind=="veille" and .target_id==$id)] | length')
[[ "$gone" == "0" ]] || {
  echo "❌ Favori veille toujours présent après DELETE"
  echo "$interests" | jq '.favorites'
  exit 1
}
echo "✓ favori veille bien supprimé"

echo ""
echo "✅ verify_veille_favorite OK"
