#!/usr/bin/env bash
# Run flutter analyze on the mobile app.
# Usage: ./scripts/flutter-analyze.sh
set -euo pipefail
export PATH="$PATH:/opt/flutter/bin"
cd "$(dirname "$0")/../apps/mobile"
flutter analyze 2>&1 | grep -v "^   Woah\|superuser\|We strongly\|^  /"
