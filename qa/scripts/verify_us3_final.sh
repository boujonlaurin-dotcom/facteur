#!/bin/bash
# ============================================================
# US-3 Verification Script - Version Corrigée
# Usage: cd /path/to/Facteur && ./docs/qa/scripts/verify_us3_final.sh
# ============================================================

# Ne pas utiliser set -e pour éviter les arrêts silencieux
# set -e

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   US-3: mDeBERTa Worker Integration - Vérification      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Détection du répertoire projet
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
API_DIR="$PROJECT_ROOT/packages/api"

echo "📍 Projet: $PROJECT_ROOT"
echo "📁 API: $API_DIR"
echo ""

# Vérifier que le venv existe
if [ -d "$API_DIR/.venv" ]; then
    VENV_PATH="$API_DIR/.venv/bin/activate"
elif [ -d "$API_DIR/venv" ]; then
    VENV_PATH="$API_DIR/venv/bin/activate"
else
    echo "❌ ERREUR: Environnement virtuel non trouvé"
    exit 1
fi

echo "🐍 Venv: $VENV_PATH"
echo ""

# Activation
cd "$API_DIR"
source "$VENV_PATH"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 ÉTAPE 1: Configuration ML"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vérifier ML_ENABLED
if grep -q "^ML_ENABLED=true" .env; then
    echo "   ✅ ML_ENABLED=true"
else
    echo "   ❌ ML_ENABLED non trouvé ou pas à true"
    exit 1
fi

# Vérifier TRANSFORMERS_CACHE
if grep -q "^TRANSFORMERS_CACHE=" .env; then
    echo "   ✅ TRANSFORMERS_CACHE configuré"
else
    echo "   ⚠️ TRANSFORMERS_CACHE non configuré (optionnel)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 ÉTAPE 2: Tests d'Intégration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Lancer les tests et capturer le résultat
python -m pytest tests/ml/test_classification_integration.py -v --tb=short 2>&1 | tee /tmp/pytest_output.log
TEST_RESULT=${PIPESTATUS[0]}

echo ""
if [ $TEST_RESULT -eq 0 ]; then
    # Compter les tests passés
    PASSED=$(grep -c "PASSED" /tmp/pytest_output.log || echo "0")
    echo "   ✅ Tests passés: $PASSED"
else
    echo "   ❌ Échec des tests (code: $TEST_RESULT)"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 ÉTAPE 3: Vérification Code"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CHECKS_PASSED=0
CHECKS_TOTAL=8

# Fonction de vérification simplifiée
check_method() {
    local file="$1"
    local pattern="$2"
    local name="$3"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "   ✅ $name"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "   ❌ $name"
    fi
}

# Vérifications
check_method "app/services/ml/classification_service.py" "async def classify_async" "classify_async()"
check_method "app/services/ml/classification_service.py" "def get_stats" "get_stats()"
check_method "app/services/ml/classification_service.py" "elapsed_ms" "timing metrics"
check_method "app/workers/classification_worker.py" "from app.services.ml import get_classification_service" "import ML service"
check_method "app/workers/classification_worker.py" "source.granular_topics" "fallback mechanism"
check_method "app/workers/classification_worker.py" "self.metrics" "metrics tracking"
check_method "app/workers/classification_worker.py" "def get_metrics" "get_metrics()"
check_method "app/routers/internal.py" "/admin/ml-status" "endpoint /admin/ml-status"

echo ""
echo "   Résultat: $CHECKS_PASSED/$CHECKS_TOTAL vérifications OK"

if [ $CHECKS_PASSED -lt $CHECKS_TOTAL ]; then
    echo "   ❌ Certaines vérifications ont échoué"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 ÉTAPE 4: Cleanup & Story Alignment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vérifier suppression ancien code
if grep -q "_extract_topics_from_content" app/workers/classification_worker.py 2>/dev/null; then
    echo "   ❌ Ancienne méthode mock encore présente"
    exit 1
else
    echo "   ✅ Ancienne méthode mock supprimée"
fi

if grep -q "TODO.*ML classification" app/workers/classification_worker.py 2>/dev/null; then
    echo "   ❌ TODO commentaire encore présent"
    exit 1
else
    echo "   ✅ TODO commentaire supprimé"
fi

# Vérifier Story refs
STORY_COUNT=0
grep -q "Story 4.2-US-3" app/services/ml/classification_service.py && STORY_COUNT=$((STORY_COUNT + 1))
grep -q "Story 4.2-US-3" app/workers/classification_worker.py && STORY_COUNT=$((STORY_COUNT + 1))
grep -q "Story 4.2-US-3" app/config.py && STORY_COUNT=$((STORY_COUNT + 1))
echo "   ✅ Story refs: $STORY_COUNT fichiers"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 RÉSUMÉ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "   ✅ ML_ENABLED: true"
echo "   ✅ Tests: passés"
echo "   ✅ Code: $CHECKS_PASSED/$CHECKS_TOTAL vérifications"
echo "   ✅ Story refs: $STORY_COUNT fichiers"
echo "   ✅ Cleanup: OK"
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║            ✅ US-3 VALIDÉE AVEC SUCCÈS                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
