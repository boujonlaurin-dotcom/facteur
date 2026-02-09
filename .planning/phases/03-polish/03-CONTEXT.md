# Phase 3: Polish - Context

**Gathered:** 2026-02-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Add push notifications, digest analytics, comprehensive tests, and performance optimization. From ROADMAP: POLISH-01 through POLISH-04.

**Key reframe from user:** Analytics must be a unified system across feed and digest — not two parallel tracking systems. Feed is a "learning center" that feeds into digest recommendations. One pool of content interaction data, one system to maintain.

</domain>

<decisions>
## Implementation Decisions

### Unified content interaction events
- **One event type for all content interactions** — e.g. `content_interaction` — regardless of surface (feed or digest)
- Each event carries a `surface` field (`feed`, `digest`) for context, but the core schema is identical
- Tracked actions: `read`, `save`, `dismiss`, `pass` (skip/next without acting)
- Payload must include: `content_id`, `source_id`, `topics`, `surface`, `position` (if applicable), `time_spent_seconds`
- This replaces the current fragmented approach (`article_read`, `feed_scroll` as separate islands)

### "Pass" as a negative signal
- Skipping an article (next without acting) is an explicit signal — it should penalize the related topic/source in recommendations
- **Research needed:** How do GAFAM platforms distinguish implicit pass (scroll past) vs explicit skip? What thresholds define "seen but ignored"? Researcher should investigate industry standard approaches for implicit negative signals.

### Session-level events stay surface-specific
- Digest closure and feed scroll sessions are genuinely different behaviors — no need to merge them into one event shape
- Digest session: articles count, breakdown by action (read/saved/dismissed/passed), total time, closure achieved yes/no, streak
- Feed session: scroll depth %, items viewed, items interacted with, total time
- Both session types still reference the unified `content_interaction` events underneath

### Forward-compatible schema for atomic themes
- Camembert-based atomic theme extraction is coming next (draft exists) — it will extract fine-grained subjects from articles
- Analytics event schema must accommodate `atomic_themes: []` field from day one (nullable/optional), so when enrichment lands, no schema migration needed
- Today: events carry `topics` (existing RSS-level tags) and `content_id` + `source_id`
- Tomorrow: events also carry `atomic_themes` extracted by Camembert — same events, richer data

### Align with industry standards
- **Research needed:** Researcher should investigate GAFAM recommendation/analytics patterns — specifically how major platforms model content interaction signals, implicit vs explicit feedback, and engagement scoring
- The goal is not to invent a custom system but to follow proven patterns that scale

### Claude's Discretion
- Exact event naming conventions (e.g. `content_interaction` vs `content_event`)
- How to migrate existing `article_read` / `feed_scroll` events to new unified model (backward-compatible wrapper vs clean break)
- Backend query helpers and metrics endpoint structure
- Mobile implementation details (provider wiring, when to fire events)

</decisions>

<specifics>
## Specific Ideas

- "Use feed as a learning center to improve digest recommendations" — feed and digest are two surfaces of the same content understanding system, not separate features
- "I don't see a clear difference in what we want to learn from digest & feed" — any distinction in tracking should be contextual (surface field), not structural (different event types)
- "If the user passes on an article, the related article (atomic theme, theme and/or source) gets a malus" — skip/pass is first-class negative signal
- "Align with top industry standards (GAFAM)" — don't reinvent, follow proven patterns

</specifics>

<deferred>
## Deferred Ideas

- **Camembert atomic theme extraction** — enrichment pipeline that extracts fine-grained subjects from articles. Analytics schema should be ready for it, but the extraction itself is a future phase.
- **Recommendation engine tuning based on analytics** — using the unified interaction data to actually adjust digest selection. This phase tracks; a future phase acts on the data.
- **"What the user will want to learn" prediction** — user acknowledged this is beyond analytics (which tracks what happened) into prediction territory. Future phase.

</deferred>

---

*Phase: 03-polish*
*Context gathered: 2026-02-08*
