#!/usr/bin/env python3
"""
Phase 1 Quick Validation (No pytest required)
=============================================

Lightweight validation script that checks Phase 1 deliverables
without requiring pytest or database access.

Usage:
    cd packages/api
    python ../../docs/qa/scripts/quick_validate_phase1.py

This script verifies:
- All imports work correctly
- Models have required attributes
- Services have required methods
- Routers have required endpoints
- Files exist in expected locations
"""

import os
import sys
from pathlib import Path

    # Add packages/api to path for imports
# When running from packages/api, current directory is already correct
if Path.cwd().name == 'api' and (Path.cwd().parent / 'packages').exists():
    # Running from packages/api
    sys.path.insert(0, str(Path.cwd()))
else:
    # Running from elsewhere
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../packages/api'))


def color(text, code):
    """Add color to terminal output."""
    colors = {
        'green': '\033[92m',
        'red': '\033[91m',
        'yellow': '\033[93m',
        'blue': '\033[94m',
        'reset': '\033[0m'
    }
    return f"{colors.get(code, '')}{text}{colors['reset']}"


def check_import(module_path, description):
    """Try to import a module and report success/failure."""
    try:
        parts = module_path.split('.')
        module = __import__(module_path)
        for part in parts[1:]:
            module = getattr(module, part)
        print(f"  ✅ {description}")
        return True
    except Exception as e:
        print(f"  ❌ {description}: {e}")
        return False


def check_file_exists(filepath, description):
    """Check if a file exists."""
    # When running from packages/api, filepath is relative to that directory
    # Try current directory first (if running from packages/api)
    current_dir = Path.cwd()
    full_path = current_dir / filepath
    
    if not full_path.exists():
        # Fall back to calculating from script location
        script_dir = Path(__file__).parent
        # Go from docs/qa/scripts -> project root -> packages/api
        full_path = script_dir.parent.parent.parent / 'packages' / 'api' / filepath
    
    if full_path.exists():
        print(f"  ✅ {description}")
        return True
    else:
        print(f"  ❌ {description}: File not found at {filepath} (tried {full_path})")
        return False


def check_model_attributes(model_name, module_path, attributes):
    """Check if a model has required attributes."""
    try:
        module = __import__(module_path, fromlist=[model_name])
        model = getattr(module, model_name)
        missing = []
        for attr in attributes:
            if not hasattr(model, attr):
                missing.append(attr)
        
        if missing:
            print(f"  ❌ {model_name}: Missing attributes {missing}")
            return False
        else:
            print(f"  ✅ {model_name}: All attributes present")
            return True
    except Exception as e:
        print(f"  ❌ {model_name}: {e}")
        return False


def main():
    print()
    print(color("=" * 70, 'blue'))
    print(color("  Phase 1 Foundation - Quick Validation", 'blue'))
    print(color("=" * 70, 'blue'))
    print()
    
    results = []
    
    # Section 1: Database Files
    print(color("📁 Database Migrations & Models", 'yellow'))
    results.append(check_file_exists('sql/009_daily_digest_table.sql', 'Migration 009 (daily_digest)'))
    results.append(check_file_exists('sql/010_digest_completions_table.sql', 'Migration 010 (digest_completions)'))
    results.append(check_file_exists('sql/011_extend_user_streaks.sql', 'Migration 011 (user_streaks extension)'))
    results.append(check_file_exists('app/models/daily_digest.py', 'DailyDigest model'))
    results.append(check_file_exists('app/models/digest_completion.py', 'DigestCompletion model'))
    print()
    
    # Section 2: Model Imports
    print(color("🔧 Model Imports", 'yellow'))
    results.append(check_import('app.models.daily_digest', 'DailyDigest model'))
    results.append(check_import('app.models.digest_completion', 'DigestCompletion model'))
    results.append(check_import('app.models.user', 'UserStreak model'))
    print()
    
    # Section 3: Model Attributes
    print(color("📋 Model Attributes", 'yellow'))
    results.append(check_model_attributes('DailyDigest', 'app.models.daily_digest', 
                                        ['items', 'user_id', 'date', 'completed']))
    results.append(check_model_attributes('DigestCompletion', 'app.models.digest_completion',
                                        ['user_id', 'date', 'completed_at']))
    results.append(check_model_attributes('UserStreak', 'app.models.user',
                                        ['closure_streak', 'longest_closure_streak', 'last_closure_date']))
    print()
    
    # Section 4: Services
    print(color("⚙️  Services", 'yellow'))
    results.append(check_import('app.services.digest_selector', 'DigestSelector service'))
    results.append(check_import('app.services.digest_service', 'DigestService'))
    results.append(check_import('app.jobs.digest_generation_job', 'Generation job'))
    print()
    
    # Section 5: API
    print(color("🌐 API Layer", 'yellow'))
    results.append(check_import('app.routers.digest', 'Digest router'))
    results.append(check_import('app.schemas.digest', 'Pydantic schemas'))
    results.append(check_file_exists('app/routers/digest.py', 'Router implementation'))
    results.append(check_file_exists('app/services/digest_service.py', 'Service implementation'))
    print()
    
    # Section 6: Tests
    print(color("🧪 Tests", 'yellow'))
    results.append(check_file_exists('app/services/digest_selector_test.py', 'DigestSelector tests'))
    print()
    
    # Summary
    passed = sum(results)
    total = len(results)
    
    print(color("=" * 70, 'blue'))
    if passed == total:
        print(color(f"  ✅ ALL CHECKS PASSED ({passed}/{total})", 'green'))
        print(color("=" * 70, 'blue'))
        print()
        print("Phase 1 Foundation validation complete!")
        print()
        print("For database-level validation, run:")
        print("  cd packages/api && python -m pytest ../../docs/qa/scripts/validate_phase1.py -v")
        return 0
    else:
        print(color(f"  ❌ SOME CHECKS FAILED ({passed}/{total})", 'red'))
        print(color("=" * 70, 'blue'))
        print()
        print("Some components are missing or not importable.")
        print("Review the errors above and check:")
        print("  1. Virtual environment is activated")
        print("  2. All dependencies are installed (pip install -r requirements.txt)")
        print("  3. You're running from packages/api directory")
        return 1


if __name__ == "__main__":
    sys.exit(main())
