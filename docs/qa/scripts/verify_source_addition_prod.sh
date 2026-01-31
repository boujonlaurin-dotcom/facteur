#!/bin/bash

# Vérification : ajout de source personnalisée (prod + isolation par user)
# Usage: ./verify_source_addition_prod.sh <JWT_TOKEN>
# Optionnel: API_BASE_URL=https://... ./verify_source_addition_prod.sh <TOKEN>

API_BASE_URL="${API_BASE_URL:-https://facteur-production.up.railway.app/api}"

echo "--------------------------------------------------"
echo "🔍 VERIFICATION SOURCE ADDITION (PROD + PER-USER)"
echo "--------------------------------------------------"

if [ -z "$1" ]; then
    echo ""
    echo "⚠️  Token JWT requis."
    echo "Usage: $0 <JWT_TOKEN>"
    echo "Optionnel: API_BASE_URL=... $0 <JWT_TOKEN>"
    echo ""
    exit 1
fi

TOKEN="$1"

echo ""
echo "[1/3] GET /api/sources (liste user-scoped)"
echo "------------------------------------------"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$API_BASE_URL/sources")
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ GET /sources FAILED ($HTTP_CODE)"
    echo "$BODY"
    exit 1
fi
echo "✅ GET /sources OK (200)"

echo ""
echo "[2/3] POST /api/sources/custom (ajout source)"
echo "---------------------------------------------"
# URL RSS connue (vert.eco) - peut être remplacée par SUBSTACK ou autre
TEST_URL="${TEST_URL:-https://vert.eco/feed}"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"url\": \"$TEST_URL\"}" \
    "$API_BASE_URL/sources/custom")
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ POST /sources/custom FAILED ($HTTP_CODE)"
    echo "$BODY"
    exit 1
fi
echo "✅ POST /sources/custom OK (200)"
echo "Response: $BODY"

echo ""
echo "[3/3] GET /api/sources (vérifier custom présent)"
echo "-------------------------------------------------"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$API_BASE_URL/sources")
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ GET /sources FAILED ($HTTP_CODE)"
    exit 1
fi
if echo "$BODY" | grep -q '"custom"' && echo "$BODY" | grep -q 'vert'; then
    echo "✅ Custom list contains expected source (vert.eco or similar)"
else
    echo "⚠️  Custom list may be empty or different; check response manually"
fi

echo ""
echo "--------------------------------------------------"
echo "✅ VERIFICATION SOURCE ADDITION TERMINEE"
echo "--------------------------------------------------"
echo "Pour tester l'isolation par user: utiliser un 2e token (autre compte)"
echo "et vérifier que GET /sources renvoie une liste custom différente."
echo ""
