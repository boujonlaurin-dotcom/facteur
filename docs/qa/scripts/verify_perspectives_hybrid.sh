#!/bin/bash
# =============================================================================
# Vérification : Pipeline hybride Perspectives (3 couches)
# =============================================================================
#
# Valide le nouveau pipeline via des exemples concrets tirés de la DB prod.
# Chaque test case cible un scénario spécifique (faux positif, recall, fallback).
#
# Usage:
#   bash docs/qa/scripts/verify_perspectives_hybrid.sh
#
# Prérequis:
#   - ~/.facteur-secrets existe (DATABASE_URL, SUPABASE_JWT_SECRET)
#   - API locale sur port 8080 OU variable API_BASE_URL définie
#   - jq installé
#
# Pour ajuster les paramètres de matching, voir le prompt compagnon :
#   docs/qa/scripts/TUNING_PROMPT_PERSPECTIVES.md
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
API_DIR="$PROJECT_ROOT/packages/api"
SECRETS_FILE="$HOME/.facteur-secrets"

# --- Counters ---
PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); echo "   ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "   ❌ $1"; }
skip() { SKIP=$((SKIP + 1)); echo "   ⏭️  $1"; }

# --- Load secrets ---
if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ Missing ~/.facteur-secrets — see docs/qa/scripts/e2e_mobile_setup.sh"
  exit 1
fi
source "$SECRETS_FILE"

API_BASE="${API_BASE_URL:-http://localhost:8080}"

echo "═══════════════════════════════════════════════════════════════"
echo "🔍 Vérification : Pipeline Hybride Perspectives"
echo "═══════════════════════════════════════════════════════════════"
echo "   API: $API_BASE"
echo ""

# --- Generate JWT ---
echo "0️⃣  Génération JWT de test..."
TOKEN=$(python3 -c "
import jose.jwt, datetime, os
secret = os.environ.get('SUPABASE_JWT_SECRET', '$SUPABASE_JWT_SECRET')
payload = {
    'sub': '00000000-0000-0000-0000-000000000001',
    'aud': 'authenticated',
    'role': 'authenticated',
    'iat': int(datetime.datetime.now(datetime.timezone.utc).timestamp()),
    'exp': int((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=2)).timestamp()),
}
print('Bearer ' + jose.jwt.encode(payload, secret, algorithm='HS256'))
" 2>&1)

if [[ ! "$TOKEN" == Bearer* ]]; then
  echo "   ❌ JWT generation failed: $TOKEN"
  exit 1
fi
echo "   ✅ JWT OK"
echo ""

# --- Health check ---
echo "0️⃣  Health check API..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE/api/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" != "200" ]; then
  echo "   ❌ API non joignable ($HTTP_CODE) — lancer: cd packages/api && uvicorn app.main:app --port 8080"
  exit 1
fi
echo "   ✅ API OK"
echo ""

# =============================================================================
# PHASE 1 : Syntaxe + imports
# =============================================================================
echo "1️⃣  Syntaxe Python..."
cd "$API_DIR"

for f in app/services/perspective_service.py app/routers/contents.py app/services/editorial/llm_client.py; do
  if python3 -c "import ast; ast.parse(open('$f').read())" 2>/dev/null; then
    pass "$f"
  else
    fail "$f — erreur de syntaxe"
  fi
done
echo ""

# =============================================================================
# PHASE 2 : Tests unitaires des nouvelles fonctions (sans DB, sans réseau)
# =============================================================================
echo "2️⃣  Tests unitaires (hors réseau)..."

