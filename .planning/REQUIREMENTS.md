# Requirements: Facteur — Epic 10 Digest Central

**Defined:** 2026-02-01  
**Core Value:** Users must feel "finished" and informed in 2-4 minutes with 5 curated articles

## v1 Requirements (Epic 10 MVP)

### Database & Models

- [ ] **DB-01**: Migration from `daily_top3` to `daily_digest` table with JSONB items array (5 articles)
- [ ] **DB-02**: `digest_completions` table for tracking daily completions
- [ ] **DB-03**: Extend `user_streaks` with `closure_streak`, `longest_closure_streak`, `last_closure_date`

### Backend Services

- [ ] **SVC-01**: `DigestSelector` service — select 5 articles from user's declared sources
- [ ] **SVC-02**: Diversity constraints in selector (max 2 per source, max 2 per theme)
- [ ] **SVC-03**: Fallback to curated sources when user pool < 5 articles
- [ ] **SVC-04**: Daily digest generation job (8am Paris time)

### API Endpoints

- [ ] **API-01**: `GET /api/digest` — retrieve today's digest (auto-generate if missing)
- [ ] **API-02**: `POST /api/digest/{id}/action` — mark article as read/saved/not_interested
- [ ] **API-03**: Completion tracking endpoint for closure logic

### Frontend — Digest Screen

- [ ] **UI-01**: Digest screen with 5 article cards (replaces feed as default)
- [ ] **UI-02**: Progress bar component (X/5 articles processed)
- [ ] **UI-03**: Article card with 3 actions: Read / Save / Not Interested
- [ ] **UI-04**: "Not Interested" integration with existing Personalization system

### Frontend — Closure Experience

- [ ] **UI-05**: Closure screen with animation, "Tu es informé !" message
- [ ] **UI-06**: Streak celebration display (closure streak)
- [ ] **UI-07**: "Explorer plus" button to access relegated feed

### Gamification

- [ ] **GMF-01**: Closure streak tracking (separate from reading streak)
- [ ] **GMF-02**: Streak UI integration in digest and closure screens

### Notifications (Optional/P1)

- [ ] **NOTIF-01**: Morning push notification "Votre digest est prêt" (8h, opt-in)

## v2 Requirements (Post-MVP)

### Multiple Essentials

- **ESS-01**: "Zen" Essential — filter out negative news (requires sentiment analysis)
- **ESS-02**: Thematic Essentials — Tech, Culture, etc.
- **ESS-03**: "New Perspectives" Essential — challenge your bubble

### Advanced Features

- **ADV-01**: Manual refresh — "Je n'aime pas ce digest, régénère"
- **ADV-02**: Quiz post-closure — "As-tu retenu ?"
- **ADV-03**: Audio digest — podcast version of daily summary

## Out of Scope

| Feature | Reason |
|---------|--------|
| In-app reading mode | Too complex for MVP — keep redirect to source |
| Real-time ML retraining | Use existing Personalization system instead |
| Sentiment analysis for Zen mode | Too costly/complex for MVP — defer to V2 |
| Complex algorithmic discovery | Digest = user sources only, discovery on relegated feed |
| Multiple digest types in MVP | Single digest validates core concept first |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DB-01 | Phase 1: Foundation | Pending |
| DB-02 | Phase 1: Foundation | Pending |
| DB-03 | Phase 1: Foundation | Pending |
| SVC-01 | Phase 1: Foundation | Pending |
| SVC-02 | Phase 1: Foundation | Pending |
| SVC-03 | Phase 1: Foundation | Pending |
| SVC-04 | Phase 1: Foundation | Pending |
| API-01 | Phase 1: Foundation | Pending |
| API-02 | Phase 1: Foundation | Pending |
| API-03 | Phase 1: Foundation | Pending |
| UI-01 | Phase 2: Frontend | Pending |
| UI-02 | Phase 2: Frontend | Pending |
| UI-03 | Phase 2: Frontend | Pending |
| UI-04 | Phase 2: Frontend | Pending |
| UI-05 | Phase 2: Frontend | Pending |
| UI-06 | Phase 2: Frontend | Pending |
| UI-07 | Phase 2: Frontend | Pending |
| GMF-01 | Phase 2: Frontend | Pending |
| GMF-02 | Phase 2: Frontend | Pending |
| NOTIF-01 | Phase 3: Polish | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0 ✓

---

*Requirements defined: 2026-02-01*  
*Last updated: 2026-02-01 after Epic 10 validation*
