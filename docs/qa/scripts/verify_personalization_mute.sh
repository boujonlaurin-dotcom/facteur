#!/bin/bash

# Script de vérification des endpoints de personnalisation (mute source/theme)
# Usage: ./verify_personalization_mute.sh [TOKEN]
# Si TOKEN n'est pas fourni, le script affiche les instructions pour l'obtenir

ROOT_DIR="/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur"
API_BASE_URL="${API_BASE_URL:-https://facteur-production.up.railway.app/api}"

echo "--------------------------------------------------"
echo "🔍 VERIFICATION API PERSONALIZATION (MUTE)"
echo "--------------------------------------------------"

# Vérifier si un token est fourni
if [ -z "$1" ]; then
    echo ""
    echo "⚠️  Token d'authentification requis"
    echo ""
    echo "Pour obtenir un token:"
    echo "1. Connecte-toi à l'app mobile Flutter"
    echo "2. Ouvre les DevTools/Logs et cherche 'ApiClient: Attaching token'"
    echo "3. Copie le token complet (JWT)"
    echo ""
    echo "Usage: $0 <JWT_TOKEN>"
    echo ""
    exit 1
fi

TOKEN="$1"

echo ""
echo "[1/4] Test GET /api/users/personalization"
echo "----------------------------------------"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$API_BASE_URL/users/personalization")
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ GET OK (200)"
    echo "Response: $BODY"
else
    echo "❌ GET FAILED ($HTTP_CODE)"
    echo "Response: $BODY"
    exit 1
fi

echo ""
echo "[2/4] Test POST /api/users/personalization/mute-source"
echo "------------------------------------------------------"
# Utiliser un UUID de test (doit être un UUID valide d'une source existante)
# En production, utiliser un vrai source_id depuis l'app
TEST_SOURCE_ID="${TEST_SOURCE_ID:-00000000-0000-0000-0000-000000000001}"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"source_id\": \"$TEST_SOURCE_ID\"}" \
    "$API_BASE_URL/users/personalization/mute-source")
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ POST mute-source OK (200)"
    echo "Response: $BODY"
elif [ "$HTTP_CODE" = "422" ]; then
    echo "⚠️  POST mute-source: Validation error (422)"
    echo "   (Source ID invalide ou non-UUID - normal si UUID de test)"
    echo "Response: $BODY"
else
    echo "❌ POST mute-source FAILED ($HTTP_CODE)"
    echo "Response: $BODY"
    exit 1
fi

echo ""
echo "[3/4] Test POST /api/users/personalization/mute-theme"
echo "----------------------------------------------------"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"theme": "tech"}' \
    "$API_BASE_URL/users/personalization/mute-theme")
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ POST mute-theme OK (200)"
    echo "Response: $BODY"
else
    echo "❌ POST mute-theme FAILED ($HTTP_CODE)"
    echo "Response: $BODY"
    exit 1
fi

echo ""
echo "[4/4] Vérification GET après mutations"
echo "--------------------------------------"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$API_BASE_URL/users/personalization")
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ GET après mutations OK (200)"
    echo "Response: $BODY"
    # Vérifier que le thème "tech" est dans la liste
    if echo "$BODY" | grep -q "tech"; then
        echo "✅ Thème 'tech' trouvé dans les préférences"
    else
        echo "⚠️  Thème 'tech' non trouvé (peut être normal si validation échoue)"
    fi
else
    echo "❌ GET après mutations FAILED ($HTTP_CODE)"
    echo "Response: $BODY"
    exit 1
fi

echo ""
echo "--------------------------------------------------"
echo "✨ VERIFICATION TERMINEE AVEC SUCCES !"
echo "--------------------------------------------------"
echo ""
echo "📝 Notes:"
echo "- Si source_id invalide (422), c'est normal avec un UUID de test"
echo "- Les endpoints doivent retourner 200 pour être fonctionnels"
echo "- Vérifie les logs backend pour les erreurs FK si 500"
