#!/bin/bash
# Verification script for Auth 403 Email Confirmation flow
# Self-contained: activates venv and runs the auth verification tests

set -e
cd "$(dirname "$0")/.."

echo "🔐 Auth Flow Verification"
echo "========================="

# Activate virtual environment
source venv/bin/activate

# Run auth verification tests
python scripts/verify_auth.py

echo ""
echo "✅ Auth verification complete"
