# Phase 1 Foundation Validation Scripts

This directory contains validation scripts for Phase 1 (Foundation) of the Epic 10 Digest Central implementation.

## Quick Start

### File Structure Validation (No dependencies)
Checks that all files exist and contain expected code patterns:

```bash
python docs/qa/scripts/validate_phase1_files.py
```

### Quick Import Validation (Requires venv)
Validates Python imports work correctly:

```bash
cd packages/api && source .venv/bin/activate && python ../../docs/qa/scripts/quick_validate_phase1.py
```

### Full Test Suite (Requires database)
Comprehensive pytest-based validation:

```bash
cd packages/api && source .venv/bin/activate && python -m pytest ../../docs/qa/scripts/validate_phase1.py -v --tb=short
```

---

## One-Liner Commands

```bash
# File structure only (fastest, no dependencies)
python docs/qa/scripts/validate_phase1_files.py

# Quick import check (needs venv)
cd packages/api && source .venv/bin/activate && python ../../docs/qa/scripts/quick_validate_phase1.py

# Full test suite (needs venv + database)
cd packages/api && source .venv/bin/activate && python -m pytest ../../docs/qa/scripts/validate_phase1.py -v

# API live testing (needs running server)
./docs/qa/scripts/validate_phase1_api.sh http://localhost:8000 YOUR_AUTH_TOKEN

# Staging APK release gate before promoting main to production
FACTEUR_AUTH_TOKEN='Bearer eyJ...' \
CONTENT_IDS='uuid-1,uuid-2' \
python docs/qa/scripts/verify_staging_apk_release.py
```

---

## Scripts Overview

### 1. `validate_phase1_files.py` ⭐ **RECOMMENDED**
- ✅ No dependencies required
- ✅ Validates file structure and content
- ✅ Checks for required code patterns
- ✅ Verifies documentation exists
- ⚡ Fast execution (< 1 second)

### 2. `quick_validate_phase1.py`
- ✅ Tests Python imports
- ✅ Validates model attributes
- ✅ Checks service methods
- ⚠️ Requires virtual environment activated

### 3. `validate_phase1.py` (pytest)
- ✅ Database table structure
- ✅ Model instantiation
- ✅ CRUD operations
- ✅ Integration tests
- ⚠️ Requires database connection

### 4. `validate_phase1_api.sh`
- ✅ Live API endpoint testing
- ✅ Authentication validation
- ✅ Response format checking
- ⚠️ Requires running API server

### 5. `validate_phase1.sh`
- Shell wrapper with multiple modes
- Options: `--quick`, `--db-only`, `--full`

### 6. `verify_staging_apk_release.py`
- Checks the latest `build-apk.yml` run uses the staging API, `SENTRY_ENVIRONMENT=staging`, and `UPDATE_CHANNEL=beta`
- Verifies staging/prod health endpoints report the expected environments
- Compares `GET /api/contents/{id}/perspectives` on staging vs production for `CONTENT_IDS` or IDs discovered from `/api/digest`
- Optionally inspects `content_deep_recommendations` when `DATABASE_URL` is set

---

## What Gets Validated

Phase 1 delivers:

- [x] **3 SQL Migrations** (168 lines total)
  - 009_daily_digest_table.sql (56 lines)
  - 010_digest_completions_table.sql (73 lines)
  - 011_extend_user_streaks.sql (39 lines)

- [x] **2 New Models** (137 lines total)
  - DailyDigest (67 lines)
  - DigestCompletion (70 lines)

- [x] **Extended Model** (closure tracking fields)
  - UserStreak with closure_streak, longest_closure_streak, last_closure_date

- [x] **DigestSelector Service** (504 lines + 617 lines tests)
  - Diversity constraints (max 2 per source/theme)
  - Fallback to curated sources
  - 617 lines of unit test coverage

- [x] **DigestService** (526 lines)
  - get_or_create_digest()
  - apply_action() with Personalization integration
  - complete_digest() with streak updates

- [x] **Generation Job** (424 lines)
  - Batch processing with concurrency control
  - Daily scheduled execution

- [x] **4 API Endpoints** (240 lines router + 133 lines schemas)
  - GET /api/digest
  - POST /api/digest/{id}/action
  - POST /api/digest/{id}/complete
  - POST /api/digest/generate

- [x] **Documentation** (879 lines)
  - 01-01-SUMMARY.md (252 lines)
  - 01-02-SUMMARY.md (143 lines)
  - 01-03-SUMMARY.md (267 lines)
  - 01-foundation-VERIFICATION.md (217 lines)

**Total: ~2,800+ lines of production-ready code**

---

## Expected Output

### validate_phase1_files.py
```
======================================================================
  Phase 1 Foundation - File Structure Validation
======================================================================

📁 SQL Migrations
  ✅ Migration 009 (56 lines, all patterns found)
  ✅ Migration 010 (73 lines, all patterns found)
  ✅ Migration 011 (39 lines, all patterns found)

🔧 Models
  ✅ DailyDigest model (67 lines, all patterns found)
  ✅ DigestCompletion model (70 lines, all patterns found)
  ...

======================================================================
  ✅ ALL CHECKS PASSED (20/20)
======================================================================
```

---

## Verification Report

The official gsd-verifier report is at:
`.planning/phases/01-foundation/01-foundation-VERIFICATION.md`

**Status:** ✅ **PASSED** (14/14 must-haves verified)

---

## Troubleshooting

### Import Errors
If imports fail:
```bash
cd packages/api
source .venv/bin/activate  # or: source venv/bin/activate
pip install -r requirements.txt
```

### Database Connection
For database tests:
1. Ensure PostgreSQL is running
2. Check `DATABASE_URL` in `.env`
3. Run migrations if needed

### API Server Not Running
For API tests, start the server first:
```bash
cd packages/api
python -m app.main
```

---

## Success Criteria

All Phase 1 success criteria met:

1. ✅ API endpoints return correct digest data (5 articles)
2. ✅ Digest generation respects diversity constraints
3. ✅ Actions (read/save/not_interested) update database correctly
4. ✅ Completion tracking works end-to-end
5. ✅ Existing feed API remains untouched (no regression)

---

*Created: 2026-02-01*
