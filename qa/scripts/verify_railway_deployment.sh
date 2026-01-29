#!/bin/bash
# Verification script for Railway deployment with migration fixes
# Usage: ./verify_railway_deployment.sh

set -e

PROD_URL="https://facteur-production.up.railway.app"

echo "========================================="
echo "Railway Deployment Verification"
echo "========================================="
echo ""

# 1. Test liveness probe (should always work if app is up)
echo "1. Testing liveness probe (/api/health)..."
LIVENESS=$(curl -s -o /dev/null -w "%{http_code}" "$PROD_URL/api/health" 2>/dev/null || echo "000")
if [ "$LIVENESS" = "200" ]; then
    echo "   ✅ Liveness: HTTP $LIVENESS"
else
    echo "   ❌ Liveness: HTTP $LIVENESS (expected 200)"
    echo "   App may not be running. Check Railway logs."
fi

# 2. Test readiness probe (checks DB connectivity)
echo ""
echo "2. Testing readiness probe (/api/health/ready)..."
READINESS_RESPONSE=$(curl -s "$PROD_URL/api/health/ready" 2>/dev/null || echo '{"error":"curl failed"}')
READINESS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PROD_URL/api/health/ready" 2>/dev/null || echo "000")

if [ "$READINESS_CODE" = "200" ]; then
    echo "   ✅ Readiness: HTTP $READINESS_CODE"
    echo "   Response: $READINESS_RESPONSE"
elif [ "$READINESS_CODE" = "503" ]; then
    echo "   ⚠️  Readiness: HTTP $READINESS_CODE (DB not ready)"
    echo "   Response: $READINESS_RESPONSE"
else
    echo "   ❌ Readiness: HTTP $READINESS_CODE"
fi

# 3. Check health response details
echo ""
echo "3. Health response details..."
curl -s "$PROD_URL/api/health" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "   (Could not parse JSON)"

# 4. Guidance
echo ""
echo "========================================="
echo "DEPLOYMENT GUIDANCE"
echo "========================================="
echo ""
echo "If deployment is stuck on migrations:"
echo ""
echo "  1. Set bypass flag in Railway:"
echo "     railway variables set FACTEUR_MIGRATION_IN_PROGRESS=1"
echo ""
echo "  2. Redeploy (app will start without migration check)"
echo ""
echo "  3. Run migrations manually:"
echo "     railway run -- alembic upgrade head"
echo ""
echo "  4. Remove bypass flag:"
echo "     railway variables unset FACTEUR_MIGRATION_IN_PROGRESS"
echo ""
echo "  5. Redeploy to restore normal migration checks"
echo ""
echo "========================================="
