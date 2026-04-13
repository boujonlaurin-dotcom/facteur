#!/bin/bash
# Hook: PostToolUse (Edit|Write)
# Exécute automatiquement les tests liés au fichier modifié (non-bloquant).
# Remplace l'ancien post-edit-reminders.sh qui ne faisait que rappeler.

file=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)
[ -z "$file" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Paths des outils installés
PYTEST="${PROJECT_DIR}/.venv/bin/pytest"
FLUTTER="/opt/flutter/bin/flutter"
export CI=true

# Backend Python: lance pytest sur les tests liés
if [[ "$file" == *"packages/api/app/"*".py" ]]; then
  module=$(basename "$file" .py)
  test_file="$PROJECT_DIR/packages/api/tests/test_${module}.py"

  if [ -f "$test_file" ]; then
    echo "AUTO-TEST: pytest $test_file"
    cd "$PROJECT_DIR/packages/api" && PYTHONPATH="$PROJECT_DIR/packages/api" "$PYTEST" "$test_file" -x -q --tb=short 2>&1 | tail -20
  else
    # Cherche un test correspondant dans les sous-dossiers
    found=$(find "$PROJECT_DIR/packages/api/tests" -name "test_*${module}*.py" -type f 2>/dev/null | head -1)
    if [ -n "$found" ]; then
      echo "AUTO-TEST: pytest $found"
      cd "$PROJECT_DIR/packages/api" && PYTHONPATH="$PROJECT_DIR/packages/api" "$PYTEST" "$found" -x -q --tb=short 2>&1 | tail -20
    else
      echo "AUTO-TEST: Pas de test trouvé pour $module — pense à en créer un."
    fi
  fi
fi

# Mobile Dart: lance flutter test sur le fichier correspondant
if [[ "$file" == *"apps/mobile/lib/"*".dart" ]]; then
  # Déduit le chemin de test depuis le chemin source
  relative="${file#*apps/mobile/lib/}"
  test_file="$PROJECT_DIR/apps/mobile/test/${relative%.dart}_test.dart"

  if [ -f "$test_file" ]; then
    echo "AUTO-TEST: flutter test $test_file"
    cd "$PROJECT_DIR/apps/mobile" && "$FLUTTER" test "$test_file" --no-pub 2>&1 | tail -20
  else
    echo "AUTO-TEST: flutter analyze (pas de test unitaire trouvé pour $relative)"
    cd "$PROJECT_DIR/apps/mobile" && "$FLUTTER" analyze --no-pub "lib/$relative" 2>&1 | tail -10
  fi
fi

exit 0
