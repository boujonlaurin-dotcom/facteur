#!/bin/bash
#
# Phase 1 Foundation Validation - Quick Command
# =============================================
#
# Usage:
#   ./validate_phase1.sh              # Run full validation
#   ./validate_phase1.sh --quick      # Run quick checks only
#   ./validate_phase1.sh --db-only    # Run database checks only
#
# Or as a one-liner from project root:
#   cd packages/api && python -m pytest ../../docs/qa/scripts/validate_phase1.py -v --tb=short
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
API_DIR="$PROJECT_ROOT/packages/api"
VALIDATION_SCRIPT="$SCRIPT_DIR/validate_phase1.py"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Phase 1 Foundation Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if we're in the right directory
if [ ! -d "$API_DIR" ]; then
    echo -e "${RED}Error: Could not find packages/api directory${NC}"
    echo "Make sure you're running this from the project root"
    exit 1
fi

cd "$API_DIR"

# Check if Python environment is available
if [ ! -d ".venv" ] && [ ! -d "venv" ]; then
    echo -e "${YELLOW}Warning: No virtual environment found${NC}"
fi

# Parse arguments
MODE="${1:-full}"

run_quick_checks() {
    echo -e "${YELLOW}Running quick import checks...${NC}"
    echo ""
    
    # Test model imports
    python -c "from app.models.daily_digest import DailyDigest; print('✅ DailyDigest model OK')" || exit 1
    python -c "from app.models.digest_completion import DigestCompletion; print('✅ DigestCompletion model OK')" || exit 1
    python -c "from app.models.user import UserStreak; print('✅ UserStreak model OK')" || exit 1
    
    # Test service imports
    python -c "from app.services.digest_selector import DigestSelector; print('✅ DigestSelector service OK')" || exit 1
    python -c "from app.services.digest_service import DigestService; print('✅ DigestService OK')" || exit 1
    
    # Test job imports
    python -c "from app.jobs.digest_generation_job import run_digest_generation; print('✅ Generation job OK')" || exit 1
    
    # Test router imports
    python -c "from app.routers import digest; print('✅ Digest router OK')" || exit 1
    python -c "from app.routers.digest import router; print('✅ Router endpoints OK')" || exit 1
    
    # Test schema imports
    python -c "from app.schemas.digest import DigestResponse; print('✅ Pydantic schemas OK')" || exit 1
    
    echo ""
    echo -e "${GREEN}All quick checks passed! ✅${NC}"
}

run_db_checks() {
    echo -e "${YELLOW}Running database validation...${NC}"
    echo ""
    
    # Check if pytest is available
    if ! python -c "import pytest" 2>/dev/null; then
        echo -e "${RED}Error: pytest not installed${NC}"
        echo "Install with: pip install pytest pytest-asyncio"
        exit 1
    fi
    
    # Run database-related tests only
    python -m pytest "$VALIDATION_SCRIPT" -v -k "test_001 or test_002 or test_003 or test_004 or test_021 or test_022" --tb=short
}

run_full_validation() {
    echo -e "${YELLOW}Running full validation suite...${NC}"
    echo ""
    
    # Run all tests
    python -m pytest "$VALIDATION_SCRIPT" -v --tb=short 2>&1 | tee /tmp/phase1_validation.log
    
    EXIT_CODE=${PIPESTATUS[0]}
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}  Phase 1 Validation: ALL TESTS PASSED ✅${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "Summary:"
        grep -E "(PASSED|FAILED|ERROR)" /tmp/phase1_validation.log | tail -20
        echo ""
        echo -e "${GREEN}Phase 1 Foundation is ready for Phase 2 (Frontend)!${NC}"
    else
        echo -e "${RED}  Phase 1 Validation: SOME TESTS FAILED ❌${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "Failed tests:"
        grep -E "FAILED|ERROR" /tmp/phase1_validation.log || echo "(See log above)"
        echo ""
        echo "Full log: /tmp/phase1_validation.log"
    fi
    
    exit $EXIT_CODE
}

case "$MODE" in
    --quick|-q)
        run_quick_checks
        ;;
    --db-only|--db|-d)
        run_db_checks
        ;;
    --full|-f|"")
        run_full_validation
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --quick, -q       Run quick import checks only"
        echo "  --db-only, -d     Run database validation only"
        echo "  --full, -f        Run full validation suite (default)"
        echo "  --help, -h        Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                    # Full validation"
        echo "  $0 --quick            # Quick checks"
        echo "  $0 --db-only          # Database only"
        exit 0
        ;;
    *)
        echo -e "${RED}Unknown option: $MODE${NC}"
        echo "Run '$0 --help' for usage"
        exit 1
        ;;
esac
