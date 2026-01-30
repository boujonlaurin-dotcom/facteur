#!/bin/bash
# Script de vérification US-3: Intégration mDeBERTa dans le Worker
# Story 4.2-US-3: ML Classification with Fallback
# Usage: ./docs/qa/scripts/verify_us3_mdeberta.sh

set -e

echo "================================================="
echo "🔍 Vérification US-3: mDeBERTa Worker Integration"
echo "================================================="
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

echo "🔧 Étape 1: Vérification ML_ENABLED"
echo "--------------------------------------"
if grep -q "ML_ENABLED=true" .env; then
    echo "✅ ML_ENABLED=true présent dans .env"
else
    echo "❌ ML_ENABLED non trouvé ou désactivé dans .env"
    exit 1
fi

if grep -q "TRANSFORMERS_CACHE" .env; then
    echo "✅ TRANSFORMERS_CACHE configuré"
else
    echo "⚠️  TRANSFORMERS_CACHE non configuré (optionnel)"
fi
echo ""

echo "🧪 Étape 2: Tests d'intégration ML"
echo "-----------------------------------"
python -m pytest tests/ml/test_classification_integration.py -v --tb=short
if [ $? -eq 0 ]; then
    echo "✅ Tests d'intégration ML passés"
else
    echo "❌ Tests d'intégration ML échoués"
    exit 1
fi
echo ""

echo "🔍 Étape 3: Vérification ClassificationService"
echo "-----------------------------------------------"
# Vérifier que classify_async existe
if grep -q "async def classify_async" app/services/ml/classification_service.py; then
    echo "✅ Méthode classify_async() présente"
else
    echo "❌ classify_async() non trouvée"
    exit 1
fi

# Vérifier que get_stats existe
if grep -q "def get_stats" app/services/ml/classification_service.py; then
    echo "✅ Méthode get_stats() présente"
else
    echo "❌ get_stats() non trouvée"
    exit 1
fi

# Vérifier le timing
if grep -q "elapsed_ms" app/services/ml/classification_service.py; then
    echo "✅ Timing metrics (elapsed_ms) présent"
else
    echo "❌ Timing metrics manquant"
    exit 1
fi

# Vérifier le threshold par défaut
if grep -q "threshold: float = 0.3" app/services/ml/classification_service.py; then
    echo "✅ Threshold par défaut à 0.3"
else
    echo "⚠️  Threshold par défaut différent de 0.3"
fi
echo ""

echo "🤖 Étape 4: Vérification ClassificationWorker"
echo "----------------------------------------------"
# Vérifier l'import du service ML
if grep -q "from app.services.ml import get_classification_service" app/workers/classification_worker.py; then
    echo "✅ Import de get_classification_service présent"
else
    echo "❌ Import ML manquant"
    exit 1
fi

# Vérifier le fallback
if grep -q "source.granular_topics" app/workers/classification_worker.py; then
    echo "✅ Fallback vers source.granular_topics présent"
else
    echo "❌ Fallback manquant"
    exit 1
fi

# Vérifier les métriques
if grep -q "self.metrics" app/workers/classification_worker.py; then
    echo "✅ Metrics tracking présent"
else
    echo "❌ Metrics tracking manquant"
    exit 1
fi

# Vérifier _update_metrics
if grep -q "_update_metrics" app/workers/classification_worker.py; then
    echo "✅ Méthode _update_metrics() présente"
else
    echo "❌ _update_metrics() manquante"
    exit 1
fi

# Vérifier get_metrics
if grep -q "def get_metrics" app/workers/classification_worker.py; then
    echo "✅ Méthode get_metrics() présente"
else
    echo "❌ get_metrics() manquante"
    exit 1
fi

# Vérifier le logging amélioré
if grep -q "worker.item_processed" app/workers/classification_worker.py; then
    echo "✅ Logging worker.item_processed présent"
else
    echo "❌ Logging insuffisant"
    exit 1
fi

