#!/usr/bin/env python3
"""
Phase 1 Validation - File Structure Only
========================================

Validates Phase 1 deliverables by checking file existence and content
without requiring Python imports or database access.

Usage:
    python docs/qa/scripts/validate_phase1_files.py
"""

import os
import re
from pathlib import Path
from typing import List, Tuple


def color(text: str, code: str) -> str:
    """Add color to terminal output."""
    colors = {
        'green': '\033[92m',
        'red': '\033[91m',
        'yellow': '\033[93m',
        'blue': '\033[94m',
        'reset': '\033[0m'
    }
    return f"{colors.get(code, '')}{text}{colors['reset']}"


def check_file_exists(path: str, description: str) -> Tuple[bool, str]:
    """Check if a file exists."""
    # The script is in docs/qa/scripts/, so project root is 3 levels up
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent.parent.parent
    full_path = project_root / path
    
    if full_path.exists():
        size = full_path.stat().st_size
        return True, f"{description} ({size} bytes)"
    else:
        return False, f"{description}: NOT FOUND at {full_path}"


def check_file_contains(path: str, description: str, patterns: List[str]) -> Tuple[bool, str]:
    """Check if a file contains specific patterns."""
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent.parent.parent
    full_path = project_root / path
    
    if not full_path.exists():
        return False, f"{description}: File not found at {full_path}"
    
    try:
        content = full_path.read_text()
        missing = []
        for pattern in patterns:
            if pattern not in content:
                missing.append(pattern)
        
        if missing:
            return False, f"{description}: Missing patterns: {missing[:3]}"
        else:
            lines = len(content.splitlines())
            return True, f"{description} ({lines} lines, all patterns found)"
    except Exception as e:
        return False, f"{description}: Error reading file: {e}"


