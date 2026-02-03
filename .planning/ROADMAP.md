# Roadmap: Facteur — Epic 10 Digest Central

**Project:** Facteur  
**Strategic Goal:** Pivot from Feed-First to Digest-First experience  
**Estimated Duration:** ~35h development + QA  
**Last Updated:** 2026-02-01 (Phase 2 Complete)

---

## Success Metrics

### Phase Success Criteria

Each phase must demonstrate:
- **Technical**: Code is testable, documented, and integrates cleanly with existing systems
- **Functional**: User can complete the described workflow end-to-end
- **Quality**: No regression in existing features

### Project Success Metrics (MVP)

- **MoC Completion Rate**: >60% of users finish the 5-article digest
- **Time-to-Closure**: 2-4 minutes median
- **Streak Consistency**: >3 days median closure streak
- **Post-MoC Return Rate**: <20% users go to feed after closure (indicates satisfaction)

---

## Phase Overview

| # | Phase | Goal | Key Deliverables | Est. Hours |
|---|-------|------|------------------|------------|
| 1 | Foundation | Backend core — database, selector, API | 3 tables, 1 service, 3 endpoints | ~20h |
| 2 | Frontend | UI/UX — digest screen, closure, actions | 3 screens, 3 components, streak UI | ~15h |
| 3 | Polish | Push notifications, analytics, optimization | 1 notification type, events tracking | ~8h |

**Total:** ~43h (including buffer)

---

## Phase 1: Foundation (Backend)

**Goal:** Build the backend infrastructure for digest generation and tracking

**Philosophy:** Extend existing systems, don't replace. Reuse scoring, RSS sync, personalization.

### Requirements Addressed

- DB-01, DB-02, DB-03 (Database migrations)
- SVC-01, SVC-02, SVC-03 (DigestSelector service)
- API-01, API-02, API-03 (API endpoints)

### Success Criteria

1. API endpoints return correct digest data (5 articles)
2. Digest generation respects diversity constraints
3. Actions (read/save/not_interested) update database correctly
4. Completion tracking works end-to-end
5. Existing feed API remains untouched (no regression)

### Technical Approach

```
Existing Code Reuse:
├── RSS Sync → No changes (30min cron)
├── Scoring Engine → No changes (V2/V3 layers)
├── Personalization → Adapt for "not_interested"
└── User Sources → No changes (same table)

New Components:
├── daily_digest table (extends daily_top3 pattern)
├── digest_completions table (new)
├── DigestSelector service (new, uses existing scoring)
└── digest endpoints (new)
```

### Plans

- [x] **01-01**: Database migrations (daily_digest, digest_completions, user_streaks extension)
- [x] **01-02**: DigestSelector service with diversity constraints
- [x] **01-03**: API endpoints (GET /digest, POST /action, completion tracking)

**Status:** ✅ Complete (verified 2026-02-01)  
**Verification:** 14/14 must-haves verified — `01-foundation-VERIFICATION.md`

---

## Phase 2: Frontend (UI/UX)

**Goal:** Create the digest screen, closure experience, and action flows

**Philosophy:** Adapt existing UI patterns (cards, actions, streak) rather than invent new ones.

### Requirements Addressed

- UI-01, UI-02, UI-03, UI-04 (Digest screen)
- UI-05, UI-06, UI-07 (Closure screen)
- GMF-01, GMF-02 (Gamification)

### Success Criteria

1. User sees 5 article cards with progress indicator
2. Each card has Read/Save/Not Interested actions
3. "Not Interested" properly integrates with Personalization
4. Closure screen displays after all 5 articles processed
5. Streak updates and displays correctly
6. "Explorer plus" button navigates to relegated feed

### Technical Approach

```
Existing Code Reuse:
├── ContentCard component → Adapt for 3 actions
├── Personalization UI → Use for "not_interested" modal
├── Streak display → Adapt for closure streak
└── Feed screen → Keep as "Explorer plus" destination

New Components:
├── DigestScreen (new main screen)
├── ProgressBar (new component)
├── ClosureScreen (new screen)
└── ArticleActionBar (adapt for 3 actions)
```

### Plans

