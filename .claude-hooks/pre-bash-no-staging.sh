#!/usr/bin/env bash
# Hook: Block any gh pr create that does not target main.
# main = continuous staging env; all PRs must target main (never production/staging).

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check gh pr create commands
if ! echo "$COMMAND" | grep -q 'gh pr create'; then
  exit 0
fi

# Check if --base main is specified
if echo "$COMMAND" | grep -qE -- '--base\s+main'; then
  exit 0
fi

# Block: no --base main (PR would target the wrong branch)
echo "BLOCKED: PR sans --base main."
echo ""
echo "main = env staging continu : toutes les PRs doivent cibler main."
echo "production est avancée seulement par le bouton hebdo (jamais une cible de PR)."
echo "Ajoute --base main à ta commande gh pr create."
echo ""
echo "Exemple : gh pr create --base main --title '...' --body '...'"
exit 2
