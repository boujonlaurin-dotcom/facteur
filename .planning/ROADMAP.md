# Roadmap: Facteur — Digest Production Fixes & Polish

**Project:** Facteur  
**Milestone:** v1.1 — Digest Production Fixes + Polish  
**Goal:** Fix production bugs, add push notifications, analytics, tests, and performance optimization  
**Estimated Duration:** ~12-16 hours  
**Last Updated:** 2026-02-08

---

## Success Metrics

### Phase Success Criteria

- **Technical**: Code passes all tests, no regressions
- **Functional**: 
  - Digest generates automatically at 8am daily
  - Digest contains articles from at least 3 different sources
  - No single source contributes more than 2 articles
  - Daily push notification at 8am (opt-in)
  - Digest analytics tracked (unified content_interaction events across surfaces)
- **Quality**: Existing digest features continue working, performance improved

---

## Phase Overview

| # | Phase | Goal | Key Deliverables | Est. Hours |
|---|-------|------|------------------|------------|
| 1 | Production Fixes | Fix scheduler and diversity bugs | 2 bug fixes, 2 verifications | ~4-6h |
| 3 | Polish | Push notifications, unified analytics, tests, performance | 5 plans across 3 waves | ~8-12h |

**Total:** ~12-16h

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

- [x] **01-01**: Add digest generation job to scheduler — Wave 1
- [x] **01-02**: Implement source diversity with decay factor — Wave 1
- [ ] **01-03**: Verify fixes (scheduler + diversity tests) — Wave 2

**Status:** 🟡 In Progress (2/3 plans complete)  
**Dependencies:** None (bug fixes on existing code)

### Plan Files Created

| Plan | Objective | Wave | Status |
|------|-----------|------|--------|
| [01-production-fixes-01-PLAN.md](phases/01-production-fixes/01-production-fixes-01-PLAN.md) | Add digest generation job to scheduler | 1 | ✓ Complete |
| [01-production-fixes-02-PLAN.md](phases/01-production-fixes/01-production-fixes-02-PLAN.md) | Implement source diversity with decay factor | 1 | ✓ Complete |
| [01-production-fixes-03-PLAN.md](phases/01-production-fixes/01-production-fixes-03-PLAN.md) | Verify fixes (scheduler + diversity tests) | 2 | Ready |

**Wave Structure:**
| Wave | Plans | Dependencies |
|------|-------|--------------|
| 1 | 01-01, 01-02 | None (can run in parallel) |
| 2 | 01-03 | 01-01, 01-02 (verification) |

---

## Phase 3: Polish

**Goal:** Add push notifications, unified content analytics, comprehensive tests, and performance optimization

### Requirements Addressed

- POLISH-01 (Push notification "Digest prêt" — FR21.5 / Story 10.15)
- POLISH-02 (Unified content interaction analytics — Story 10.16, CONTEXT.md decisions)
- POLISH-03 (DigestSelector unit tests — Story 10.17)
- POLISH-04 (Performance optimization — eager loading, caching)

### Success Criteria

1. Daily local push notification at 8am "Ton essentiel du jour est prêt"
2. Notification tap opens DigestScreen
3. Opt-out in settings (wired to existing toggle)
4. Analytics events: unified `content_interaction` tracked across feed & digest surfaces
5. Session events: `digest_session` (with closure stats) and `feed_session` (surface-specific)
6. Forward-compatible `atomic_themes` field in event schema (nullable)
7. Backend GET /analytics/digest-metrics endpoint available
8. DigestSelector unit tests: selection, diversity, decay, fallback
9. Digest API uses eager loading (no N+1 queries)
10. Mobile caches daily digest in memory

### Plans

- [ ] **03-01**: Local push notification "Digest prêt" — Wave 1
- [x] **03-02**: Unified analytics schema + service methods (backend + mobile) — Wave 1
- [ ] **03-03**: Wire analytics into digest screens + metrics endpoint — Wave 2
- [x] **03-04**: DigestSelector & DigestService tests (TDD) — Wave 1
- [ ] **03-05**: Performance optimization (eager loading + caching) — Wave 3

**Status:** 🟡 In Progress (2/5 plans complete)  
**Dependencies:** Phase 1 complete (production fixes deployed)

### Plan Files Created

| Plan | Objective | Wave | Status |
|------|-----------|------|--------|
| [03-01-PLAN.md](phases/03-polish/03-01-PLAN.md) | Local push notification at 8am (v20 API) | 1 | Ready |
| [03-02-PLAN.md](phases/03-polish/03-02-PLAN.md) | Unified content_interaction analytics schema + service | 1 | ✓ Complete |
| [03-03-PLAN.md](phases/03-polish/03-03-PLAN.md) | Wire analytics into digest + metrics endpoint | 2 | Ready |
| [03-04-PLAN.md](phases/03-polish/03-04-PLAN.md) | DigestSelector & DigestService tests (TDD) | 1 | ✓ Complete |
| [03-05-PLAN.md](phases/03-polish/03-05-PLAN.md) | Performance optimization (eager loading + caching) | 3 | Ready |

**Wave Structure:**
| Wave | Plans | Dependencies |
|------|-------|--------------|
| 1 | 03-01, 03-02, 03-04 | None (can run in parallel) |
| 2 | 03-03 | 03-02 (needs unified analytics methods) |
| 3 | 03-05 | 03-03, 03-04 (needs analytics wiring + tests as safety net) |

---

## Requirement Mapping Summary

| Requirement | Phase | Plan | Status |
|-------------|-------|------|--------|
| FIX-01 | Phase 1 | 01-01 | Pending |
| FIX-02 | Phase 1 | 01-02 | Pending |
| TEST-01 | Phase 1 | 01-03 | Pending |
| TEST-02 | Phase 1 | 01-03 | Pending |
| POLISH-01 | Phase 3 | 03-01 | Pending |
| POLISH-02 | Phase 3 | 03-02, 03-03 | Pending |
| POLISH-03 | Phase 3 | 03-04 | Pending |
| POLISH-04 | Phase 3 | 03-05 | Pending |

**100% Coverage Achieved** ✓

---

## Execution Flow

```
Phase 1:
  Wave 1 (Parallel): 01-01 (scheduler), 01-02 (diversity)
  Wave 2: 01-03 (verification)

Phase 3:
  Wave 1 (Parallel): 03-01 (notifications), 03-02 (unified analytics schema), 03-04 (tests)
  Wave 2: 03-03 (analytics wiring into digest + metrics endpoint)
  Wave 3: 03-05 (performance optimization + caching)
```

---

## Key Decisions Logged

| Decision | Rationale | Phase |
|----------|-----------|-------|
| Decay factor 0.70 | Matches existing feed algorithm for consistency | 1 |
| Min 3 sources | Ensures meaningful diversity in 5-article digest | 1 |
| 8am Europe/Paris | Matches Top 3 schedule, user expectation | 1 |
| Local notifications (not FCM) | Simpler, no backend needed, story dev notes recommend for MVP | 3 |
| Unified content_interaction events | CONTEXT.md decision — one event type across surfaces, not separate per feature | 3 |
| Forward-compatible atomic_themes field | Prepares for Camembert enrichment without schema migration | 3 |
| Extend existing AnalyticsService | No new dependencies, reuse plumbing | 3 |
| TDD for DigestSelector | Clear inputs/outputs, safety net for perf refactoring | 3 |

---

*Roadmap created: 2026-02-07*  
*Phase 3 replanned: 2026-02-08 (unified analytics per CONTEXT.md)*  
*Next step: Run `/gsd-execute-phase 3` to execute Phase 3*
