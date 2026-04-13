#!/usr/bin/env bash
# Run Flutter mobile tests.
# Usage:
#   ./scripts/test-mobile.sh                                        # all tests
#   ./scripts/test-mobile.sh test/features/digest/                  # specific folder
#   ./scripts/test-mobile.sh test/features/digest/digest_topic_representative_id_test.dart
set -euo pipefail
export PATH="$PATH:/opt/flutter/bin"
cd "$(dirname "$0")/../apps/mobile"
flutter test "${@:-test/}" --reporter compact 2>&1 | grep -v "^   Woah\|superuser\|We strongly\|^  /"
