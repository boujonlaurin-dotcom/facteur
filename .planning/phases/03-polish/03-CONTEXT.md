# Phase 03: Polish (Notifications & Analytics) - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Add push notifications for "digest ready" alerts and analytics tracking for MoC (Moment of Completion) metrics — completion rate, time-to-closure, and streak data. This phase does NOT include algorithm improvements or additional notification types.

</domain>

<decisions>
## Implementation Decisions

### Notification timing & delivery
- Send at fixed time: 8am local time
- No user-configurable timing (for MVP)
- Respect system Do Not Disturb settings (iOS handles this)
- No quiet hours logic in app

### Notification content & behavior
- Content: "Votre Brief du Jour est prêt"
- Tap action: Open directly to digest screen (not home)
- Badge: Show '1' when digest is ready (not dynamic article count)
- Sound: Default system notification sound
- No re-engagement prompts if user disables notifications

### Analytics events to track
- Detailed journey tracking:
  - Digest started (screen opened)
  - Article action taken (read/save/not_interested)
  - Digest completed (all 5 articles processed)
  - Time per article (engagement duration)
  - Scroll depth within article
  - Which action types are used most
- Per-digest timestamps only (start and finish times)
- No granular per-article timing breakdown

### Privacy & data handling
- No user-facing analytics controls (standard/expected behavior)
- Pseudonymized tracking with user ID (not fully anonymous)
- Track per-user patterns for streak and engagement analysis
- Aggregate metrics for completion rate calculations

### Claude's Discretion
- Notification permission request timing (onboarding vs first use)
- Analytics event batching strategy
- Data retention period for analytics events
- Performance optimization approach (<500ms target)

</decisions>

<specifics>
## Specific Ideas

- Notification should feel like a gentle nudge, not demanding
- "Votre Brief du Jour est prêt" maintains the app's French voice
- Badge '1' is simple and doesn't create pressure to clear
- Analytics should measure the core MoC metrics from project success criteria

</specifics>

<deferred>
## Deferred Ideas

- Evening reminder notification (e.g., 8pm if digest not completed) — Phase 4+
- Algorithm review/improvement for digest selection — separate technical review phase
- Custom notification sounds — future enhancement
- User-configurable notification times — future enhancement
- Advanced analytics dashboard for users — future phase

</deferred>

---

*Phase: 03-polish*
*Context gathered: 2026-02-05*
