#!/usr/bin/env bash
#
# apply-supabase-auth-templates.sh
# ================================
# Pousse la config Auth « email » de Supabase à partir des SOURCES VERSIONNÉES du
# repo, via la Management API. Idempotent : un re-run qui n'a rien à changer est un
# no-op.
#
# Ce script existe pour fermer un trou récurrent : le template email « Magic Link »
# (celui de l'email de soutien, cf. docs/stories/core/premium.2.soutien-prix-libre.md)
# vivait uniquement en HTML versionné + une étape manuelle « coller dans le dashboard »
# qui n'a jamais été faite → les utilisateurs recevaient le template Supabase par
# défaut (« Your Magic Link »). On rend l'application reproductible et scriptée.
#
# Ce qu'il applique :
#   - mailer_subjects_magic_link       = objet propre
#   - mailer_templates_magic_link_content = apps/landing/emails/soutien-magic-link.html
#   - uri_allow_list                   = liste actuelle + https://facteur.app/**
#                                        (redirect du magic link Stripe vers /soutenir)
#
# Le SMTP custom (Resend, expéditeur laurin@facteur.app) est déjà configuré côté
# dashboard : ce script ne le touche pas.
#
# Pré-requis :
#   - SUPABASE_ACCESS_TOKEN : PAT Supabase (doit avoir le scope écriture ; un PAT
#     read-only renverra 403 sur le PATCH → voir le repli manuel plus bas).
#
# Usage :
#   bash scripts/apply-supabase-auth-templates.sh          # applique
#   DRY_RUN=1 bash scripts/apply-supabase-auth-templates.sh # affiche sans écrire
#
# Repli manuel si PAT read-only (403) :
#   Dashboard Supabase → Authentication → Email Templates → « Magic Link »
#     Subject : Merci pour ta demande de soutien
#     Body    : coller le contenu de apps/landing/emails/soutien-magic-link.html
#               (à partir du <!DOCTYPE html>)
#   Puis URL Configuration → Redirect URLs → ajouter https://facteur.app/**
#
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-ykuadtelnzavrqzbfdve}"
SUBJECT="Merci pour ta demande de soutien"
EXTRA_REDIRECT="https://facteur.app/**"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="$REPO_ROOT/apps/landing/emails/soutien-magic-link.html"
API="https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth"

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "❌ SUPABASE_ACCESS_TOKEN manquant (PAT Supabase requis)." >&2
  exit 1
fi
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "❌ Template introuvable : $TEMPLATE_FILE" >&2
  exit 1
fi

# Contenu HTML à partir du <!DOCTYPE html> (on retire l'en-tête de commentaire de doc).
CONTENT="$(sed -n '/<!DOCTYPE html>/,$p' "$TEMPLATE_FILE")"
if [[ -z "$CONTENT" ]]; then
  echo "❌ Impossible d'extraire le HTML (pas de <!DOCTYPE html> dans le template)." >&2
  exit 1
fi

echo "→ Lecture de la config Auth actuelle…"
CURRENT="$(curl -fsS -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" "$API")"

# Construit le body PATCH : merge l'allow-list existante avec EXTRA_REDIRECT (sans
# doublon ni écrasement des entrées existantes), injecte subject + content.
BODY="$(
  SUBJECT="$SUBJECT" EXTRA_REDIRECT="$EXTRA_REDIRECT" CONTENT="$CONTENT" \
  python3 - "$CURRENT" <<'PY'
import json, os, sys
current = json.loads(sys.argv[1])
raw = current.get("uri_allow_list") or ""
entries = [e.strip() for e in raw.split(",") if e.strip()]
extra = os.environ["EXTRA_REDIRECT"]
if extra not in entries:
    entries.append(extra)
print(json.dumps({
    "mailer_subjects_magic_link": os.environ["SUBJECT"],
    "mailer_templates_magic_link_content": os.environ["CONTENT"],
    "uri_allow_list": ",".join(entries),
}))
PY
)"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "— DRY_RUN : body qui serait envoyé (content tronqué) —"
  echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); d['mailer_templates_magic_link_content']=d['mailer_templates_magic_link_content'][:120]+'…'; print(json.dumps(d, ensure_ascii=False, indent=2))"
  exit 0
fi

echo "→ PATCH de la config Auth…"
HTTP="$(curl -fsS -o /tmp/supabase_auth_patch.json -w '%{http_code}' \
  -X PATCH "$API" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY")" || {
    echo "❌ PATCH échoué (HTTP $HTTP). Réponse :" >&2
    cat /tmp/supabase_auth_patch.json >&2 || true
    echo >&2
    echo "   Si HTTP 403 : le PAT est read-only → voir le repli manuel en tête de script." >&2
    exit 1
  }

echo "→ Vérification…"
curl -fsS -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" "$API" \
  | SUBJECT="$SUBJECT" EXTRA_REDIRECT="$EXTRA_REDIRECT" python3 - <<'PY'
import sys, os, json
d = json.load(sys.stdin)
subj = d.get('mailer_subjects_magic_link')
content = d.get('mailer_templates_magic_link_content') or ''
allow = d.get('uri_allow_list') or ''
ok_subj = subj == os.environ['SUBJECT']
ok_brand = 'Facteur' in content
ok_allow = os.environ['EXTRA_REDIRECT'] in allow
print(f"  subject            : {subj!r}  {'✅' if ok_subj else '❌'}")
print(f"  content branded    : {'✅' if ok_brand else '❌'} ({len(content)} car.)")
print(f"  allow-list /soutenir: {'✅' if ok_allow else '❌'}")
sys.exit(0 if (ok_subj and ok_brand and ok_allow) else 2)
PY

echo "✅ Config Auth email appliquée."
