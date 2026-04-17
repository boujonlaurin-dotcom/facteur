#!/bin/bash
# Test : le hook session-start imprime WARN: et sort 0 quand l'install échoue.
# Isolation : HOME temporaire + stub curl qui exit 1 (simule offline).
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude-hooks/session-start.sh"

if [ ! -f "$HOOK" ]; then
  echo "FAIL: hook introuvable à $HOOK"
  exit 1
fi

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

mkdir -p "$SANDBOX/stubs"
cat > "$SANDBOX/stubs/curl" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$SANDBOX/stubs/curl"

OUTPUT=$(
  HOME="$SANDBOX" \
  PATH="$SANDBOX/stubs:/usr/bin:/bin" \
  bash "$HOOK" 2>&1
)
RC=$?

echo "--- Hook output ---"
echo "$OUTPUT"
echo "--- Exit code: $RC ---"

fail=0
if ! grep -q "WARN:" <<< "$OUTPUT"; then
  echo "FAIL: expected 'WARN:' in output"
  fail=1
fi
if [ "$RC" -ne 0 ]; then
  echo "FAIL: expected exit 0, got $RC"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS"
  exit 0
else
  exit 1
fi
