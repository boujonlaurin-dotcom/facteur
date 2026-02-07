# Project State: Facteur — Epic 10 Digest Central

**Current Phase:** 2 — Frontend Complete  
**Last Updated:** 2026-02-07  
**Status:** ✅ Phase 2 Complete - All 15 plans executed successfully (including 02-16 gap closure)

**Status:** ✅ All UI/UX adjustments complete — BriefingSection pattern implemented with FeedCard footer actions

---

## Current Position

**Phase:** 02-frontend ✅ COMPLETE  
**Plan:** 02-16 complete (Fix API Response Scoring Breakdown Bug)  
**Next:** Phase 03 (Polish)  

**Progress:** Phase 1: 4/4 | Phase 2: 15/15 | Total: 19/19 plans complete  

```
Phase 1 Foundation: [████] 100% (4/4)
Phase 2 Frontend:   [███████████████] 100% (15/15)
Overall:            [███████████████████] 100% (19/19)
```

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Users must feel "finished" and informed in 2-4 minutes with 5 curated articles  
**Current focus:** Epic 10 — Digest Central pivot implementation  
**Key principle:** Safe reuse of existing backend logic

---

## Phase Status

| Phase | Status | Progress | Plans Complete |
|-------|--------|----------|----------------|
| 1 — Foundation | ✅ Complete | 100% | **4/4** |
| 2 — Frontend | ✅ Complete | 100% | **15/15** |
| 3 — Polish | ⚪ Not Started | 0% | 0 |

---

## ✅ UI/UX Adjustments Complete (Phase 2 - Plan 02-07)

### Completed Changes

All UI/UX adjustments from the rework have been successfully implemented:

#### 1. ✅ **Reuse BriefingSection as Base**
- Created `DigestBriefingSection` based on BriefingSection patterns
- Adapted from 3 to 5 articles
- Premium container design (gradient, 24px radius, shadow)

#### 2. ✅ **Remove "Read" Button**
- Reading is now marked automatically on article tap
- Removed redundant "Lu" button from action bar

#### 3. ✅ **Integrate Save/NotInterested in FeedCard Footer**
- Extended FeedCard with onSave and onNotInterested callbacks
- Save button (bookmark icon) in footer
- NotInterested button (eye-slash icon) in footer
- Source info compact on left side
- Reuses `PersonalizationSheet` for "Not Interested" action

#### 4. ✅ **Progress Bar in Header**
- Elegant segmented progress bar with 5 segments (4px height, 8px width each)
- Green when complete
- Integrated in DigestBriefingSection header

#### 5. ✅ **Feed-Style Header**
- Uses same header style as Feed (FacteurLogo centered)
- Title "L'Essentiel du Jour" (not "Votre Essentiel")

#### 6. **Decommission Old BriefingSection** (Next: Plan 02-08)
- Ready to remove from FeedScreen once validated
- Can mark old code as @deprecated

### Implementation Details
- **Files created:** `digest_briefing_section.dart`
- **Files modified:** `feed_card.dart`, `digest_screen.dart`
- **flutter analyze:** 0 errors

### Reference Document
**Full specifications:** `.planning/phases/02-frontend/02-07-SUMMARY.md`

---

## Completed Work


### Frontend Phase — Plan 02-16 Complete (2026-02-06)

**Fix API Response Scoring Breakdown Bug**

- ✅ Fixed null handling for breakdown data from database JSONB
- ✅ Changed `item_data.get("breakdown", [])` to `item_data.get("breakdown") or []`
- ✅ Fixed mutable default in Pydantic schema (`Field(default_factory=list)`)
- ✅ API response now correctly includes `recommendation_reason` with full scoring breakdown
- ✅ Flutter app will receive non-null `recommendationReason` for all digest items

**Root cause:** `dict.get("key", default)` only returns default if key is missing, not if value is `null`. PostgreSQL JSONB null values were returned as Python `None`, causing the breakdown to be skipped.

See: `.planning/phases/02-frontend/02-16-SUMMARY.md`


### Foundation Phase — Plan 01-04 Complete (2026-02-05)

**Critical Fix: Extended Digest Lookback to 168h with Recency Bonuses**