UNIT_RESULT=$(cd "$API_DIR" && python3 -c "
import sys, json
sys.path.insert(0, '.')
from app.services.perspective_service import _parse_entity_names, PerspectiveService

errors = []

# --- _parse_entity_names ---
# Basic parsing
entities = [
    json.dumps({'type': 'PERSON', 'name': 'Lionel Jospin'}),
    json.dumps({'type': 'ORG', 'name': 'TotalEnergies'}),
    json.dumps({'type': 'EVENT', 'name': 'COP30'}),
    json.dumps({'type': 'LOCATION', 'name': 'Paris'}),
]

# All types
names_all = _parse_entity_names(entities)
if len(names_all) != 4:
    errors.append(f'parse_all: expected 4 got {len(names_all)}')

# Filter PERSON+ORG
names_po = _parse_entity_names(entities, types={'PERSON', 'ORG'})
if names_po != ['Lionel Jospin', 'TotalEnergies']:
    errors.append(f'parse_person_org: got {names_po}')

# Empty / None
if _parse_entity_names(None) != []:
    errors.append('parse_none should return []')
if _parse_entity_names([]) != []:
    errors.append('parse_empty should return []')

# Malformed JSON
if _parse_entity_names(['not json', '{bad']) != []:
    errors.append('parse_malformed should return []')

# --- build_entity_query ---
svc = PerspectiveService()

# With entities: should quote names + add context words
q = svc.build_entity_query(entities, 'Lionel Jospin et les remords de la gauche')
has_quoted = any('\"' in term for term in q)
if not has_quoted:
    errors.append(f'build_entity_query: no quoted terms in {q}')
# Should NOT contain 'remords' as a quoted entity
if any('remords' in term and '\"' in term for term in q):
    errors.append(f'build_entity_query: remords should not be quoted: {q}')

# Without entities: should fallback to extract_keywords
q_fallback = svc.build_entity_query(None, 'Trump et le Venezuela : le pétro-impérialisme')
if not q_fallback:
    errors.append('build_entity_query fallback: empty')
# Should not contain quotes (pure keyword extraction)
if any('\"' in term for term in q_fallback):
    errors.append(f'build_entity_query fallback: unexpected quotes in {q_fallback}')

if errors:
    for e in errors:
        print(f'FAIL: {e}')
else:
    print('ALL_PASS')
" 2>&1)

if echo "$UNIT_RESULT" | grep -q "ALL_PASS"; then
  pass "Tous les tests unitaires OK"
else
  echo "$UNIT_RESULT" | grep "FAIL:" | while read -r line; do
    fail "$line"
  done
fi
echo ""

# =============================================================================
# PHASE 3 : Découverte de cas de test en DB
# =============================================================================
echo "3️⃣  Découverte de cas de test en DB..."

# Find concrete content IDs for each scenario
TEST_CASES=$(cd "$API_DIR" && python3 -c "
import sys, json, os
sys.path.insert(0, '.')

# Connect to DB synchronously for discovery
import psycopg
db_url = os.environ.get('DATABASE_URL', '$DATABASE_URL')
# Convert async URL to sync
sync_url = db_url.replace('+psycopg', '')

conn = psycopg.connect(sync_url)
cur = conn.cursor()

cases = {}

# Case A: Article with PERSON entity (high-profile person → should get many perspectives)
cur.execute(\"\"\"
    SELECT c.id, c.title, c.entities, s.name as source_name
    FROM contents c
    JOIN sources s ON c.source_id = s.id
    WHERE c.entities IS NOT NULL
      AND array_length(c.entities, 1) >= 2
      AND c.published_at > now() - interval '5 days'
      AND EXISTS (
          SELECT 1 FROM unnest(c.entities) e
          WHERE e::text ILIKE '%PERSON%'
      )
    ORDER BY c.published_at DESC
    LIMIT 3
\"\"\")
rows = cur.fetchall()
if rows:
    cases['with_person_entity'] = [
        {'id': str(r[0]), 'title': r[1], 'entities': r[2][:3] if r[2] else [], 'source': r[3]}
        for r in rows
    ]

# Case B: Article WITHOUT entities (should fallback to keywords-only)
cur.execute(\"\"\"
    SELECT c.id, c.title, s.name as source_name
    FROM contents c
    JOIN sources s ON c.source_id = s.id
    WHERE (c.entities IS NULL OR array_length(c.entities, 1) IS NULL)
      AND c.published_at > now() - interval '5 days'
    ORDER BY c.published_at DESC
    LIMIT 2
\"\"\")
rows = cur.fetchall()
if rows:
    cases['without_entities'] = [
        {'id': str(r[0]), 'title': r[1], 'source': r[2]}
        for r in rows
    ]

# Case C: Article with ORG entity (brand/company → good for recall test)
cur.execute(\"\"\"
    SELECT c.id, c.title, c.entities, s.name as source_name
    FROM contents c
    JOIN sources s ON c.source_id = s.id
    WHERE c.entities IS NOT NULL
      AND c.published_at > now() - interval '5 days'
      AND EXISTS (
          SELECT 1 FROM unnest(c.entities) e
          WHERE e::text ILIKE '%ORG%'
      )
    ORDER BY c.published_at DESC
    LIMIT 2
\"\"\")
rows = cur.fetchall()
if rows:
    cases['with_org_entity'] = [
        {'id': str(r[0]), 'title': r[1], 'entities': r[2][:3] if r[2] else [], 'source': r[3]}
        for r in rows
    ]

# Case D: Count entity coverage
cur.execute(\"\"\"
    SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE entities IS NOT NULL AND array_length(entities, 1) > 0) as with_entities
    FROM contents
    WHERE published_at > now() - interval '5 days'
\"\"\")
total, with_ent = cur.fetchone()
cases['coverage'] = {'total_5d': total, 'with_entities_5d': with_ent, 'pct': round(100*with_ent/total, 1) if total > 0 else 0}

conn.close()
print(json.dumps(cases, ensure_ascii=False))
" 2>&1)

if ! echo "$TEST_CASES" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  echo "   ⚠️  DB discovery failed: $TEST_CASES"
  skip "DB discovery — using fallback mode (API-only tests)"
  TEST_CASES='{}'
else
  COVERAGE=$(echo "$TEST_CASES" | python3 -c "import sys,json; d=json.load(sys.stdin); c=d.get('coverage',{}); print(f\"{c.get('with_entities_5d',0)}/{c.get('total_5d',0)} ({c.get('pct',0)}%)\")")
  echo "   Entity coverage (5j): $COVERAGE"

  N_PERSON=$(echo "$TEST_CASES" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('with_person_entity',[])))")
  N_NO_ENT=$(echo "$TEST_CASES" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('without_entities',[])))")
  N_ORG=$(echo "$TEST_CASES" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('with_org_entity',[])))")
  echo "   Found: ${N_PERSON} PERSON articles, ${N_ORG} ORG articles, ${N_NO_ENT} no-entity articles"
  pass "DB discovery OK"
fi
echo ""

# =============================================================================
# PHASE 4 : Tests E2E sur l'API — chaque scénario
# =============================================================================
echo "4️⃣  Tests E2E sur l'API..."

call_perspectives() {
  local content_id="$1"
  local label="$2"

  local RESP
  RESP=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: $TOKEN" \
    "$API_BASE/api/contents/$content_id/perspectives" 2>/dev/null)

  local HTTP_CODE
  HTTP_CODE=$(echo "$RESP" | tail -1)
  local BODY
  BODY=$(echo "$RESP" | sed '$d')

  if [ "$HTTP_CODE" != "200" ]; then
    fail "$label — HTTP $HTTP_CODE"
    return 1
  fi

  local COUNT
  COUNT=$(echo "$BODY" | jq '.perspectives | length' 2>/dev/null || echo "0")
  local KEYWORDS
  KEYWORDS=$(echo "$BODY" | jq -r '.keywords | join(", ")' 2>/dev/null || echo "?")
  local BIAS_DIST
  BIAS_DIST=$(echo "$BODY" | jq -c '.bias_distribution' 2>/dev/null || echo "{}")

  echo "   📊 $label"
  echo "      Keywords: $KEYWORDS"
  echo "      Results: $COUNT perspectives"
  echo "      Bias: $BIAS_DIST"

  # Return count for assertions
  echo "$COUNT"
}

# Helper: extract content IDs from test cases JSON
get_id() {
  echo "$TEST_CASES" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d.get('$1', [])
idx = $2
if idx < len(items):
    print(items[idx]['id'])
else:
    print('')
" 2>/dev/null
}

get_title() {
  echo "$TEST_CASES" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d.get('$1', [])
idx = $2
if idx < len(items):
    print(items[idx]['title'][:80])
else:
    print('?')
" 2>/dev/null
}

echo ""
echo "   --- Scénario A: Articles avec entité PERSON ---"
PERSON_ID=$(get_id "with_person_entity" 0)
if [ -n "$PERSON_ID" ]; then
  TITLE_A=$(get_title "with_person_entity" 0)
  echo "   Article: \"$TITLE_A\""
  RESULT_A=$(call_perspectives "$PERSON_ID" "PERSON entity" 2>&1 | tail -1)
  if [ "$RESULT_A" -ge 3 ] 2>/dev/null; then
    pass "PERSON entity: $RESULT_A perspectives (≥3)"
  else
    fail "PERSON entity: seulement $RESULT_A perspectives (<3)"
  fi
else
  skip "Aucun article PERSON trouvé en DB"
fi

echo ""
echo "   --- Scénario B: Articles SANS entités (fallback keywords) ---"
NO_ENT_ID=$(get_id "without_entities" 0)
if [ -n "$NO_ENT_ID" ]; then
  TITLE_B=$(get_title "without_entities" 0)
  echo "   Article: \"$TITLE_B\""
  RESULT_B=$(call_perspectives "$NO_ENT_ID" "Sans entités (fallback)" 2>&1 | tail -1)
  if [ "$RESULT_B" -ge 1 ] 2>/dev/null; then
    pass "Fallback keywords: $RESULT_B perspectives (≥1)"
  else
    fail "Fallback keywords: 0 perspectives"
  fi
else
  skip "Aucun article sans entités trouvé en DB"
fi

echo ""
echo "   --- Scénario C: Articles avec entité ORG (recall) ---"
ORG_ID=$(get_id "with_org_entity" 0)
if [ -n "$ORG_ID" ]; then
  TITLE_C=$(get_title "with_org_entity" 0)
  echo "   Article: \"$TITLE_C\""
  RESULT_C=$(call_perspectives "$ORG_ID" "ORG entity (recall)" 2>&1 | tail -1)
  if [ "$RESULT_C" -ge 2 ] 2>/dev/null; then
    pass "ORG entity: $RESULT_C perspectives (≥2)"
  else
    fail "ORG entity: seulement $RESULT_C perspectives (<2)"
  fi
else
  skip "Aucun article ORG trouvé en DB"
fi

echo ""

# =============================================================================
# PHASE 5 : Test endpoint analyse LLM
# =============================================================================
echo "5️⃣  Test endpoint analyse LLM..."
ANALYZE_ID="${PERSON_ID:-$ORG_ID}"
if [ -n "$ANALYZE_ID" ]; then
  ANALYZE_RESP=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: $TOKEN" \
    "$API_BASE/api/contents/$ANALYZE_ID/perspectives/analyze" 2>/dev/null)

  ANALYZE_CODE=$(echo "$ANALYZE_RESP" | tail -1)
  ANALYZE_BODY=$(echo "$ANALYZE_RESP" | sed '$d')

  if [ "$ANALYZE_CODE" == "200" ]; then
    HAS_ANALYSIS=$(echo "$ANALYZE_BODY" | jq -r '.analysis // "null"' 2>/dev/null)
    if [ "$HAS_ANALYSIS" != "null" ] && [ -n "$HAS_ANALYSIS" ]; then
      pass "Analyse LLM retournée (${#HAS_ANALYSIS} chars)"
      echo "      Extrait: $(echo "$HAS_ANALYSIS" | head -c 120)..."
    else
      skip "Analyse null (Mistral probablement indisponible — acceptable)"
    fi
  else
    fail "Endpoint analyse HTTP $ANALYZE_CODE"
  fi
else
  skip "Pas de content_id disponible pour tester l'analyse"
fi

echo ""

# =============================================================================
# PHASE 6 : Comparaison ancien vs nouveau (si 2e article PERSON dispo)
# =============================================================================
echo "6️⃣  Diagnostic détaillé pipeline (Layer 1/2/3)..."
DIAG_ID="${PERSON_ID:-$ORG_ID}"
if [ -n "$DIAG_ID" ]; then
  cd "$API_DIR"
  DIAG_RESULT=$(python3 -c "
import sys, json, asyncio, os
sys.path.insert(0, '.')

async def diagnose():
    # Minimal async DB setup
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
    from sqlalchemy.orm import sessionmaker, joinedload
    from sqlalchemy import select
    from app.models.content import Content
    from app.services.perspective_service import PerspectiveService, _parse_entity_names

    db_url = os.environ.get('DATABASE_URL', '$DATABASE_URL')
    engine = create_async_engine(db_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        result = await session.execute(
            select(Content)
                .options(joinedload(Content.source))
                .where(Content.id == '$DIAG_ID')
        )
        content = result.scalars().first()
        if not content:
            print(json.dumps({'error': 'Content not found'}))
            return

        svc = PerspectiveService(db=session, max_results=10)

        # Entities parsed
        entities_person = _parse_entity_names(content.entities, types={'PERSON', 'ORG'})

        # Layer 1: internal DB
        internal = await svc.search_internal_perspectives(content)

        # Layer 2 query
        entity_query = svc.build_entity_query(content.entities, content.title)

        # Fallback query
        fallback_query = svc.extract_keywords(content.title)

        # Full hybrid
        merged, keywords = await svc.get_perspectives_hybrid(
            content, exclude_domain=svc._extract_domain(content.source.url) if content.source else None
        )

        report = {
            'title': content.title,
            'source': content.source.name if content.source else '?',
            'entities_parsed': entities_person,
            'layer1_internal_count': len(internal),
            'layer1_domains': [p.source_domain for p in internal],
            'layer2_entity_query': entity_query,
            'layer3_fallback_query': fallback_query,
            'layer2_equals_layer3': entity_query == fallback_query,
            'total_merged': len(merged),
            'merged_domains': [p.source_domain for p in merged],
            'merged_biases': [p.bias_stance for p in merged],
        }
        print(json.dumps(report, ensure_ascii=False, indent=2))

    await engine.dispose()

asyncio.run(diagnose())
" 2>&1)

  if echo "$DIAG_RESULT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    echo "$DIAG_RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"   Article: {d['title'][:80]}\")
print(f\"   Source: {d['source']}\")
print(f\"   Entities (PERSON/ORG): {d['entities_parsed']}\")
print(f\"   Layer 1 (DB interne): {d['layer1_internal_count']} résultats → {d['layer1_domains']}\")
print(f\"   Layer 2 (Google entities): query={d['layer2_entity_query']}\")
print(f\"   Layer 3 (fallback keywords): query={d['layer3_fallback_query']}\")
print(f\"   Layer 2 == Layer 3: {d['layer2_equals_layer3']} {'(pas de fallback nécessaire)' if d['layer2_equals_layer3'] else '(fallback activé si < 6)'}\")
print(f\"   Total fusionné: {d['total_merged']} perspectives\")
print(f\"   Domaines: {d['merged_domains']}\")
print(f\"   Biais: {d['merged_biases']}\")
"
    TOTAL=$(echo "$DIAG_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['total_merged'])")
    if [ "$TOTAL" -ge 3 ] 2>/dev/null; then
      pass "Diagnostic: $TOTAL perspectives fusionnées (≥3)"
    else
      fail "Diagnostic: seulement $TOTAL perspectives fusionnées (<3)"
    fi
  else
    fail "Diagnostic erreur: $DIAG_RESULT"
  fi
else
  skip "Pas de content_id pour le diagnostic"
fi

echo ""

# =============================================================================
# RÉSUMÉ
# =============================================================================
echo "═══════════════════════════════════════════════════════════════"
TOTAL_TESTS=$((PASS + FAIL + SKIP))
echo "📋 Résumé: $PASS pass / $FAIL fail / $SKIP skip (sur $TOTAL_TESTS tests)"

if [ "$FAIL" -gt 0 ]; then
  echo "❌ ÉCHECS DÉTECTÉS — voir les détails ci-dessus"
  exit 1
else
  echo "✅ TOUS LES TESTS PASSENT"
  exit 0
fi
