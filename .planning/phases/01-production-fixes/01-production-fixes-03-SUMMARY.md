---
phase: 01-production-fixes
plan: 03
subsystem: api

# Dependency graph
requires:
  - phase: 01-production-fixes-01
    provides: Digest generation job in scheduler
  - phase: 01-production-fixes-02
    provides: Decay-based diversity algorithm
provides:
  - "Scheduler verification tests (7 tests)"
  - "Diversity algorithm tests (6 tests) with ÷2 penalty"
  - "Breakdown transparency: 'Diversité revue de presse' visible to user"
affects:
  - digest_selector.py (diversity logic changed from ×0.70 to ÷2)
  - scoring_config.py (new DIGEST_DIVERSITY_DIVISOR constant)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Diversity ÷2: score / 2 for duplicate source in digest"
    - "Breakdown injection: penalty visible in 'Pourquoi cet article?' sheet"
    - "Centralized config: all algo constants in ScoringWeights"

key-files:
  created:
    - "packages/api/tests/workers/test_scheduler.py"
  modified:
    - "packages/api/app/services/digest_selector.py"
    - "packages/api/app/services/digest_selector_test.py"
    - "packages/api/app/services/recommendation/scoring_config.py"

key-decisions:
  - "÷2 instead of ×0.70: at 150-260 pts range, multiplicative decay left duplicates too high"
  - "÷2 instead of fixed penalty: proportional to score, works at any score range"
  - "Breakdown transparency (règle d'or): all algo rules visible to user"
  - "No frontend changes needed: breakdown auto-rendered by existing sheet"

patterns-established:
  - "Diversity penalty: proportional (÷N) not fixed (-X pts) for high-score algorithms"
  - "Algo transparency: every bonus/malus must appear in DigestScoreBreakdown"
  - "Centralized constants: ScoringWeights is source of truth for all tunable values"

# Metrics
duration: ~30min (including user discussion and design iteration)
completed: 2026-02-09
---

# Phase 1 Plan 3: Verify Fixes + Diversity Revue de Presse

**Scheduler verification tests (7), diversity ÷2 algorithm tests (6), and transparency breakdown — all 31 tests pass.**

## Performance

- **Duration:** ~30 min (including design discussion)
- **Completed:** 2026-02-09
- **Tasks:** 3 (2 auto + 1 checkpoint)
- **Files modified:** 4

## Accomplishments

### Scheduler Tests (TEST-01)
- 7 tests verifying daily_digest job exists in scheduler
- Confirms 8am Europe/Paris timezone via CronTrigger
- Verifies job function is `run_digest_generation`

### Diversity Algorithm Change (TEST-02 + user feedback)
- **Changed from ×0.70 to ÷2** based on user testing feedback
- Original ×0.70 was insufficient: 220 pts × 0.70 = 154 pts (still above alternatives)
- New ÷2: 220 pts → 110 pts — alternatives at 150 pts now win
- `DIGEST_DIVERSITY_DIVISOR = 2` centralized in `ScoringWeights`

### Transparency (règle d'or)
- "Diversité revue de presse" line injected into `DigestScoreBreakdown`
- Automatically rendered in "Pourquoi cet article ?" sheet (red down-arrow)
- No frontend changes needed — existing breakdown rendering handles it

### Test Coverage
- 6 new diversity tests in `TestDiversityRevueDePresse`:
  - `test_diversity_halves_score_for_duplicate_source` (220 → 110)
  - `test_minimum_three_sources_enforced`
  - `test_le_monde_only_user_gets_diversity`
  - `test_diversity_penalty_visible_in_breakdown` (règle d'or)
  - `test_diversity_penalty_relegate_duplicate_below_alternative` (real-world scenario)
  - `test_no_single_source_exceeds_two_articles`

## Task Commits

1. **Task 1: Scheduler verification tests** — `10fab13` (test)
2. **Task 2: Diversity verification tests** — `0da440b` (test)
3. **Task 3: Diversity ÷2 + transparency + checkpoint approval** — `04040df` (fix)

## Files Created/Modified

- `packages/api/tests/workers/test_scheduler.py` — Created: 7 scheduler tests
- `packages/api/app/services/digest_selector.py` — Modified: ÷2 diversity + breakdown injection
- `packages/api/app/services/digest_selector_test.py` — Modified: 6 diversity tests
- `packages/api/app/services/recommendation/scoring_config.py` — Modified: `DIGEST_DIVERSITY_DIVISOR = 2`

## Decisions Made

1. **÷2 instead of ×0.70**: User feedback — ×0.70 left duplicates too high at typical top-digest scores
2. **÷2 instead of -10 fixed**: First iteration failed — 150 pts - 10 = 140 pts, still dominant
3. **Règle d'or**: Every algo rule must be visible to the user in the personalization sheet
4. **Centralized in ScoringWeights**: Single source of truth for tunable algo constants

## Deviations from Plan

- **Design iteration**: Original plan assumed ×0.70 decay. User testing revealed it was insufficient.
  First attempt used -10 fixed penalty (also insufficient at 150+ pts).
  Final solution: ÷2 proportional penalty — approved by user after analysis.
- **Additional tests**: Added 2 extra tests (breakdown visibility, real-world relegation scenario)
  beyond what was planned, to cover the new ÷2 logic and règle d'or.

## Issues Encountered

None after final implementation.

---
*Phase: 01-production-fixes*
*Completed: 2026-02-09*
