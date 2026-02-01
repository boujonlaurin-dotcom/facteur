---
phase: 01-foundation
plan: 02
subsystem: api
tags: [python, sqlalchemy, asyncio, pytest, digest, scoring, diversity]

# Dependency graph
requires:
  - phase: 01-foundation
    plan: 01
    provides: "DigestCompletion model and streak tracking infrastructure"
provides:
  - DigestSelector service with diversity constraints
  - Daily digest generation job
  - Unit tests for selection logic
  - Fallback mechanism to curated sources
  - Integration with existing ScoringEngine
affects:
  - 01-03 (API endpoints for digest)
  - 02-frontend (digest UI components)
  - 03-polish (digest refinement)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Service pattern: Async SQLAlchemy with dependency injection"
    - "Dataclass pattern: DigestItem for structured results"
    - "Batch processing: Concurrency limiting with asyncio.Semaphore"
    - "JSONB storage: DailyDigest.items for flexible article storage"

key-files:
  created:
    - packages/api/app/services/digest_selector.py
    - packages/api/app/services/digest_selector_test.py
    - packages/api/app/jobs/__init__.py
    - packages/api/app/jobs/digest_generation_job.py
  modified: []

key-decisions:
  - "Reused existing ScoringEngine without modifications (plan requirement)"
  - "Stored digest articles in JSONB column for flexibility"
  - "Implemented fallback to curated sources when user pool < 5"
  - "Enforced diversity constraints: max 2 per source, max 2 per theme"

patterns-established:
  - "DigestSelector: Service class with session injection, async methods"
  - "Diversity constraints: Counter-based tracking during selection"
  - "Batch job: Configurable batch_size and concurrency_limit"
  - "On-demand generation: Separate function for single-user generation"

# Metrics
duration: 4min
completed: 2026-02-01
---

# Phase 1 Plan 2: DigestSelector Service Summary

**DigestSelector service implementing 5-article daily digest with diversity constraints (max 2/source, 2/theme), curated fallback, and existing ScoringEngine reuse**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-01T19:40:05Z
- **Completed:** 2026-02-01T19:44:04Z
- **Tasks:** 3
- **Files created:** 4

## Accomplishments

- DigestSelector service with `select_for_user()` method returning exactly 5 articles
- Diversity constraints enforced: maximum 2 articles per source, maximum 2 per theme
- Fallback mechanism to curated sources when user content pool < 5 articles
- Full integration with existing ScoringEngine (no modifications needed)
- Comprehensive unit tests covering constraints, fallback, and edge cases
- Daily batch job with configurable concurrency and batch processing
- On-demand generation function for individual users
- Respects muted sources, themes, and topics from PersonalizationLayer

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DigestSelector service** - `bf839d7` (feat)
   - DigestItem dataclass for structured results
   - DigestSelector class with select_for_user() method
   - Diversity constraints implementation
   - Fallback to curated sources

2. **Task 2: Create unit tests** - `ec13505` (test)
   - TestDiversityConstraints: max 2 per source/theme
   - TestFallbackSources: fallback when pool < 5
   - TestReasonGeneration: French translations
   - TestScoringIntegration: error handling
   - TestIntegrationSelectForUser: end-to-end

3. **Task 3: Create daily generation job** - `44bfc2a` (feat)
   - DigestGenerationJob with batch processing
   - run_digest_generation() for scheduled execution
   - generate_digest_for_user() for on-demand
   - Concurrency limiting and statistics tracking

## Files Created

- `packages/api/app/services/digest_selector.py` (504 lines) - Core selection service with diversity algorithms
- `packages/api/app/services/digest_selector_test.py` (617 lines) - Comprehensive unit test suite
- `packages/api/app/jobs/__init__.py` (20 lines) - Job package exports
- `packages/api/app/jobs/digest_generation_job.py` (427 lines) - Batch generation job with concurrency control

## Decisions Made

1. **Diversity Algorithm**: Implemented greedy selection with counters - scans by score descending and applies constraints. Simple, fast, deterministic.

2. **Fallback Priority**: User sources first, then curated sources filtered by user interests. Ensures personalization even in fallback.

3. **JSONB Storage**: Used DailyDigest model's existing JSONB items column instead of separate junction table. Simpler, faster queries, sufficient for 5 items.

4. **Scoring Reuse**: Called existing ScoringEngine via RecommendationService.scoring_engine.compute_score(). No changes to scoring layers, context, or weights.

5. **Error Handling**: Graceful degradation - returns empty list on errors, 0.0 score for failed scoring, continues with partial results.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - all components existed as expected (DailyDigest model, ScoringEngine, models).

## Next Phase Readiness

- ✅ DigestSelector ready for API endpoint integration (01-03)
- ✅ Batch job ready for scheduler configuration (01-03)
- ✅ DailyDigest persistence ready for read operations (01-03)
- ✅ Tests passing foundation for future regression prevention

**Blockers for next phase:** None

**Concerns:** None

---
*Phase: 01-foundation*
*Completed: 2026-02-01*
