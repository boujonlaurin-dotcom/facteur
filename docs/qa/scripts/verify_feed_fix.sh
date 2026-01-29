#!/bin/bash
# Script de vérification pour le bug UnboundLocalError sur le feed
# Protocole BMAD

# Configuration
REPO_ROOT="/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur"
API_DIR="$REPO_ROOT/packages/api"

echo "🔍 Démarrage de la vérification du bug Feed..."

cd "$API_DIR" || exit 1

# 1. Vérification par script de reproduction (TestClient)
echo "--- ÉTAPE 1: Script de reproduction ---"
PYTHONPATH=. venv/bin/python debug_feed_json.py

if [ $? -eq 0 ]; then
    echo "✅ Le script de reproduction a réussi (Status 200)."
else
    echo "❌ ÉCHEC : Le script de reproduction a échoué."
    exit 1
fi

# 2. Vérification par tests unitaires existants
echo "--- ÉTAPE 2: Tests unitaires de scoring ---"
PYTHONPATH=. venv/bin/pytest tests/test_scoring_v2.py

if [ $? -eq 0 ]; then
    echo "✅ Les tests unitaires sont au vert."
else
    echo "❌ ÉCHEC : Régression détectée dans les tests unitaires."
    exit 1
fi

echo "✨ Vérification terminée avec succès !"
