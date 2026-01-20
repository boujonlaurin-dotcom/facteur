#!/bin/bash
# Helper script to apply migrations and run verification
# This can be run manually if agents encounter shell integration issues

set -e

cd "$(dirname "$0")/.."

echo "====================================================="
echo " Story 4.1c Part 1/3 - Migration Application"
echo "====================================================="
echo ""

# Activate virtual environment
echo "Step 1: Activating virtual environment..."
source venv/bin/activate

# Apply migrations
echo ""
echo "Step 2: Applying migrations with alembic..."
alembic upgrade head

# Run verification script
echo ""
echo "Step 3: Running verification script..."
python scripts/test_taxonomy_schema.py

echo ""
echo "====================================================="
echo " Migration complete!"
echo "====================================================="
