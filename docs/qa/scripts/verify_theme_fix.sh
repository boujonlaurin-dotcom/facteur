#!/bin/bash
# Script de vérification du fix Theme Matching
# Usage: ./docs/qa/scripts/verify_theme_fix.sh

set -e

echo "====================================="
echo "🔍 Vérification du Theme Matching Fix"
echo "====================================="
echo ""

# Déterminer le répertoire racine du projet
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../../.." && pwd )"
API_DIR="$PROJECT_ROOT/packages/api"

echo "📁 Répertoire API: $API_DIR"
echo ""

# Vérifier que le venv existe
if [ -d "$API_DIR/.venv" ]; then
    VENV_PATH="$API_DIR/.venv/bin/activate"
elif [ -d "$API_DIR/venv" ]; then
    VENV_PATH="$API_DIR/venv/bin/activate"
else
    echo "❌ Environnement virtuel non trouvé dans $API_DIR"
    exit 1
fi

echo "🐍 Activation du venv: $VENV_PATH"
source "$VENV_PATH"
echo ""

# Se déplacer dans le répertoire API
cd "$API_DIR"

echo "🧪 Étape 1: Tests unitaires CoreLayer"
echo "-------------------------------------"
python -m pytest tests/recommendation/test_core_layer.py -v --tb=short
if [ $? -eq 0 ]; then
    echo "✅ Tests unitaires passés"
else
    echo "❌ Tests unitaires échoués"
    exit 1
fi
echo ""

echo "📊 Étape 2: Vérification du code CoreLayer"
echo "------------------------------------------"
# Vérifier que la normalisation a été retirée
if grep -q "lower().strip()" app/services/recommendation/layers/core.py; then
    echo "⚠️  WARNING: Normalisation encore présente dans core.py"
else
    echo "✅ Normalisation retirée (comparaison directe)"
fi

# Vérifier le message de raison
if grep -q "Thème:" app/services/recommendation/layers/core.py; then
    echo "✅ Message de raison en français ('Thème:')"
else
    echo "❌ Message de raison incorrect"
    exit 1
fi
echo ""

echo "🗄️  Étape 3: Vérification de la migration"
echo "------------------------------------------"
if [ -f "alembic/versions/z1a2b3c4d5e6_fix_theme_taxonomy.py" ]; then
    echo "✅ Migration Alembic présente"
    
    # Vérifier le contenu
    if grep -q "Tech & Futur" alembic/versions/z1a2b3c4d5e6_fix_theme_taxonomy.py; then
        echo "✅ Mapping French labels → slugs présent"
    fi
else
    echo "⚠️  Migration non trouvée"
fi
echo ""

echo "📋 Étape 4: Vérification des données sources"
echo "--------------------------------------------"
CSV_FILE="$PROJECT_ROOT/sources/sources_master.csv"
if [ -f "$CSV_FILE" ]; then
    # Compter les thèmes
    echo "Thèmes trouvés dans sources_master.csv:"
    tail -n +2 "$CSV_FILE" | grep -v "^#" | grep -v "^$" | cut -d',' -f4 | sort | uniq -c | sort -rn | head -10
    echo ""
    
    # Vérifier qu'il n'y a pas de labels FR
    INVALID_LABELS=$(tail -n +2 "$CSV_FILE" | grep -v "^#" | grep -v "^$" | cut -d',' -f4 | grep -E "(Tech &|Société|Environnement|Économie|Politique|Culture|Science|International)" || true)
    if [ -z "$INVALID_LABELS" ]; then
        echo "✅ Aucun label français trouvé (données alignées)"
    else
        echo "⚠️  Labels français trouvés:"
        echo "$INVALID_LABELS"
    fi
else
    echo "❌ Fichier sources_master.csv non trouvé"
fi
echo ""

echo "====================================="
echo "✅ Vérification terminée avec succès!"
echo "====================================="
echo ""
echo "Prochaines étapes:"
echo "  1. Exécuter la migration: alembic upgrade z1a2b3c4d5e6"
echo "  2. Tester en local avec un vrai utilisateur"
echo "  3. Déployer sur staging"
