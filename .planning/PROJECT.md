# Facteur — Pivot Digest Central

## What This Is

Facteur is a mobile app for intentional information consumption. After extensive brainstorming and validation (January 2026), we're executing a strategic pivot from an infinite-scroll "Feed-First" experience to a "Digest-First" experience. Users receive exactly 5 curated articles per day from their trusted sources, creating a satisfying "finished" state rather than endless scrolling.

**Current Pivot**: Epic 10 "Digest Central" — transforming the app to deliver a personalized daily digest with closure experience, while safely reusing existing backend logic (Personalization, RSS sync, Source management) to minimize codebase disruption.

## Core Value

**Users must feel "finished" and informed in 2-4 minutes, not overwhelmed by infinite content.** If the closure experience fails, nothing else matters.

## Requirements

### Validated

(Existing capabilities to leverage — already working in codebase)
- ✓ User authentication (Supabase Auth) — existing
- ✓ Source management (catalogue + custom RSS) — existing
- ✓ RSS synchronization engine — existing
- ✓ Personalization system (mute topics/sources) — existing, will adapt for "Not Interested"
- ✓ Content scoring algorithm (V2/V3) — existing
- ✓ User profiles & onboarding — existing
- ✓ Streak tracking system — existing, will extend for "closure streak"

### Validated (Previous Milestone: Epic 10)

- ✓ **DIG-01 through DIG-13**: Digest Central MVP — Phase 1 & 2 complete (2026-02-07)
  - Database migrations, DigestSelector service, API endpoints
  - Flutter digest screen, actions, closure experience
  - Feed relegation and navigation

## Active

**Milestone v1.0.1: Digest Production Fixes**

- [ ] **FIX-01**: Add digest generation job to scheduler (8am daily)
- [ ] **FIX-02**: Implement source diversity with decay factor 0.70
- [ ] **FIX-03**: Verify fixes with comprehensive testing

**Previous (Deferred to v1.1):**
- [ ] **DIG-14**: Morning push notification "Digest ready" (8h) — Phase 3 Polish

### Out of Scope

- ❌ Multiple digest types (Zen, Tech, etc.) — V2
- ❌ Algorithmic discovery within digest — V2
- ❌ Real-time sentiment analysis — too costly for MVP
- ❌ In-app reading mode — future consideration
- ❌ Complex ML retraining from digest actions — use existing Personalization

## Context

**Why this pivot?**
- Original infinite feed created decision fatigue and doom-scrolling guilt
- User interviews showed desire for "being done" with news consumption
- 5-article constraint forces quality curation over quantity
- "Closure" feeling differentiates from all competitors (Feedly, Deepstash, etc.)

**Technical Philosophy: Safe Reuse**
This pivot intentionally reuses existing systems:
- **RSS sync**: No changes — already syncs every 30min
- **Scoring algorithm**: No changes — use existing V2/V3 layers
- **Personalization**: Adapt, don't rebuild — "Not Interested" reuses existing mute logic
- **Source management**: No changes — digest pulls from same `user_sources` table
- **Database**: Extend, don't replace — add `daily_digest` alongside existing tables

**Risk Mitigation**
- If digest doesn't resonate, feed remains accessible via "Explorer plus"
- No breaking changes to existing user data or flows
- Can A/B test digest vs feed for new users

## Constraints

- **Tech stack**: Flutter + FastAPI + PostgreSQL (Supabase) — locked, no changes
- **Existing codebase**: Must minimize disruption — leverage existing Personalization, RSS, Scoring systems
- **Timeline**: ~35h for MVP core (backend ~20h, frontend ~15h)
- **Scope**: Single digest only, no multi-category for MVP
- **User data**: Preserve existing user preferences, sources, reading history

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 5 articles per day | Creates "finished" state; manageable cognitive load; ~2-4min completion | — Pending |
| Sources declared only | User control and transparency; builds trust | — Pending |
| Read/Save/Not Interested | Reuses existing Personalization logic; reduces user frustration vs binary | — Pending |
| Feed relegated (not removed) | Safety valve for users wanting more; validates core hypothesis without risk | — Pending |
| Defer "Zen" Essential to V2 | Sentiment analysis too costly/complex for MVP; single digest validates core concept first | ✓ Confirmed |
| Reuse existing scoring (V2/V3) | No algorithm changes needed; DigestSelector uses existing layers | ✓ Confirmed |

## Current Milestone: v1.0.1 — Digest Production Fixes

**Goal:** Fix 2 critical bugs blocking production release

**Target features:**
- Job scheduler integration for daily digest generation at 8am
- Source diversity algorithm with decay factor
- Verification tests for both fixes

**Timeline:** ~4-6 hours

---

*Last updated: 2026-02-07 after starting v1.0.1 production fixes milestone*
