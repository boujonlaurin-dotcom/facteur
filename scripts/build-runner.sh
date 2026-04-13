#!/usr/bin/env bash
# Regenerate Freezed + json_serializable code after modifying dart model files.
# Usage: ./scripts/build-runner.sh
set -euo pipefail
export PATH="$PATH:/opt/flutter/bin"
cd "$(dirname "$0")/../apps/mobile"
dart run build_runner build --delete-conflicting-outputs 2>&1 | grep -v "^   Woah\|superuser\|We strongly\|^  /"
echo "Done — check git diff for changes."
