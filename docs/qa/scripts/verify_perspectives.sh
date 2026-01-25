#!/bin/bash
# Script de vérification : Fonctionnalité Perspectives
# Usage: ./verify_perspectives.sh
# Date: 2026-01-24

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
API_DIR="$PROJECT_ROOT/packages/api"

echo "═══════════════════════════════════════════════════════════════"
echo "🔍 Vérification : Fonctionnalité Perspectives"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 1. Vérifier que le service existe et est syntaxiquement correct
echo "1️⃣ Vérification syntaxe Python..."
cd "$API_DIR"
if venv/bin/python -m py_compile app/services/perspective_service.py 2>/dev/null; then
    echo "   ✅ perspective_service.py : OK"
else
    echo "   ❌ perspective_service.py : Erreur de syntaxe"
    exit 1
fi

if venv/bin/python -m py_compile app/routers/contents.py 2>/dev/null; then
    echo "   ✅ contents.py : OK"
else
    echo "   ❌ contents.py : Erreur de syntaxe"
    exit 1
fi

# 2. Vérifier que le logging est présent
echo ""
echo "2️⃣ Vérification logging..."
if grep -q "structlog" app/services/perspective_service.py; then
    echo "   ✅ Logging structlog présent"
else
    echo "   ❌ Logging structlog manquant"
    exit 1
fi

if grep -q "USER_AGENT" app/services/perspective_service.py; then
    echo "   ✅ User-Agent défini"
else
    echo "   ❌ User-Agent manquant"
    exit 1
fi

# 3. Vérifier que les exceptions sont loggées (pas silencieuses)
echo ""
echo "3️⃣ Vérification gestion des erreurs..."
if grep -q "perspectives_search_timeout" app/services/perspective_service.py && \
   grep -q "perspectives_search_request_error" app/services/perspective_service.py; then
    echo "   ✅ Erreurs HTTP loggées (pas silencieuses)"
else
    echo "   ❌ Gestion des erreurs insuffisante"
    exit 1
fi

# 4. Test fonctionnel avec le service
echo ""
echo "4️⃣ Test fonctionnel du service..."
RESULT=$(venv/bin/python -c "
import asyncio
import sys
sys.path.insert(0, '.')
from app.services.perspective_service import PerspectiveService

async def test():
    service = PerspectiveService()
    
    # Test extraction keywords
    keywords = service.extract_keywords('Trump et le Venezuela : le pétro-impérialisme')
    if not keywords:
        print('FAIL: No keywords extracted')
        return False
    print(f'Keywords: {keywords}')
    
    # Test search
    perspectives = await service.search_perspectives(keywords)
    if not perspectives:
        print('FAIL: No perspectives found')
        return False
    
    print(f'Perspectives: {len(perspectives)} found')
    return True

success = asyncio.run(test())
print('SUCCESS' if success else 'FAIL')
" 2>&1)

if echo "$RESULT" | grep -q "SUCCESS"; then
    echo "   ✅ Service fonctionnel"
    echo "   $(echo "$RESULT" | grep -E 'Keywords:|Perspectives:')"
else
    echo "   ❌ Service non fonctionnel"
    echo "   $RESULT"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ TOUS LES TESTS PASSENT"
echo "═══════════════════════════════════════════════════════════════"