- [x] **02-01**: Digest screen with article cards and progress bar — Wave 1
- [x] **02-02**: Article actions (Read/Save/Not Interested) + Personalization integration — Wave 1
- [x] **02-03**: Closure screen with animation and streak celebration — Wave 2
- [x] **02-04**: Feed relegation and navigation flows — Wave 3
- [ ] **02-06**: Backend digest performance fix (gap closure for timeout issue) — Wave 1

**Dependencies:** Requires Phase 1 API endpoints ✅  
**Wave Structure:**
| Wave | Plans | Dependencies |
|------|-------|--------------|
| 1 | 02-01, 02-02, 02-06 | 02-06 has no dependencies (gap closure) |
| 2 | 02-03 | 02-02 (action completion) |
| 3 | 02-04 | 02-03 (closure navigation) |

**Status:** 🔄 Gap Closure In Progress — Backend digest timeout issue diagnosed (02-06)  
**Verification:** 7/7 must-haves verified — `02-frontend-VERIFICATION.md`
**Gap:** Digest API timeout blocking production — see `02-UAT.md` for diagnosis

---

## Phase 3: Polish (Notifications & Analytics)

**Goal:** Add push notifications and analytics for monitoring

### Requirements Addressed

- NOTIF-01 (Push notifications)
- Analytics events for MoC metrics

### Success Criteria

1. Users receive "Digest ready" notification at 8am (opt-in)
2. Analytics events track: completion rate, time-to-closure, streak
3. Performance: digest loads in <500ms

### Plans (will be detailed in plan-phase)

- **03-01**: Morning push notification (APNs + Firebase)
- **03-02**: Analytics integration (closure events)

**Dependencies:** Requires Phase 2 completion  
**Parallelizable:** Can be parallel with Phase 2 if needed (notification is independent)

---

## Requirement Mapping Summary

| Requirement | Phase | Plan | Status |
|-------------|-------|------|--------|
| DB-01 | Phase 1 | 01-01 | ✅ Complete |
| DB-02 | Phase 1 | 01-01 | ✅ Complete |
| DB-03 | Phase 1 | 01-01 | ✅ Complete |
| SVC-01 | Phase 1 | 01-02 | ✅ Complete |
| SVC-02 | Phase 1 | 01-02 | ✅ Complete |
| SVC-03 | Phase 1 | 01-02 | ✅ Complete |
| API-01 | Phase 1 | 01-03 | ✅ Complete |
| API-02 | Phase 1 | 01-03 | ✅ Complete |
| API-03 | Phase 1 | 01-03 | ✅ Complete |
| UI-01 | Phase 2 | 02-01 | ✅ Complete |
| UI-02 | Phase 2 | 02-01 | ✅ Complete |
| UI-03 | Phase 2 | 02-02 | ✅ Complete |
| UI-04 | Phase 2 | 02-02 | ✅ Complete |
| UI-05 | Phase 2 | 02-03 | ✅ Complete |
| UI-06 | Phase 2 | 02-03 | ✅ Complete |
| UI-07 | Phase 2 | 02-04 | ✅ Complete |
| GMF-01 | Phase 2 | 02-03 | ✅ Complete |
| GMF-02 | Phase 2 | 02-03 | ✅ Complete |
| NOTIF-01 | Phase 3 | 03-01 | Pending |

**100% Coverage Achieved** ✓

---

## Execution Flow

```
Wave 1 (Sequential):
  Phase 1: Foundation
    └── Plans: 01-01, 01-02, 01-03

Wave 2 (Sequential, depends on Wave 1):
  Phase 2: Frontend
    └── Plans: 02-01, 02-02, 02-03, 02-04

Wave 3 (Can start with Wave 2):
  Phase 3: Polish
    └── Plans: 03-01, 03-02
```

---

## Key Decisions Logged

| Decision | Rationale | Phase |
|----------|-----------|-------|
| Single digest for MVP | Validate core concept before complexity | 1 |
| Reuse existing Personalization | "Not Interested" action uses existing logic | 2 |
| Feed relegated not removed | Safety valve; no regression risk | 2 |
| Defer Zen Essential | Sentiment analysis too costly for MVP | 3+ |
| 5 articles fixed | Creates "finished" state; ~2-4min completion | 1 |

---

*Roadmap created: 2026-02-01*  
*Last updated: 2026-02-01*  
*Next step: Run `/gsd-execute-phase 2` to build the Frontend phase*
