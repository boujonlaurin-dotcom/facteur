#!/bin/bash
# Hook: PreToolUse (Edit/Write)
# Bloque toute modification de fichiers de deploy liée à alembic/migrations
# Les migrations SQL doivent être fournies à copier-coller dans Supabase SQL Editor

file=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

# Ne vérifier que les fichiers de deploy
case "$file" in
  *Dockerfile*|*docker-compose*|*railway.json|*deploy*|*.github/workflows/deploy*)
    ;;
  *)
    exit 0
    ;;
esac

# Vérifier si le contenu de l'édition touche à alembic/migrations
content=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('new_string','') + ' ' + d.get('content',''))
" 2>/dev/null)

if echo "$content" | grep -qiP 'alembic|migration'; then
  echo "BLOQUÉ: Ne jamais modifier les migrations dans les fichiers de deploy."
  echo ""
  echo "Rappel Guardrail #4:"
  echo "→ Les fichiers Alembic servent uniquement de tracking de révision."
  echo "→ Les migrations SQL sont exécutées MANUELLEMENT dans Supabase SQL Editor."
  echo "→ Fournis le SQL brut à l'utilisateur pour copier-coller."
  exit 1
fi

exit 0
