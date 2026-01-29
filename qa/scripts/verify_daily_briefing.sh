#!/bin/bash

# ==============================================================================
# Script de Vérification Automatisé - Daily Briefing (M6 & M7)
# Ce script gère l'activation de l'environnement et l'exécution des tests.
# ==============================================================================

# Configuration des Chemins Absolus
PROJECT_ROOT="/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur"
API_DIR="$PROJECT_ROOT/packages/api"
MOBILE_DIR="$PROJECT_ROOT/apps/mobile"

echo "------------------------------------------------------------"
echo "🚀 DÉBUT DE LA VÉRIFICATION - DAILY BRIEFING"
echo "------------------------------------------------------------"

# 1. Validation Backend (Data & API)
echo "📦 [1/2] Validation Backend..."
if [ -d "$API_DIR/venv" ]; then
    echo "💡 Activation du venv Python..."
    source "$API_DIR/venv/bin/activate"
    cd "$API_DIR"
    python scripts/verify_briefing_flow.py
    deactivate
else
    echo "⚠️  ERREUR : venv introuvable dans $API_DIR"
    exit 1
fi

echo ""

# 2. Validation Frontend (Logique & State Management)
echo "📱 [2/2] Validation Frontend (Flutter)..."
cd "$MOBILE_DIR"

if command -v flutter >/dev/null 2>&1; then
    echo "📦 Installation des dépendances Flutter..."
    flutter pub get
    flutter test test/features/feed/briefing_logic_test.dart
else
    echo "⚠️  ERREUR : Commande 'flutter' introuvable dans le PATH."
    exit 1
fi

echo "------------------------------------------------------------"
echo "🏁 FIN DES VÉRIFICATIONS"
echo "------------------------------------------------------------"
