#!/usr/bin/env bash
# =============================================================================
# Utilitaire : Génération de JWT test pour Facteur
# =============================================================================
#
# Génère un JWT signé HS256 compatible avec l'auth Supabase de l'API Facteur.
# Le token est écrit sur stdout (raw), sans préfixe "Bearer".
#
# Usage:
#   bash docs/qa/scripts/mint_jwt.sh <user_uuid>
#   TOKEN=$(bash docs/qa/scripts/mint_jwt.sh 00000000-0000-0000-0000-000000000001)
#
# Prérequis:
#   - ~/.facteur-secrets existe (SUPABASE_JWT_SECRET)
#   - python3 + python-jose installés (pip install python-jose[cryptography])
#
# =============================================================================

set -euo pipefail

SECRETS_FILE="$HOME/.facteur-secrets"

# --- Validate args ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 <user_uuid>" >&2
  exit 1
fi

USER_UUID="$1"

# --- Load secrets ---
if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ Missing ~/.facteur-secrets — see docs/qa/scripts/e2e_mobile_setup.sh" >&2
  exit 1
fi
source "$SECRETS_FILE"

if [ -z "${SUPABASE_JWT_SECRET:-}" ]; then
  echo "❌ SUPABASE_JWT_SECRET not set in ~/.facteur-secrets" >&2
  exit 1
fi

# --- Generate JWT ---
python3 -c "
import jose.jwt, datetime, os

secret = os.environ.get('SUPABASE_JWT_SECRET', '')
if not secret:
    raise SystemExit('SUPABASE_JWT_SECRET is empty')

now = datetime.datetime.now(datetime.timezone.utc)
payload = {
    'sub': '$USER_UUID',
    'aud': 'authenticated',
    'role': 'authenticated',
    'iat': int(now.timestamp()),
    'exp': int((now + datetime.timedelta(hours=1)).timestamp()),
}
print(jose.jwt.encode(payload, secret, algorithm='HS256'))
"
