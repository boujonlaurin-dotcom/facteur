# Requirements: Facteur — Digest Production Fixes

**Defined:** 2026-02-07  
**Milestone:** v1.0.1 — Critical Production Fixes  
**Core Value:** Digest must regenerate daily at 8am with diverse source representation

---

## v1.0.1 Requirements (Production Fixes)

### Bug Fix: Job Scheduler

- [ ] **FIX-01**: Daily digest generation job scheduled at 8:00 Europe/Paris
  - Import and call `run_digest_generation` from `app.jobs.digest_generation_job`
  - Add to `packages/api/app/workers/scheduler.py`
  - Same cron pattern as existing Top 3 job

### Bug Fix: Source Diversity

- [ ] **FIX-02**: Implement source diversity in digest selection
  - Modify `_select_with_diversity()` in `digest_selector.py`
  - Implement decay factor: 0.70 (same as feed algorithm)
  - Formula: `final_score = base_score * (0.70 ^ source_count)`
  - Ensure minimum 3 different sources in digest

### Verification Requirements

- [ ] **TEST-01**: Verify job triggers at 8am daily
- [ ] **TEST-02**: Verify diversity with "Le Monde only" user test case
  - User following only Le Monde should still get 3+ sources
  - No single source should dominate with 5 articles

---

## Out of Scope

| Feature | Reason |
|---------|--------|
| New digest features | Production fixes only, no new functionality |
| UI changes | Backend-only fixes |
| Algorithm improvements beyond diversity | Scope is fixing existing bugs, not enhancing |

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FIX-01 | Phase 1 | Pending |
| FIX-02 | Phase 1 | Pending |
| TEST-01 | Phase 1 | Pending |
| TEST-02 | Phase 1 | Pending |

**Coverage:**
- Total requirements: 4
- Mapped to phases: 4
- Unmapped: 0 ✓

---

*Requirements defined: 2026-02-07*  
*Last updated: 2026-02-07 after milestone initialization*
