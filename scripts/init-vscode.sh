#!/usr/bin/env bash
# init-vscode.sh — Initialise .vscode/launch.json depuis le template générique.
# Usage: bash scripts/init-vscode.sh

set -euo pipefail

TEMPLATE=".vscode/launch.template.json"
TARGET=".vscode/launch.json"

if [ -f "$TARGET" ]; then
  echo "✓ $TARGET existe déjà — aucune action."
  echo "  Supprime-le manuellement pour réinitialiser depuis le template."
  exit 0
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "✗ Template introuvable : $TEMPLATE" >&2
  exit 1
fi

cp "$TEMPLATE" "$TARGET"
echo "✓ $TARGET créé depuis $TEMPLATE"
echo ""
echo "Prochaines étapes :"
echo "  1. Ouvre $TARGET dans Cursor"
echo "  2. Remplace les placeholders <...> par les valeurs du projet"
echo "  3. Lance une config depuis le panneau Run & Debug (Cmd+Shift+D)"
