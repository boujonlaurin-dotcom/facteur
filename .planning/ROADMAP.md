# Roadmap: Facteur — Digest Production Fixes (v1.0.1)

**Project:** Facteur  
**Milestone:** v1.0.1 — Critical Production Fixes  
**Goal:** Fix 2 critical bugs blocking digest production release  
**Estimated Duration:** ~4-6 hours  
**Last Updated:** 2026-02-07

---

## Success Metrics

### Phase Success Criteria

- **Technical**: Code passes all tests, no regressions
- **Functional**: 
  - Digest generates automatically at 8am daily
  - Digest contains articles from at least 3 different sources
  - No single source contributes more than 2 articles
- **Quality**: Existing digest features continue working

---

## Phase Overview

| # | Phase | Goal | Key Deliverables | Est. Hours |
|---|-------|------|------------------|------------|
| 1 | Production Fixes | Fix scheduler and diversity bugs | 2 bug fixes, 2 verifications | ~4-6h |

**Total:** ~4-6h

---

## Phase 1: Production Fixes

**Goal:** Fix the 2 critical bugs identified in production hand-off

### Requirements Addressed

- FIX-01 (Job scheduler)
- FIX-02 (Source diversity)
- TEST-01 (Scheduler verification)
- TEST-02 (Diversity verification)

### Success Criteria

1. `run_digest_generation` job is scheduled in scheduler.py
2. Job triggers at 8:00 Europe/Paris daily
3. Digest articles come from at least 3 different sources
4. No single source has more than 2 articles in digest
5. Decay factor of 0.70 is applied correctly
6. Existing digest functionality continues working

### Technical Approach

#### Bug 1: Job Scheduler
```
File: packages/api/app/workers/scheduler.py

Action:
- Import run_digest_generation from app.jobs.digest_generation_job
- Add cron job: 0 8 * * * (8am daily, Europe/Paris timezone)
- Same pattern as existing top_3_generation job
```

#### Bug 2: Source Diversity
```
File: packages/api/app/services/digest_selector.py

Action:
- Modify _select_with_diversity() method
- Track source_count during selection
- Apply decay: score * (0.70 ^ source_count)
- Ensure min 3 sources constraint
```

### Plans

- [ ] **01-01**: Add digest generation job to scheduler — Wave 1
- [ ] **01-02**: Implement source diversity with decay factor — Wave 1
- [ ] **01-03**: Verify fixes (scheduler + diversity tests) — Wave 2

**Status:** ⚪ Not Started  
**Dependencies:** None (bug fixes on existing code)

**Wave Structure:**
| Wave | Plans | Dependencies |
|------|-------|--------------|
| 1 | 01-01, 01-02 | None (can run in parallel) |
| 2 | 01-03 | 01-01, 01-02 (verification) |

---

## Requirement Mapping Summary

| Requirement | Phase | Plan | Status |
|-------------|-------|------|--------|
| FIX-01 | Phase 1 | 01-01 | Pending |
| FIX-02 | Phase 1 | 01-02 | Pending |
| TEST-01 | Phase 1 | 01-03 | Pending |
| TEST-02 | Phase 1 | 01-03 | Pending |

**100% Coverage Achieved** ✓

---

## Execution Flow

```
Wave 1 (Parallel):
  └── Plans: 01-01 (scheduler), 01-02 (diversity)

Wave 2 (Sequential):
  └── Plan: 01-03 (verification)
```

---

## Key Decisions Logged

| Decision | Rationale | Phase |
|----------|-----------|-------|
| Decay factor 0.70 | Matches existing feed algorithm for consistency | 1 |
| Min 3 sources | Ensures meaningful diversity in 5-article digest | 1 |
| 8am Europe/Paris | Matches Top 3 schedule, user expectation | 1 |

---

*Roadmap created: 2026-02-07*  
*Next step: Run `/gsd-plan-phase 1` to create detailed plans*
