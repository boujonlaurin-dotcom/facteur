#!/bin/bash
# Hook: Stop
# Vérifie que les tests passent avant que Claude ne termine sa réponse.
# Si des fichiers Python ou Dart ont été modifiés dans la session, lance les suites de tests.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Paths des outils installés
PYTEST="${PROJECT_DIR}/.venv/bin/pytest"
FLUTTER="/opt/flutter/bin/flutter"
export CI=true

# Détecte les fichiers modifiés (staged + unstaged) par rapport à la branche base
changed_files=$(git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null || git -C "$PROJECT_DIR" diff --name-only 2>/dev/null)

has_python=false
has_dart=false

while IFS= read -r f; do
  [[ "$f" == packages/api/app/*.py ]] && has_python=true
  [[ "$f" == apps/mobile/lib/*.dart ]] && has_dart=true
done <<< "$changed_files"

errors=()

# Tests backend Python
if $has_python; then
  echo "STOP-VERIFY: Lancement pytest..."
  if [ -d "$PROJECT_DIR/packages/api" ]; then
    output=$(cd "$PROJECT_DIR/packages/api" && PYTHONPATH="$PROJECT_DIR/packages/api" "$PYTEST" -x -q --tb=short 2>&1)
    rc=$?
    echo "$output" | tail -15
    if [ $rc -ne 0 ]; then
      errors+=("Backend pytest échoué (exit $rc)")
    else
      echo "STOP-VERIFY: pytest OK ✓"
    fi
  fi
fi

# Tests mobile Dart
if $has_dart; then
  echo "STOP-VERIFY: Lancement flutter test..."
  if [ -d "$PROJECT_DIR/apps/mobile" ]; then
    output=$(cd "$PROJECT_DIR/apps/mobile" && "$FLUTTER" test --no-pub 2>&1)
    rc=$?
    echo "$output" | tail -15
    if [ $rc -ne 0 ]; then
      errors+=("Mobile flutter test échoué (exit $rc)")
    else
      echo "STOP-VERIFY: flutter test OK ✓"
    fi
  fi
fi

# Résultat final
if [ ${#errors[@]} -gt 0 ]; then
  echo ""
  echo "STOP-VERIFY FAILED:"
  for e in "${errors[@]}"; do echo "  - $e"; done
  echo ""
  echo "Corrige les tests avant de terminer."
  exit 1
fi

exit 0