if grep -q "worker.using_fallback" app/workers/classification_worker.py; then
    echo "✅ Logging fallback présent"
else
    echo "⚠️  Logging fallback manquant"
fi
echo ""

echo "🌐 Étape 5: Vérification Endpoints Admin"
echo "-----------------------------------------"
# Vérifier /admin/ml-status
if grep -q "/admin/ml-status" app/routers/internal.py; then
    echo "✅ Endpoint /admin/ml-status présent"
else
    echo "❌ Endpoint /admin/ml-status manquant"
    exit 1
fi

# Vérifier /admin/classification-metrics
if grep -q "/admin/classification-metrics" app/routers/internal.py; then
    echo "✅ Endpoint /admin/classification-metrics présent"
else
    echo "❌ Endpoint /admin/classification-metrics manquant"
    exit 1
fi

# Vérifier la structure de retour
if grep -q "ml_enabled" app/routers/internal.py; then
    echo "✅ Champ ml_enabled dans réponse"
else
    echo "❌ Champ ml_enabled manquant"
    exit 1
fi

if grep -q "model_loaded" app/routers/internal.py; then
    echo "✅ Champ model_loaded dans réponse"
else
    echo "❌ Champ model_loaded manquant"
    exit 1
fi
echo ""

echo "📦 Étape 6: Vérification Exports"
echo "---------------------------------"
# Vérifier que get_classification_service est exporté
if grep -q "get_classification_service" app/services/ml/__init__.py; then
    echo "✅ get_classification_service exporté dans __init__.py"
else
    echo "❌ get_classification_service non exporté"
    exit 1
fi
echo ""

echo "🎯 Étape 7: Vérification Story Alignment"
echo "------------------------------------------"
# Vérifier le commentaire de story dans classification_service.py
if grep -q "Story 4.2-US-3" app/services/ml/classification_service.py; then
    echo "✅ Commentaire Story 4.2-US-3 dans classification_service.py"
else
    echo "⚠️  Commentaire Story manquant dans classification_service.py"
fi

# Vérifier le commentaire dans classification_worker.py
if grep -q "Story 4.2-US-3" app/workers/classification_worker.py; then
    echo "✅ Commentaire Story 4.2-US-3 dans classification_worker.py"
else
    echo "⚠️  Commentaire Story manquant dans classification_worker.py"
fi
echo ""

echo "🧹 Étape 8: Vérification Code Quality"
echo "--------------------------------------"
# Vérifier qu'il n'y a pas de TODO restants
if grep -q "TODO.*ML classification" app/workers/classification_worker.py; then
    echo "❌ TODO ML classification encore présent (doit être supprimé)"
    exit 1
else
    echo "✅ Ancien TODO supprimé"
fi

# Vérifier qu'il n'y a pas de mock
if grep -q "_extract_topics_from_content" app/workers/classification_worker.py; then
    echo "❌ Méthode mock _extract_topics_from_content encore présente"
    exit 1
else
    echo "✅ Méthode mock supprimée"
fi
echo ""

echo "================================================="
echo "✅ Vérification US-3 terminée avec succès!"
echo "================================================="
echo ""
echo "Résumé des changements:"
echo "  ✅ ML_ENABLED=true configuré"
echo "  ✅ ClassificationService avec classify_async()"
echo "  ✅ ClassificationWorker avec mDeBERTa intégré"
echo "  ✅ Fallback vers source.granular_topics"
echo "  ✅ Metrics et logging améliorés"
echo "  ✅ Endpoints /admin/ml-status et /admin/classification-metrics"
echo "  ✅ Tests d'intégration créés"
echo ""
echo "Prochaines étapes:"
echo "  1. Tester en local: ML_ENABLED=true && python -m app.main"
echo "  2. Vérifier /admin/ml-status retourne enabled: true"
echo "  3. Lancer le worker et vérifier classification"
echo "  4. Monitorer les logs pour fallback_rate"
echo ""
