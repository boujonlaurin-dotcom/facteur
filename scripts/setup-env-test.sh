#!/usr/bin/env bash
# =============================================================================
# setup-env-test.sh — Configure ~/.facteur/.env.test interactivement
#
# Crée (ou met à jour) le fichier ~/.facteur/.env.test avec les secrets
# nécessaires aux tests API. Hors repo, jamais commité. Pose les questions
# une par une et sauvegarde uniquement à la fin.
#
# Usage :
#   bash scripts/setup-env-test.sh
# =============================================================================

set -euo pipefail

ENV_DIR="$HOME/.facteur"
ENV_FILE="$ENV_DIR/.env.test"
mkdir -p "$ENV_DIR"

echo "=== Configuration ~/.facteur/.env.test ==="
echo ""
echo "Ce fichier est stocké hors du repo (jamais committé)."
echo "Réponds à chaque question, ou laisse vide pour garder la valeur actuelle."
echo ""

# ─── Charger valeurs existantes si le fichier existe ──────────────────────────
DATABASE_URL=""
SUPABASE_JWT_SECRET=""
MISTRAL_API_KEY=""
SENTRY_DSN=""

if [ -f "$ENV_FILE" ]; then
  echo "[i] ~/.facteur/.env.test détecté — valeurs actuelles rechargées."
  set +u
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set -u
  echo ""
fi

mask() {
  local v="$1"
  local n=${#v}
  if [ "$n" -le 10 ]; then
    printf "****"
  else
    printf "%s****%s" "${v:0:4}" "${v: -4}"
  fi
}

prompt() {
  local varname="$1"
  local label="$2"
  local help="$3"
  local current="${!varname:-}"

  echo ""
  echo "📝 $label"
  echo "   $help"
  if [ -n "$current" ]; then
    echo "   Valeur actuelle : $(mask "$current")"
  fi
  read -r -p "   Nouvelle valeur (Entrée = inchangé) : " input
  if [ -n "$input" ]; then
    printf -v "$varname" '%s' "$input"
  fi
}

# ─── DATABASE_URL (défaut : DB test locale dockerisée) ────────────────────────
if [ -z "$DATABASE_URL" ]; then
  DATABASE_URL="postgresql+psycopg://facteur:facteur@localhost:54322/facteur_test"
fi
echo ""
echo "📝 DATABASE_URL"
echo "   Par défaut pointe sur la DB test dockerisée. On le garde tel quel."
echo "   Valeur : $DATABASE_URL"

# ─── Supabase JWT secret (obligatoire pour tests auth) ────────────────────────
prompt SUPABASE_JWT_SECRET \
  "SUPABASE_JWT_SECRET" \
  "Obtenir : Supabase Dashboard → Project Settings → API → JWT Secret"

# ─── Mistral API key (LLM pipeline) ───────────────────────────────────────────
prompt MISTRAL_API_KEY \
  "MISTRAL_API_KEY" \
  "Obtenir : console.mistral.ai → API Keys (budget test cappé recommandé)"

# ─── Sentry DSN (optionnel en test, laisser vide est OK) ──────────────────────
prompt SENTRY_DSN \
  "SENTRY_DSN (optionnel)" \
  "Laisse vide pour ne pas envoyer d'erreurs Sentry pendant les tests."

# ─── Écriture atomique ────────────────────────────────────────────────────────
TMP_FILE="$(mktemp)"
cat >"$TMP_FILE" <<EOF
# ~/.facteur/.env.test — secrets test Facteur (hors repo, ne pas committer)
# Généré par scripts/setup-env-test.sh
DATABASE_URL=$DATABASE_URL
SUPABASE_JWT_SECRET=$SUPABASE_JWT_SECRET
MISTRAL_API_KEY=$MISTRAL_API_KEY
SENTRY_DSN=$SENTRY_DSN
EOF
chmod 600 "$TMP_FILE"
mv "$TMP_FILE" "$ENV_FILE"

echo ""
echo "✅ Sauvegardé dans $ENV_FILE"
echo ""
echo "Vérifier l'état complet : bash scripts/doctor.sh"