- ✅ Extended lookback window from 48h to 168h (7 days) for user sources
- ✅ Added 6 tiered recency bonus constants (30/25/15/8/3/1 pts) to ScoringWeights
- ✅ Modified fallback logic: only use curated when user sources < 3 articles
- ✅ User sources now ALWAYS prioritized over curated content
- ✅ Recency bonuses displayed in article reason strings (+X pts format)
- ✅ Comprehensive logging for debugging source selection

**Impact:** Fixes critical bug where users received articles NOT from their followed sources because the 48h window was too narrow.

See: `.planning/phases/01-foundation/01-04-SUMMARY.md`


### Frontend Phase — Plan 02-09 Complete (2026-02-04)

**Fix MissingGreenlet Error with Eager Loading**

- ✅ Added `from sqlalchemy.orm import selectinload` import at top level
- ✅ Replaced `session.get(Content, content_id)` with eager loading query in `_build_digest_response()`
- ✅ Used `selectinload(Content.source)` pattern to prevent lazy loading in async context
- ✅ Follows same pattern as `_get_emergency_candidates()` method

See: `.planning/phases/02-frontend/02-09-SUMMARY.md`

### Frontend Phase — Plan 02-11 Complete (2026-02-06)

**Digest Scoring Transparency for "Pourquoi cet article?"**

- ✅ Extended Pydantic schemas with DigestScoreBreakdown and DigestRecommendationReason
- ✅ Modified DigestSelector._score_candidates() to capture all 5 scoring layer contributions
- ✅ Added CoreLayer contributions: Theme match (+70), Trusted source (+40), Custom source (+10)
- ✅ Added ArticleTopicLayer: Topic matches (+60, max 2), Subtopic precision (+20)
- ✅ Added StaticPreferenceLayer: Format match (+15)
- ✅ Added QualityLayer: Curated source (+10), Low reliability penalty (-30)
- ✅ Updated digest storage to persist breakdown in JSONB
- ✅ Enhanced API response with full recommendation_reason for each item
- ✅ Preserved backward-compatible 'reason' string field
- ✅ Added _determine_top_reason() helper to intelligently derive label from highest contribution

See: `.planning/phases/02-frontend/02-11-SUMMARY.md`

### Frontend Phase — Plan 02-15 Complete (2026-02-06)

**Fix Missing Scoring Breakdown Data**

- ✅ Added diagnostic logging for breakdown storage tracking
- ✅ Added INFO log when breakdown is stored (content_id, title, count, labels)
- ✅ Added WARNING log when breakdown is missing during storage
- ✅ Added INFO log when breakdown is rebuilt from stored data
- ✅ Added WARNING log when stored item has no breakdown data
- ✅ Logs distinguish old digests (before 02-11) from new digests with breakdown
- ✅ User can force regenerate via existing endpoint to get fresh data

See: `.planning/phases/02-frontend/02-15-SUMMARY.md`

### Frontend Phase — Plan 02-14 Complete (2026-02-06)

**Digest Personalization Unification**

- ✅ Removed NotInterestedConfirmationSheet widget (156 lines deleted)
- ✅ Unified Digest personalization with Feed pattern
- ✅ Updated _handleNotInterested to apply action immediately (no confirmation)
- ✅ Shows unified "Pourquoi cet article?" sheet with scoring + personalization
- ✅ Visual design matches Feed PersonalizationSheet exactly
- ✅ Code is simpler: 176 lines removed, 8 lines added
- ✅ flutter analyze passes with 0 new errors

See: `.planning/phases/02-frontend/02-14-SUMMARY.md`

### Frontend Phase — Plan 02-13 Complete (2026-02-06)

**"Not Interested" Confirmation Flow Fix**

- ✅ Created NotInterestedConfirmationSheet widget with confirmation flow
- ✅ Fixed UX issue where "Pourquoi cet article?" sheet showed "Information non disponible"
- ✅ New flow: Confirmation sheet → Apply action → Optional personalization sheet
- ✅ Clear explanation: "Cela masquera cet article et réduira les contenus similaires"
- ✅ Source name displayed prominently in styled container
- ✅ Destructive action button styled with warning color (orange)
- ✅ flutter analyze passes with 0 errors

See: `.planning/phases/02-frontend/02-13-SUMMARY.md`

### Frontend Phase — Plan 02-12 Complete (2026-02-06)

**"Pourquoi cet article?" UI Implementation**

