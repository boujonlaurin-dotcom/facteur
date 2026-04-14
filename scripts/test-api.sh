#!/usr/bin/env bash
# Run backend (API) tests.
# Usage:
#   ./scripts/test-api.sh                    # all tests
#   ./scripts/test-api.sh tests/editorial/   # specific folder
#   ./scripts/test-api.sh tests/editorial/test_pipeline.py -k TestPerspectiveCount
set -euo pipefail
cd "$(dirname "$0")/../packages/api"
PYTHONPATH="$(pwd)" .venv/bin/pytest "${@:-tests/}" -v
