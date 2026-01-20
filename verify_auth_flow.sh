#!/bin/bash

# Configuration des chemins automatiques
ROOT_DIR="/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur"
API_DIR="$ROOT_DIR/packages/api"
MOBILE_DIR="$ROOT_DIR/apps/mobile"

echo "--------------------------------------------------"
echo "🚀 VERIFICATION GLOBALE DU FLUX D'AUTH (FACTEUR)"
echo "--------------------------------------------------"

# 1. Verification Backend
echo -e "\n[1/2] Test d'intégration Backend (API)..."
cd "$API_DIR"
source venv/bin/activate
PYTHONPATH=. python3 scripts/verify_auth.py
if [ $? -eq 0 ]; then
    echo "✅ Backend: OK"
else
    echo "❌ Backend: ECHEC"
    exit 1
fi

# 2. Verification Mobile
echo -e "\n[2/2] Test de logique Router (Mobile)..."
cd "$MOBILE_DIR"
dart scripts/verify_router_logic.dart
if [ $? -eq 0 ]; then
    echo "✅ Mobile: OK"
else
    echo "❌ Mobile: ECHEC"
    exit 1
fi

echo -e "\n--------------------------------------------------"
echo "✨ TOUS LES TESTS SONT PASSÉS AVEC SUCCÈS !"
echo "--------------------------------------------------"
