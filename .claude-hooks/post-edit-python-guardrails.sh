#!/bin/bash
# Hook: PostToolUse (Edit/Write)
# Guardrail #1: typing.List → list[] natif Python 3.12
# + Ruff lint immédiat (non-bloquant)

# Extraire le file_path du JSON input
file=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

# Ne s'applique qu'aux fichiers .py
if [[ "$file" != *.py ]]; then
  exit 0
fi

if [ ! -f "$file" ]; then
  exit 0
fi

# --- Guardrail #1: typing.List / Dict / Set / Tuple / Optional ---
bad_imports=$(grep -nP 'from typing import.*\b(List|Dict|Set|Tuple|Optional)\b' "$file" 2>/dev/null)
if [ -n "$bad_imports" ]; then
  echo "GUARDRAIL BLOQUANT: imports typing obsolètes détectés dans $file"
  echo "$bad_imports"
  echo ""
  echo "→ Utiliser les types natifs Python 3.12:"
  echo "  List → list, Dict → dict, Set → set, Tuple → tuple, Optional[X] → X | None"
  exit 1
fi

# --- Ruff lint (non-bloquant) ---
if [[ "$file" == *"packages/api"* ]] && command -v ruff &>/dev/null; then
  errors=$(ruff check "$file" --no-fix 2>&1 | head -15)
  if [ -n "$errors" ]; then
    echo "Ruff lint warnings:"
    echo "$errors"
  fi
fi

exit 0
