#!/bin/bash
# Verification script for Story 4.1d - ML Classification Service
# Tests the ClassificationService implementation

set -e  # Exit on error

echo "🧪 Verifying ML Classification Service (Story 4.1d Part 1/3)"
echo "=============================================================="
echo ""

# Check we're in the right directory
if [ ! -f "app/services/ml/classification_service.py" ]; then
    echo "❌ Error: Must run from packages/api directory"
    exit 1
fi

# Activate virtual environment
if [ ! -d "venv" ]; then
    echo "❌ Error: Virtual environment not found. Run: python -m venv venv"
    exit 1
fi

source venv/bin/activate

echo "✅ Virtual environment activated"
echo ""

# Run unit tests (fast, mocked)
echo "📋 Running unit tests (mocked, no model download)..."
pytest tests/ml/test_classification_service.py -v --tb=short

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ All unit tests passed!"
    echo ""
else
    echo ""
    echo "❌ Unit tests failed"
    exit 1
fi

# Test service import
echo "📦 Testing ClassificationService import..."
python -c "from app.services.ml.classification_service import ClassificationService; print('✅ Import successful')"
echo ""

# Optional: Test with real model if ML_ENABLED is set
if [ "$ML_ENABLED" = "true" ]; then
    echo "🧠 ML_ENABLED=true detected, testing with real model..."
    echo "⏳ This will download ~558MB on first run..."
    echo ""
    python scripts/test_ml_local.py
else
    echo "💡 To test with the real model, run:"
    echo "   ML_ENABLED=true ./scripts/verify_ml_classification.sh"
    echo ""
fi

echo "=============================================================="
echo "✅ ML Classification Service verification complete!"
echo ""
echo "Summary:"
echo "  - Unit tests: ✅ Passed"
echo "  - Service import: ✅ Working"
if [ "$ML_ENABLED" = "true" ]; then
    echo "  - Real model: ✅ Tested"
else
    echo "  - Real model: ⏭️  Skipped (set ML_ENABLED=true to test)"
fi
echo ""
