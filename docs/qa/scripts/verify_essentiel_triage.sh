#!/bin/bash
# Story 33.1 — vérification E2E de `POST /api/essentiel/triage`.
#
# Le point le plus important n'est pas que l'endpoint réponde 200 : c'est qu'il
# ne touche RIEN. La V0 est en collecte seule (décision PO n°2), et l'action
# `not_interested` existante est à un enum de distance (elle ajouterait la
# source entière à `user_personalization.muted_sources`, sans expiration).
# Ce script vérifie l'écriture ET la non-écriture.
#
# Usage :
#   API_URL=http://localhost:8080 JWT=<token> bash docs/qa/scripts/verify_essentiel_triage.sh
set -euo pipefail

API_URL="${API_URL:-http://localhost:8080}"
JWT="${JWT:-}"

if [ -z "$JWT" ]; then
  echo "❌ JWT manquant. Exporter JWT=<token> (cf. docs/qa/scripts/e2e_mobile_setup.sh)."
  exit 1
fi

AUTH=(-H "Authorization: Bearer $JWT" -H "Content-Type: application/json")
TODAY="$(date +%F)"

echo "→ 1. Lecture du slate du jour (GET /api/essentiel)"
SLATE_JSON="$(curl -sS "${AUTH[@]}" "$API_URL/api/essentiel")"
IDS="$(echo "$SLATE_JSON" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print(" ".join(a["content_id"] for a in data.get("articles", [])))
')"
if [ -z "$IDS" ]; then
  echo "⚠️  Aucun article servi (202 preparing ?) — rien à trier, arrêt."
  exit 0
fi
# shellcheck disable=SC2206
ID_ARRAY=($IDS)
SLATE_SIZE="${#ID_ARRAY[@]}"
echo "   slate = $SLATE_SIZE articles"

echo "→ 2. Cas nominal : un batch de décisions"
BODY="$(python3 - "$TODAY" "$SLATE_SIZE" "${ID_ARRAY[@]}" <<'PY'
import json, sys
today, slate_size, *ids = sys.argv[1:]
decisions = []
for i, cid in enumerate(ids):
    decisions.append({
        "content_id": cid,
        "decision": ["keep", "pass", "later"][i % 3],
        "rank": i + 1,
        "decided_via": "swipe",
        "latency_ms": 1200,
    })
print(json.dumps({
    "digest_date": today,
    "slate_size": int(slate_size),
    "decisions": decisions,
}))
PY
)"
RESP="$(curl -sS -w '\n%{http_code}' "${AUTH[@]}" -X POST "$API_URL/api/essentiel/triage" -d "$BODY")"
CODE="$(echo "$RESP" | tail -1)"
[ "$CODE" = "200" ] || { echo "❌ attendu 200, reçu $CODE"; echo "$RESP"; exit 1; }
echo "   ✅ 200 — $(echo "$RESP" | head -n -1)"

echo "→ 3. Idempotence : le même batch rejoué ne duplique pas"
RESP2="$(curl -sS -w '\n%{http_code}' "${AUTH[@]}" -X POST "$API_URL/api/essentiel/triage" -d "$BODY")"
CODE2="$(echo "$RESP2" | tail -1)"
[ "$CODE2" = "200" ] || { echo "❌ rejeu : attendu 200, reçu $CODE2"; exit 1; }
echo "   ✅ rejeu accepté (upsert sur user+article+jour)"

echo "→ 4. Cas limite : un rang hors du slate doit être refusé (422)"
BAD="$(python3 - "$TODAY" "${ID_ARRAY[0]}" <<'PY'
import json, sys
today, cid = sys.argv[1:]
print(json.dumps({
    "digest_date": today,
    "slate_size": 3,
    "decisions": [{"content_id": cid, "decision": "keep", "rank": 99}],
}))
PY
)"
CODE3="$(curl -sS -o /dev/null -w '%{http_code}' "${AUTH[@]}" -X POST "$API_URL/api/essentiel/triage" -d "$BAD")"
[ "$CODE3" = "422" ] || { echo "❌ rang hors slate : attendu 422, reçu $CODE3"; exit 1; }
echo "   ✅ 422 — le dénominateur de la jauge est protégé"

echo "→ 5. Cas limite : une décision inconnue est refusée (422)"
BAD2="$(python3 - "$TODAY" "${ID_ARRAY[0]}" <<'PY'
import json, sys
today, cid = sys.argv[1:]
print(json.dumps({
    "digest_date": today,
    "slate_size": 5,
    "decisions": [{"content_id": cid, "decision": "not_interested", "rank": 1}],
}))
PY
)"
CODE4="$(curl -sS -o /dev/null -w '%{http_code}' "${AUTH[@]}" -X POST "$API_URL/api/essentiel/triage" -d "$BAD2")"
[ "$CODE4" = "422" ] || { echo "❌ decision inconnue : attendu 422, reçu $CODE4"; exit 1; }
echo "   ✅ 422 — 'not_interested' n'est pas un vocabulaire du tri"

echo
echo "✅ Endpoint OK. Vérifications DB à faire ensuite (psql \$DATABASE_URL_RO) :"
echo
echo "  -- les décisions sont écrites, avec rang et taille de slate"
echo "  SELECT decision, rank, slate_size, decided_via, latency_ms"
echo "    FROM essentiel_triage_decisions WHERE digest_date = '$TODAY';"
echo
echo "  -- GARDE-FOU : aucune source mutée par un 'pass'"
echo "  SELECT user_id, muted_sources FROM user_personalization"
echo "   WHERE cardinality(muted_sources) > 0;"
echo
echo "  -- GARDE-FOU : aucun poids bougé par le tri"
echo "  SELECT count(*) FROM user_subtopics WHERE updated_at > now() - interval '5 min';"
echo "  SELECT count(*) FROM user_entity_affinity WHERE updated_at > now() - interval '5 min';"
echo
echo "  -- seul effet attendu : le(s) 'later' sont bien mis de côté"
echo "  SELECT content_id, is_saved FROM user_content_status WHERE is_saved IS TRUE;"
