#!/bin/bash
# Hook: PreToolUse (Edit/Write)
# Avertit (sans bloquer) quand un fichier de deploy est édité avec du contenu
# touchant Alembic. Le `Dockerfile` exécute légitimement `alembic upgrade head`
# au démarrage du conteneur Railway — toute erreur dans la chaîne plante le
# déploiement (le CMD a un fallback qui démarre uvicorn avec un WARNING dans
# les logs, donc une migration cassée peut passer inaperçue).
#
# Historique : avant le squash de baseline (PR #515, mai 2026), ce hook
# bloquait les edits et orientait vers du SQL manuel via Supabase SQL Editor.
# C'est exactement le pattern qui a causé l'incident de drift d'avril 2026 ;
# Alembic est désormais la seule source de vérité pour le schéma.

file=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

case "$file" in
  *Dockerfile*|*docker-compose*|*railway.json|*deploy*|*.github/workflows/deploy*)
    ;;
  *)
    exit 0
    ;;
esac

content=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('new_string','') + ' ' + d.get('content',''))
" 2>/dev/null)

if echo "$content" | grep -qiP 'alembic|migration'; then
  cat >&2 <<'WARN'
[pre-edit-alembic-deploy] Édition d'un fichier de deploy touchant Alembic.
  Rappel : le Dockerfile rejoue `alembic upgrade head` au boot Railway. Une
  migration cassée plante le déploiement (le fallback du CMD démarre uvicorn
  malgré l'erreur — surveille les logs après deploy). Pas de SQL manuel via
  Supabase SQL Editor.
  Si tu débogues une chaîne qui drift, consulte
  docs/runbooks/recover-from-alembic-drift.md.
WARN
fi

exit 0
