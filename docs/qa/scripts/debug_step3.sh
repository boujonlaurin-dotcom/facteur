#!/bin/bash
# Script de debug pour identifier le problème étape 3

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
API_DIR="$PROJECT_ROOT/packages/api"

echo "=== DEBUG ÉTAPE 3 ==="
echo "API_DIR: $API_DIR"
echo "Current dir: $(pwd)"
echo ""

cd "$API_DIR"

# Test 1: Vérifier que le fichier existe
echo "Test 1: Existence des fichiers"
ls -la app/services/ml/classification_service.py || echo "❌ Fichier non trouvé"
ls -la app/workers/classification_worker.py || echo "❌ Fichier non trouvé"
ls -la app/routers/internal.py || echo "❌ Fichier non trouvé"
echo ""

# Test 2: Vérifier grep fonctionne
echo "Test 2: Grep fonctionne?"
echo "Recherche 'classify_async':"
grep -n "async def classify_async" app/services/ml/classification_service.py || echo "Pattern non trouvé"
echo ""

# Test 3: Vérifier les permissions
echo "Test 3: Permissions"
head -1 app/services/ml/classification_service.py
echo ""

# Test 4: Lancer les checks un par un avec set +e
echo "Test 4: Checks individuels (avec set +e)"
set +e

check_method() {
    local file=$1
    local pattern=$2
    local name=$3
    
    echo "Check: $name"
    echo "  File: $file"
    echo "  Pattern: $pattern"
    
    if [ ! -f "$file" ]; then
        echo "  ❌ Fichier inexistant"
        return 1
    fi
    
    result=$(grep "$pattern" "$file" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "  ✅ Trouvé"
        echo "  Match: $(echo "$result" | head -1)"
    else
        echo "  ❌ Non trouvé (exit code: $exit_code)"
        echo "  Error: $result"
    fi
    echo ""
}

check_method "app/services/ml/classification_service.py" "async def classify_async" "classify_async()"
check_method "app/services/ml/classification_service.py" "def get_stats" "get_stats()"
check_method "app/workers/classification_worker.py" "from app.services.ml import get_classification_service" "import ML"
check_method "app/routers/internal.py" "/admin/ml-status" "endpoint"

echo "=== FIN DEBUG ==="