- ✅ Extended Freezed models with DigestScoreBreakdown and DigestRecommendationReason classes
- ✅ Created DigestPersonalizationSheet widget with scoring breakdown visualization
- ✅ Added long-press handler on digest articles with haptic feedback
- ✅ Visual distinction: green trendUp for positive contributions, red trendDown for negative
- ✅ Total score displayed prominently in header badge (e.g., "245 pts")
- ✅ Actions to mute source/theme from reasoning sheet (reuses feed provider)
- ✅ Null-safe handling for articles without reasoning data
- ✅ flutter analyze passes with 0 errors

See: `.planning/phases/02-frontend/02-12-SUMMARY.md`

### Frontend Phase — Plan 02-10 Complete (2026-02-04)

**Add greenlet>=3.0.0 Dependency for SQLAlchemy Async Support**

- ✅ Added greenlet>=3.0.0 to packages/api/requirements.txt in Database section
- ✅ Added greenlet>=3.0.0 to packages/api/pyproject.toml dependencies
- ✅ SQLAlchemy async operations now have proper context switching support
- ✅ Fixes MissingGreenlet error in digest loading

See: `.planning/phases/02-frontend/02-10-SUMMARY.md`

### Frontend Phase — Plan 02-07 Complete (2026-02-04)

**BriefingSection Refactor with DigestBriefingSection**

- ✅ Extended FeedCard with onSave, onNotInterested, isSaved parameters
- ✅ Created DigestBriefingSection based on BriefingSection patterns
- ✅ Segmented progress bar (5 segments) in header
- ✅ Refactored DigestScreen with CustomScrollView and Feed-style header
- ✅ Reading automatic on article tap (no Read button)
- ✅ Reuses PersonalizationSheet for NotInterested action
- ✅ flutter analyze passes with 0 errors

See: `.planning/phases/02-frontend/02-07-SUMMARY.md`

### Frontend Phase — Plan 02-01 Verified (2026-02-03)

**Digest Screen UI with 5 Cards and Progress Bar**

- ✅ Freezed models (SourceMini, DigestItem, DigestResponse, DigestCompletionResponse)
- ✅ Digest repository with API calls to /api/digest
- ✅ Riverpod provider with optimistic updates and auto-completion
- ✅ ProgressBar widget with 5 animated segments
- ✅ DigestCard widget adapted from FeedCard with rank badge
- ✅ DigestScreen with "Votre Essentiel" app bar and list of 5 articles
- ✅ Route configuration with digest as default authenticated route
- ✅ Flutter analyze passes with 0 errors

See: `.planning/phases/02-frontend/02-01-SUMMARY.md`

### Frontend Phase — Plan 02-04 Complete (2026-02-01)

**Feed Relegation to Explorer Plus Status**

- ✅ Updated shell scaffold with 3 tabs: Essentiel (Digest), Explorer (Feed), Paramètres (Settings)
- ✅ Changed default authenticated route from feed to digest
- ✅ Created DigestWelcomeModal for first-time users
- ✅ Integrated welcome modal with query param detection and shared preferences
- ✅ Verified streak indicators in both digest and feed screens
- ✅ All navigation flows working end-to-end

See: `.planning/phases/02-frontend/02-04-SUMMARY.md`

### Frontend Phase — Plan 02-02 Complete (2026-02-01)

**Article Actions with API Integration**

- ✅ Digest repository with applyAction and completeDigest methods
- ✅ Digest provider with optimistic updates and action handling
- ✅ Article action bar widget with 3 buttons (Read, Save, Not Interested)
- ✅ Not Interested confirmation sheet with source muting explanation
- ✅ Digest card with integrated action bar and visual state feedback
- ✅ Digest screen with action handling and progress bar
- ✅ Haptic feedback for actions (light/medium/heavy by action type)
- ✅ Notifications confirming action success

See: `.planning/phases/02-frontend/02-02-SUMMARY.md`

### Foundation Phase — Plan 01-03 Complete (2026-02-01)

**Digest API Endpoints for Mobile App**

- ✅ Pydantic schemas for digest API (DigestItem, DigestResponse, DigestAction)
- ✅ DigestService with get_or_create_digest(), apply_action(), complete_digest()
- ✅ REST API endpoints:
  - GET /api/digest - Retrieve or generate today's digest
  - POST /api/digest/{id}/action - Mark read/save/not_interested
  - POST /api/digest/{id}/complete - Track completion, update closure streak
  - POST /api/digest/generate - On-demand generation
