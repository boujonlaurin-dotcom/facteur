#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
API_BASE_URL="${API_BASE_URL:-https://facteur-production.up.railway.app}"
RUN_FLUTTER_BUILD="${RUN_FLUTTER_BUILD:-0}"

echo "== Facteur: verify_release =="
echo "Root: ${ROOT_DIR}"
echo "API:  ${API_BASE_URL}"

check_http() {
  local url="$1"
  local code
  code="$(curl -s -o /dev/null -w "%{http_code}" "$url")"
  if [[ "$code" != "200" ]]; then
    echo "FAIL: $url -> $code"
    exit 1
  fi
  echo "OK:   $url -> $code"
}

check_http "${API_BASE_URL}/api/health"
check_http "${API_BASE_URL}/api/health/ready"

if [[ -n "${DATABASE_URL:-}" ]]; then
  echo "Checking Alembic status..."
  pushd "${ROOT_DIR}/packages/api" >/dev/null
  if [[ -d "venv" ]]; then
    # shellcheck disable=SC1091
    source "venv/bin/activate"
  fi
  alembic current
  alembic heads
  popd >/dev/null
else
  echo "SKIP: DATABASE_URL not set (alembic check skipped)"
fi

if [[ "${RUN_FLUTTER_BUILD}" == "1" ]]; then
  echo "Running flutter build apk --release..."
  pushd "${ROOT_DIR}/apps/mobile" >/dev/null
  flutter build apk --release
  popd >/dev/null
else
  echo "SKIP: RUN_FLUTTER_BUILD=1 to build APK"
fi