def main():
    print()
    print(color("=" * 70, 'blue'))
    print(color("  Phase 1 Foundation - File Structure Validation", 'blue'))
    print(color("=" * 70, 'blue'))
    print()
    
    results = []
    
    # Section 1: SQL Migrations
    print(color("📁 SQL Migrations", 'yellow'))
    
    checks = [
        ("packages/api/sql/009_daily_digest_table.sql", "Migration 009", 
         ["CREATE TABLE", "daily_digest", "JSONB", "items"]),
        ("packages/api/sql/010_digest_completions_table.sql", "Migration 010",
         ["CREATE TABLE", "digest_completions", "completed_at"]),
        ("packages/api/sql/011_extend_user_streaks.sql", "Migration 011",
         ["ALTER TABLE", "user_streaks", "closure_streak"]),
    ]
    
    for path, desc, patterns in checks:
        success, msg = check_file_contains(path, desc, patterns)
        results.append(success)
        symbol = "✅" if success else "❌"
        print(f"  {symbol} {msg}")
    print()
    
    # Section 2: Models
    print(color("🔧 Models", 'yellow'))
    
    model_checks = [
        ("packages/api/app/models/daily_digest.py", "DailyDigest model",
         ["class DailyDigest", "items", "user_id", "date", "JSONB"]),
        ("packages/api/app/models/digest_completion.py", "DigestCompletion model",
         ["class DigestCompletion", "user_id", "completed_at"]),
        ("packages/api/app/models/user.py", "UserStreak extension",
         ["closure_streak", "longest_closure_streak", "last_closure_date"]),
        ("packages/api/app/models/__init__.py", "Model exports",
         ["DailyDigest", "DigestCompletion"]),
    ]
    
    for path, desc, patterns in model_checks:
        success, msg = check_file_contains(path, desc, patterns)
        results.append(success)
        symbol = "✅" if success else "❌"
        print(f"  {symbol} {msg}")
    print()
    
    # Section 3: Services
    print(color("⚙️  Services", 'yellow'))
    
    service_checks = [
        ("packages/api/app/services/digest_selector.py", "DigestSelector service",
         ["class DigestSelector", "select_for_user", "MAX_PER_SOURCE", "MAX_PER_THEME"]),
        ("packages/api/app/services/digest_service.py", "DigestService",
         ["class DigestService", "get_or_create_digest", "apply_action", "complete_digest"]),
        ("packages/api/app/services/digest_selector_test.py", "Unit tests",
         ["def test_", "pytest", "DigestSelector"]),
    ]
    
    for path, desc, patterns in service_checks:
        success, msg = check_file_contains(path, desc, patterns)
        results.append(success)
        symbol = "✅" if success else "❌"
        print(f"  {symbol} {msg}")
    print()
    
    # Section 4: Jobs
    print(color("⏰ Background Jobs", 'yellow'))
    
    job_checks = [
        ("packages/api/app/jobs/digest_generation_job.py", "Generation job",
         ["run_digest_generation", "DigestGenerationJob", "batch"]),
        ("packages/api/app/jobs/__init__.py", "Job exports",
         ["run_digest_generation"]),
    ]
    
    for path, desc, patterns in job_checks:
        success, msg = check_file_contains(path, desc, patterns)
        results.append(success)
        symbol = "✅" if success else "❌"
        print(f"  {symbol} {msg}")
    print()
    
    # Section 5: API
    print(color("🌐 API Layer", 'yellow'))
    
    api_checks = [
        ("packages/api/app/routers/digest.py", "Digest router",
         ["@router.get", "@router.post", "/action", "/complete"]),
        ("packages/api/app/schemas/digest.py", "Pydantic schemas",
         ["class DigestResponse", "class DigestActionRequest", "DigestAction"]),
        ("packages/api/app/main.py", "Router registration",
         ["digest", "include_router"]),
        ("packages/api/app/routers/__init__.py", "Router exports",
         ["digest"]),
    ]
    
    for path, desc, patterns in api_checks:
        success, msg = check_file_contains(path, desc, patterns)
        results.append(success)
        symbol = "✅" if success else "❌"
        print(f"  {symbol} {msg}")
    print()
    
    # Section 6: Documentation
    print(color("📚 Documentation", 'yellow'))
    
    doc_checks = [
        (".planning/phases/01-foundation/01-01-SUMMARY.md", "Plan 01-01 Summary",
         ["Database Schema", "daily_digest", "digest_completions"]),
        (".planning/phases/01-foundation/01-02-SUMMARY.md", "Plan 01-02 Summary",
         ["DigestSelector", "diversity constraints", "unit tests"]),
        (".planning/phases/01-foundation/01-03-SUMMARY.md", "Plan 01-03 Summary",
         ["API Endpoints", "GET /api/digest", "apply_action"]),
        (".planning/phases/01-foundation/01-foundation-VERIFICATION.md", "Verification Report",
         ["PASSED", "must-haves verified"]),
    ]
    
    for path, desc, patterns in doc_checks:
        success, msg = check_file_contains(path, desc, patterns)
        results.append(success)
        symbol = "✅" if success else "❌"
        print(f"  {symbol} {msg}")
    print()
    
    # Summary
    passed = sum(results)
    total = len(results)
    
    print(color("=" * 70, 'blue'))
    if passed == total:
        print(color(f"  ✅ ALL CHECKS PASSED ({passed}/{total})", 'green'))
        print(color("=" * 70, 'blue'))
        print()
        print("Phase 1 Foundation file structure is complete!")
        print()
        print("To run Python import tests (requires venv):")
        print("  cd packages/api && source .venv/bin/activate")
        print("  python -c \"from app.models.daily_digest import DailyDigest; print('OK')\"")
        print()
        print("To run full test suite (requires database):")
        print("  pytest docs/qa/scripts/validate_phase1.py -v")
        return 0
    else:
        print(color(f"  ❌ SOME CHECKS FAILED ({passed}/{total})", 'red'))
        print(color("=" * 70, 'blue'))
        print()
        print("Some expected files or patterns are missing.")
        print("Review the errors above.")
        return 1


if __name__ == "__main__":
    exit(main())