- ✅ Integration with DigestSelector (from 01-02)
- ✅ Integration with Personalization system (not_interested → source mute)
- ✅ Integration with StreakService (consumption streak on read)
- ✅ Closure streak tracking with milestone messages (7 days, 30 days)

See: `.planning/phases/01-foundation/01-03-SUMMARY.md`

### Foundation Phase — Plan 01-02 Complete (2026-02-01)

**DigestSelector Service for 5-Article Daily Digest**

- ✅ DigestSelector service with `select_for_user()` method
- ✅ Diversity constraints: max 2 articles per source, max 2 per theme
- ✅ Fallback mechanism to curated sources when user pool < 5
- ✅ Full integration with existing ScoringEngine (no modifications)
- ✅ Comprehensive unit tests (617 lines) covering constraints and fallback
- ✅ Daily batch generation job with concurrency control
- ✅ On-demand single user generation function
- ✅ Respects muted sources, themes, and topics from PersonalizationLayer

See: `.planning/phases/01-foundation/01-02-SUMMARY.md`

### Foundation Phase — Plan 01-01 Complete (2026-02-01)

**Database Schema for Digest System**

- ✅ Migration 009: daily_digest table with JSONB items array
- ✅ Migration 010: digest_completions table for tracking
- ✅ Migration 011: Extended user_streaks with closure tracking
- ✅ DailyDigest SQLAlchemy model
- ✅ DigestCompletion SQLAlchemy model
- ✅ Updated UserStreak model with closure fields

See: `.planning/phases/01-foundation/01-01-SUMMARY.md`

### Documentation (2026-02-01)

- ✅ PROJECT.md created with pivot context and decisions
- ✅ REQUIREMENTS.md with 21 REQ-IDs mapped to phases
- ✅ ROADMAP.md with 3 phases and execution flow
- ✅ config.json with workflow preferences

### Decisions Validated

- ✅ 5 articles per day (creates "finished" state)
- ✅ Sources declared only (user control)
- ✅ Read/Save/Not Interested actions (reuses Personalization)
- ✅ Feed relegated (safety valve)
- ✅ No Zen Essential in MVP (defer to V2)
- ✅ Reuse existing scoring algorithm (no changes needed)
- ✅ Diversity constraints: max 2 per source, max 2 per theme
- ✅ Fallback to curated sources when pool < 5

---

## Pending Work

### Immediate Next Steps

1. **Phase 2 Frontend** ✅ COMPLETE (15/15 plans)
   - ✅ 02-01 Digest Screen UI - Initial digest implementation
   - ✅ 02-02 Action UI - Article actions with API integration
   - ✅ 02-03 Closure Screen - Completion celebration
   - ✅ 02-04 Feed Relegation - Navigation update
   - ✅ 02-07 BriefingSection Refactor - UI/UX improvements using BriefingSection patterns
   - ✅ 02-09 Fix SQLAlchemy Eager Loading (gap closure)
   - ✅ 02-10 Add greenlet>=3.0.0 Dependency (gap closure)
   - ✅ 02-11 Digest Scoring Transparency - "Pourquoi cet article?" backend
   - ✅ 02-12 "Pourquoi cet article?" UI - Frontend modal implementation
   - ✅ 02-13 "Not Interested" Confirmation Flow Fix - UX fix for moins voir action
   - ✅ 02-14 Digest Personalization Unification - Align with Feed pattern
   - ✅ 02-15 Fix Missing Scoring Breakdown Data - Diagnostic logging for breakdown tracking
   - ✅ 02-16 Fix API Response Scoring Breakdown Bug - Fixed null handling in JSONB retrieval
   - ✅ Verified: All must-haves passing

2. **Next: Phase 3 Polish**
   - Push notifications for digest ready
   - Analytics integration for MoC metrics
   - Performance optimization (<500ms load time)

3. **Prepare for Production**
   - End-to-end testing
   - Beta release preparation

---

## Current Blockers

**None** — Ready to proceed with planning Phase 1.

---

