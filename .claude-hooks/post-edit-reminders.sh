#!/bin/bash
# Hook: PostToolUse (Edit/Write)
# Rappels non-bloquants: pytest (backend) et flutter analyze (mobile)

file=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

if [[ "$file" == *"packages/api/app/"*".py" ]]; then
  echo "RAPPEL: Pense à lancer 'cd packages/api && pytest -v' après tes modifications backend."
fi

if [[ "$file" == *"apps/mobile"*".dart" ]]; then
  echo "RAPPEL: Pense à lancer 'cd apps/mobile && flutter analyze' après tes modifications Dart."
fi

exit 0
