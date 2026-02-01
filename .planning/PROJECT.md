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

### Active

**Epic 10: Digest Central — MVP Scope**

- [ ] **DIG-01**: Database migration from `daily_top3` to `daily_digest` (5 articles, JSONB items)
- [ ] **DIG-02**: `DigestSelector` service — select 5 articles from user's declared sources only
- [ ] **DIG-03**: Diversity constraints (max 2 per source, 2 per theme) in selector
- [ ] **DIG-04**: Fallback to curated sources when user pool insufficient
- [ ] **DIG-05**: API endpoint `GET /api/digest` — retrieve today's digest
- [ ] **DIG-06**: API endpoint `POST /api/digest/{id}/action` — mark Read/Save/Not Interested
- [ ] **DIG-07**: Digest completion tracking (`digest_completions` table)
- [ ] **DIG-08**: Closure streak extension (add to `user_streaks`)
- [ ] **DIG-09**: Flutter digest screen — 5 article cards with progress bar
- [ ] **DIG-10**: Article card actions — Read / Save / Not Interested (reuse Personalization UI patterns)
- [ ] **DIG-11**: Progress bar component (X/5)
- [ ] **DIG-12**: Closure screen — animation, "Tu es informé !", streak update
- [ ] **DIG-13**: Feed relegation — "Explorer plus" button from closure
- [ ] **DIG-14**: Morning push notification "Digest ready" (8h) — optional

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

---

*Last updated: 2026-02-01 after Epic 10 validation session*
