#!/usr/bin/env bash
set -euo pipefail

# Storage Health Check for Facteur (Supabase PostgreSQL)
# Exit codes: 0 = OK (<400MB), 1 = Warning (400-450MB), 2 = Critical (>450MB)
#
# Usage: DATABASE_URL="postgresql://..." bash verify_storage_health.sh

if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "ERROR: DATABASE_URL not set"
    exit 2
fi

LIMIT_MB=500

# Query database size
SIZE_MB=$(psql "${DATABASE_URL}" -t -A -c \
    "SELECT pg_database_size(current_database()) / 1024 / 1024;")

PERCENT=$((SIZE_MB * 100 / LIMIT_MB))

echo "Storage: ${SIZE_MB} MB / ${LIMIT_MB} MB (${PERCENT}%)"

# Article age breakdown
echo ""
echo "Articles by age:"
psql "${DATABASE_URL}" -c \
    "SELECT
        COUNT(*) FILTER (WHERE published_at >= NOW() - INTERVAL '14 days') AS recent_14d,
        COUNT(*) FILTER (WHERE published_at < NOW() - INTERVAL '14 days') AS older_14d,
        COUNT(*) AS total
     FROM contents;"

# Exit code based on thresholds
if [[ $SIZE_MB -gt 450 ]]; then
    echo "CRITICAL: Storage above 450 MB"
    exit 2
elif [[ $SIZE_MB -gt 400 ]]; then
    echo "WARNING: Storage above 400 MB"
    exit 1
else
    echo "OK: Storage healthy"
    exit 0
fi