## Decisions Made

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-02-06 | Unify Digest and Feed personalization patterns | Creates consistent UX across platform, simplifies code |
| 2026-02-06 | Apply "Not Interested" action immediately (no confirmation) | Matches Feed behavior; simpler UX flow |
| 2026-02-06 | Show confirmation BEFORE personalization for "Not Interested" | Avoids confusing "Information non disponible" UX issue when sheet opens |
| 2026-02-06 | Reuse feed provider for muting actions | DRY principle - avoid duplicating personalization logic |
| 2026-02-06 | Use GestureDetector for long-press on FeedCard | Clean extension of existing card component |
| 2026-02-06 | Use 'or []' pattern for null JSONB handling | dict.get('key', []) doesn't handle null values from PostgreSQL JSONB |
| 2026-02-06 | Match feed's ScoreContribution pattern for digest | UI consistency and proven pattern for scoring transparency |
| 2026-02-06 | Store breakdown in JSONB | Enables historical analysis and retrieval of scoring details |
| 2026-02-06 | Preserve legacy 'reason' string | Backward compatibility for existing clients |
| 2026-02-04 | Extend FeedCard with optional callbacks | Maintains backward compatibility while enabling Save/NotInterested for digest |
| 2026-02-04 | Automatic read on article tap | Consistent with BriefingSection behavior, removes redundant button |
| 2026-02-04 | Segmented progress bar (5 segments) | Elegant, compact visualization of digest progress |
| 2026-02-01 | 3-tab navigation structure | Essentiel primary, Explorer secondary, clear hierarchy |
| 2026-02-01 | First-time welcome via query params | Allows direct onboarding→digest flow with welcome state |
| 2026-02-01 | SharedPreferences for welcome tracking | Ensures welcome shown only once per user |
| 2026-02-01 | Optimistic updates for actions | Instant UI feedback, rollback on error |
| 2026-02-01 | Confirmation sheet for "not_interested" | Prevents accidental source mutes |
| 2026-02-01 | Haptic feedback by action type | Medium for read, light for save/dismiss, heavy for completion |
| 2026-02-01 | Auto-complete when all processed | No explicit "done" button needed |
| 2026-02-01 | Card opacity 0.6 when processed | Clear visual feedback without removing card |
| 2026-02-01 | JSONB for digest items | Fixed 5-item array, simpler than junction table |
| 2026-02-01 | Separate closure streak | Distinct gamification path from activity streak |
| 2026-02-01 | Idempotent migrations | Safe re-runs, Supabase-compatible |
| 2026-02-01 | Scope: Single digest only | Validate core concept before complexity |
| 2026-02-01 | Include "Not Interested" | Reuse existing Personalization, reduce frustration |
| 2026-02-01 | Defer Zen Essential | Sentiment analysis too costly for MVP |
| 2026-02-01 | Feed relegated not removed | Safety valve for users wanting more |
| 2026-02-01 | Reuse V2/V3 scoring | No algorithm changes needed |
| 2026-02-01 | Greedy diversity algorithm | Fast, deterministic, easy to understand |

---

## Concerns & Risks

| Risk | Mitigation | Status |
|------|------------|--------|
| Users reject binary digest | Feed remains accessible via "Explorer plus" | Monitored |
| 5 articles feels too few | Fallback to curated sources; can adjust number | Configurable |
| Personalization integration complexity | Well-understood existing system | Low risk |
| Performance with diversity constraints | Test with large content pools | To monitor |
| Batch job scalability | Configurable batch_size and concurrency | Controlled |

---

## Next Action

**Phase 2 Frontend Complete - UI/UX Rework Done - Ready for Phase 3 (Polish)**

Foundation for digest-first experience is complete with improved UI/UX:
- DigestBriefingSection with premium BriefingSection design
- 5 articles with segmented progress bar and N°1-5 rank badges
- FeedCard footer with Save/NotInterested actions
- Automatic read on tap (no Read button)
- **Long-press for "Pourquoi cet article?" with scoring breakdown**
- Feed-style header with FacteurLogo
- Closure screen with streak celebration
- Navigation with Essentiel/Explorer/Paramètres tabs
- First-time welcome experience
- Verified: All must-haves passing, flutter analyze clean

Next: **Phase 03 - Polish** for production readiness

1. Morning push notifications (8am digest ready)
2. Analytics integration (MoC completion tracking)
3. Performance optimization (<500ms load time)

Run `/gsd-plan-phase 3` to create detailed plans.

---

## Session Continuity

**Last session:** 2026-02-06T23:24:00Z  
**Stopped at:** Completed 02-16 Fix API Response Scoring Breakdown Bug  
**Resume file:** `.planning/phases/02-frontend/02-16-SUMMARY.md`

---

*State updated after 02-16 plan execution - Phase 2 Frontend COMPLETE with 15/15 plans, ready for Phase 3 Polish*
