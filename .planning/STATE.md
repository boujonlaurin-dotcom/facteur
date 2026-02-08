# Project State: Facteur — Digest Polish (v1.1)

**Current Phase:** 3 — Polish  
**Last Updated:** 2026-02-08  
**Status:** 🟢 Phase 3 Complete

---

## Current Position

**Milestone:** v1.1 — Digest Production Fixes + Polish  
**Phase:** 03-polish  
**Plan:** 5 of 5 completed in current phase  
**Status:** Phase 3 complete  
**Last activity:** 2026-02-08 - Completed 03-05-PLAN.md (Performance optimization — eager loading + caching)

**Progress:**

```
Phase 1 Production Fixes: [●●○] 67% (2/3)
Phase 3 Polish:           [●●●●●] 100% (5/5)
Overall:                  ████████████████████░ 95%
```

---

## Project Reference

See: .planning/PROJECT.md  
**Core value:** Users feel "finished" and informed in 2-4 minutes  
**Current focus:** v1.1 — Polish complete, Phase 1 verification remaining  
**Key principle:** Unified analytics across surfaces, safe reuse of existing logic

---

## Phase Status

| Phase | Status | Progress | Plans Complete |
|-------|--------|----------|----------------|
| 1 — Production Fixes | 🟡 In Progress | 67% | 2/3 |
| 3 — Polish | 🟢 Complete | 100% | 5/5 |

---

## Pending Work

### Phase 3 Polish

- ✅ 03-01: Local push notification "Digest prêt" — COMPLETE
- ✅ 03-02: Unified analytics schema + service methods — COMPLETE
- ✅ 03-03: Wire analytics into digest screens + metrics endpoint — COMPLETE
- ✅ 03-04: DigestSelector & DigestService tests (TDD) — COMPLETE
- ✅ 03-05: Performance optimization (eager loading + caching) — COMPLETE

### Phase 1 Remaining

- ⬜ 01-03: Verify fixes (scheduler + diversity tests) — Wave 2

---

## Decisions Made

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-02-07 | Decay factor 0.70 | Matches existing feed algorithm |
| 2026-02-07 | Min 3 sources requirement | Ensures diversity in 5-article digest |
| 2026-02-07 | 8am Europe/Paris timezone | Matches Top 3 schedule |
| 2026-02-08 | Single content_interaction event type | CONTEXT.md: one event across surfaces, not separate per feature |
| 2026-02-08 | Clean break with deprecation for legacy analytics | Old methods @deprecated, new unified methods alongside |
| 2026-02-08 | Forward-compatible atomic_themes field | Nullable, ready for Camembert without schema migration |
| 2026-02-08 | Characterization tests over strict RED-first TDD | Implementation exists, tests lock down behavior |
| 2026-02-08 | Test _select_with_diversity directly (sync) | No DB mocking needed, fast and reliable |
| 2026-02-08 | PushNotificationService (not NotificationService) | Avoids collision with existing SnackBar NotificationService |
| 2026-02-08 | Local notifications only (no FCM) | Simpler, no backend needed, story dev notes recommend for MVP |
| 2026-02-08 | Map 'not_interested' to 'dismiss' analytics action | Semantic alignment with unified schema |
| 2026-02-08 | JSONB text() for analytics aggregation | Performance over ORM filtering for JSONB fields |
| 2026-02-08 | Batch queries over asyncio.gather | AsyncSession not safe for concurrent queries; batch reduces round trips |
| 2026-02-08 | In-memory cache only (no Hive) | Digest changes daily, stale risk minimal |

---

## Concerns & Risks

| Risk | Mitigation | Status |
|------|------------|--------|
| pubspec.yaml conflict (timezone ^0.9.4 vs ^0.10.0) | Resolved: used ^0.10.0 (required by v20) | ✅ Resolved |
| Regression in digest functionality | 24 tests in 03-04 provide safety net, all pass after optimization | ✅ Mitigated |

---

## Session Continuity

**Last session:** 2026-02-08  
**Stopped at:** Completed 03-05-PLAN.md (Phase 3 Polish complete)  
**Resume file:** None

---

*Next step: Execute Phase 1 remaining plan (01-03: verify fixes — scheduler + diversity tests)*
