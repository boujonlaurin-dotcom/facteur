# Requirements: Facteur — Epic 10 Digest Central

**Defined:** 2026-02-01  
**Core Value:** Users must feel "finished" and informed in 2-4 minutes with 5 curated articles

## v1 Requirements (Epic 10 MVP)

### Database & Models

- [x] **DB-01**: Migration from `daily_top3` to `daily_digest` table with JSONB items array (5 articles)
- [x] **DB-02**: `digest_completions` table for tracking daily completions
- [x] **DB-03**: Extend `user_streaks` with `closure_streak`, `longest_closure_streak`, `last_closure_date`

### Backend Services

- [x] **SVC-01**: `DigestSelector` service — select 5 articles from user's declared sources
- [x] **SVC-02**: Diversity constraints in selector (max 2 per source, max 2 per theme)
- [x] **SVC-03**: Fallback to curated sources when user pool < 5 articles
- [x] **SVC-04**: Daily digest generation job (8am Paris time)

### API Endpoints

- [x] **API-01**: `GET /api/digest` — retrieve today's digest (auto-generate if missing)
- [x] **API-02**: `POST /api/digest/{id}/action` — mark article as read/saved/not_interested
- [x] **API-03**: Completion tracking endpoint for closure logic

### Frontend — Digest Screen

- [x] **UI-01**: Digest screen with 5 article cards (replaces feed as default)
- [x] **UI-02**: Progress bar component (X/5 articles processed)
- [x] **UI-03**: Article card with 3 actions: Read / Save / Not Interested
- [x] **UI-04**: "Not Interested" integration with existing Personalization system

### Frontend — Closure Experience

- [x] **UI-05**: Closure screen with animation, "Tu es informé !" message
- [x] **UI-06**: Streak celebration display (closure streak)
- [x] **UI-07**: "Explorer plus" button to access relegated feed

### Gamification

- [x] **GMF-01**: Closure streak tracking (separate from reading streak)
- [x] **GMF-02**: Streak UI integration in digest and closure screens

### Notifications (Optional/P1)

- [ ] **NOTIF-01**: Morning push notification "Votre digest est prêt" (8h, opt-in)

## Implementation Constraints

### Frontend Reuse Constraint (MANDATORY)

To minimize shipping, debugging, and validation of new code, the digest UI **MUST** reuse existing components and design patterns:

**Reuse as-is (no visual changes):**
- ContentCard component structure (thumbnail, title, source styling)
- Color palette (Terracotta #E07A5F, dark theme backgrounds, text colors)
- Typography system (Fraunces for headings, DM Sans for body)
- Card container styling (borders, shadows, padding)
- Button components (Primary, Secondary, Ghost variants)
- Bottom navigation bar (no changes)

**Allowed adaptations only:**
- Progress bar component (new, but use existing color tokens)
- Action bar: extend from 2 to 3 actions (Read/Save/Not Interested) using existing button styles
- "Essentiel" container: reuse existing card container patterns
- Closure screen: new screen but reuse existing animation patterns and color scheme

**Anti-patterns to avoid:**
- ❌ Creating new card designs from scratch
- ❌ Introducing new colors or typography
- ❌ Changing layout patterns significantly
- ✅ The digest should feel like a "reorganization of existing UI", not a new design system

### Algorithmic Selection Guarantee (MANDATORY)

The top 5 articles **MUST** be selected based on the existing algorithmic ranking system:

**Selection Process:**
```
1. Pool: Articles from user's declared sources only (36h window)
2. Scoring: Apply EXISTING algorithm layers (no modifications):
   - CoreLayer: Theme matching (+70pts), Source following (+40pts)
   - ArticleTopicLayer: Topic matching (+40pts), Precision bonus (+10pts)
   - QualityLayer: Source reliability (+10pts/-30pts)
   - PersonalizationLayer: Apply existing user mutes/blocks
3. Ranking: Sort by total score descending
4. Constraints: Apply diversity rules (max 2 per source, max 2 per theme)
5. Selection: Take top 5 from ranked list
6. Fallback: If < 5, complete with curated sources (also scored)
```

**Backend Integration Requirements:**
- Use existing `ScoringEngine` class without modifications
- Query existing `user_interests` and `user_subtopics` tables
- Use existing `content.topics` classifications
- Integrate with existing `PersonalizationLayer` for "Not Interested" actions
- **No new scoring algorithms** — only a selection wrapper (`DigestSelector`)

**Verification Criteria:**
- [ ] Digest articles have `score` field visible in API response
- [ ] Scoring uses same weights as existing feed algorithm
- [ ] Personalization mutes are respected in digest selection
- [ ] Articles in digest are demonstrably top-ranked from user's sources

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
| DB-01 | Phase 1: Foundation | **Complete** |
| DB-02 | Phase 1: Foundation | **Complete** |
| DB-03 | Phase 1: Foundation | **Complete** |
| SVC-01 | Phase 1: Foundation | **Complete** |
| SVC-02 | Phase 1: Foundation | **Complete** |
| SVC-03 | Phase 1: Foundation | **Complete** |
| SVC-04 | Phase 1: Foundation | **Complete** |
| API-01 | Phase 1: Foundation | **Complete** |
| API-02 | Phase 1: Foundation | **Complete** |
| API-03 | Phase 1: Foundation | **Complete** |
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
