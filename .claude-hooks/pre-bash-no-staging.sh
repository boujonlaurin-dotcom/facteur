#!/usr/bin/env bash
# Hook: Block any gh pr create that targets staging instead of main.
# staging is deprecated — all PRs must target main.

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

# Block: either no --base flag (defaults to staging) or explicit --base staging
echo "BLOCKED: PR targets staging (the deprecated default branch)."
echo ""
echo "staging est déprécié. Toutes les PRs doivent cibler main."
echo "Ajoute --base main à ta commande gh pr create."
echo ""
echo "Exemple : gh pr create --base main --title '...' --body '...'"
exit 2
