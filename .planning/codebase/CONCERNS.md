# Codebase Concerns

**Analysis Date:** 2026-02-01

## Tech Debt

**Migration Management - Alembic Complexity:**
- Issue: Database migrations are frequently a source of production failures. Multiple migration heads exist and need manual resolution (`a8da35e3c12b_merge_heads.py`). Migration lock timeouts with Supabase pooler require complex workarounds with `autocommit_block` and lock timeout handling.
- Files: `packages/api/alembic/versions/1a2b3c4d5e6f_fix_user_personalization_fk.py`, `packages/api/alembic/env.py`
- Impact: Deployments to Railway frequently fail with "Healthcheck failure" due to migration issues. Currently using `FACTEUR_MIGRATION_IN_PROGRESS` bypass flag.
- Fix approach: Consolidate migrations, implement zero-downtime migration strategy with maintenance windows.

**Debug/Print Statements in Production Code:**
- Issue: Multiple `print()` statements throughout the API codebase for debugging. No centralized logging configuration for production.
- Files: `packages/api/app/routers/feed.py` (lines 108, 110), `packages/api/app/dependencies.py` (line 114), `packages/api/scripts/*.py`
- Impact: Pollutes production logs, makes log aggregation difficult.
- Fix approach: Replace all `print()` with structured logging via `structlog`. Add log level configuration via environment variables.

**TODOs and Unimplemented Features:**
- Issue: Multiple TODO comments indicate incomplete implementations.
- Files:
  - `packages/api/app/services/source_service.py`: `content_count=0` stub (lines 61, 100)
  - `packages/api/app/services/recommendation_service.py`: Reading time calculation (line 525)
  - `packages/api/app/services/briefing_service.py`: Unify context creation with RecService (line 143)
  - `packages/api/app/services/briefing_service.py`: Redis/Memory cache for RSS fetching (line 222)
  - `packages/api/app/services/user_service.py`: Real stats with SQL queries (line 189)
  - `packages/api/app/utils/youtube_utils.py`: Resolve handle to channel ID (line 25)
- Impact: Missing functionality impacts user experience and analytics accuracy.
- Fix approach: Prioritize TODOs by user impact and implement incrementally.

**Large Service Files:**
- Issue: Several service files exceed 300 lines, indicating high complexity and potential for bugs.
- Files:
  - `packages/api/app/services/recommendation_service.py`: 596 lines
  - `packages/api/app/services/sync_service.py`: 419 lines
  - `packages/api/app/services/rss_parser.py`: 323 lines
  - `packages/api/app/services/source_service.py`: 321 lines
- Impact: Hard to test, maintain, and reason about. Single responsibility principle violations.
- Fix approach: Refactor into smaller, focused service classes.

## Known Bugs (Documented)

**Theme Matching Bug (RESOLVED but pattern remains):**
- Issue: Source.theme contained French labels while UserInterest.interest_slug contained normalized slugs. The check `if content.source.theme in context.user_interests` never matched.
- Files: `packages/api/app/services/recommendation/layers/core.py` (fixed)
- Fix: Migration to unify taxonomy, simplified matching logic.
- Pattern Risk: Other areas may have similar label/slug mismatch issues.

**UnboundLocalError in Feed Generation (RESOLVED):**
- Issue: Variables `muted_sources`, `muted_themes`, `muted_topics` were passed to `_get_candidates()` before being defined.
- Files: `packages/api/app/services/recommendation_service.py` (fixed)
- Root Cause: Code reorganization without proper variable initialization order.

**Source Addition 500 Error (RESOLVED):**
- Issue: `source_service.py` used `logger` without importing it, causing NameError on production.
- Files: `packages/api/app/services/source_service.py` (fixed)
- Impact: Complete failure of custom source addition feature.

**Personalization API Foreign Key Violation (IN PROGRESS):**
- Issue: FK mismatch between `user_personalization.user_id` and `user_profiles.id` vs `user_profiles.user_id`.
- Files: `packages/api/app/routers/personalization.py`
- Fix: Migration applied but verification needed in production.

**Daily Briefing Disappearance (IN PROGRESS):**
- Issue: "Essentiels du jour" (Daily Top 3) not appearing for users.
- Files: `packages/api/app/services/briefing_service.py`, `packages/api/app/workers/top3_job.py`
- Hypotheses: Job not running, retrieval mismatch with `generated_at`, candidates empty.

**Authentication Race Conditions (RESOLVED):**
- Issue: Silent bounce for unconfirmed emails, 403 mismatch after manual confirmation.
- Files: `apps/mobile/lib/core/auth/auth_state.dart`
- Fix: `forceUnconfirmed` flag management, DB fallback check for confirmation status.

**Perspective Search Timeout (RESOLVED):**
- Issue: Google News RSS search timing out, no User-Agent, silent exception swallowing.
- Files: `packages/api/app/services/perspective_service.py` (fixed)
- Fix: Added proper User-Agent, timeout increase, explicit error logging.

## Security Considerations

**JWT Token Debugging in Production:**
- Risk: Debug JWT payload printing in `dependencies.py` (line 114) could expose sensitive token data in logs.
- Files: `packages/api/app/dependencies.py`
- Current mitigation: Only prints during auth failures.
- Recommendations: Remove debug printing or gate behind strict log level checks.

**SQL Injection via Raw SQL:**
- Risk: Raw SQL queries in `dependencies.py` (line 102-103) for email confirmation check.
- Files: `packages/api/app/dependencies.py`
- Current mitigation: Uses SQLAlchemy `text()` with parameter binding.
- Recommendations: Migrate to ORM query for consistency and safety.

**User Data Isolation:**
- Risk: Custom sources visible across users (was fixed but indicates pattern risk).
- Files: `packages/api/app/services/source_service.py`, `packages/api/app/routers/sources.py`
- Current mitigation: Unique constraint on `(user_id, source_id)` added.
- Recommendations: Add automated tests verifying per-user data isolation.

## Performance Bottlenecks

**Feed Generation - Multiple Sequential DB Queries:**
- Problem: `get_feed()` in `recommendation_service.py` makes 4 separate DB calls sequentially (user profile, followed sources, subtopics, personalization).
- Files: `packages/api/app/services/recommendation_service.py` (lines 61-94)
- Cause: SQLAlchemy AsyncSession is not thread-safe for concurrent operations.
- Improvement path: Use `asyncio.gather()` with separate sessions, or denormalize frequently accessed data into a cache (Redis).

**Sync Service - RSS Parsing Blocks Event Loop:**
- Problem: `feedparser.parse()` is CPU-bound and synchronous. Called within async context.
- Files: `packages/api/app/services/sync_service.py` (line 108)
- Current mitigation: Offloaded to thread pool with `run_in_executor()`.
- Improvement path: Consider async RSS parser or dedicated worker process.

**NER Service - Temporarily Disabled:**
- Problem: Migration to add `entities` column fails on large `contents` table in Supabase free tier.
- Files: `packages/api/app/services/ml/ner_service.py`, `packages/api/alembic/versions/p1q2r3s4t5u6_add_content_entities.py`
- Cause: `ALTER TABLE` timeout after ~30s, egress limit reached.
- Current state: NER runs but entities not persisted (logged as warning).
- Improvement path: Upgrade Supabase tier or migrate to separate PostgreSQL host.

**Recommendation Scoring - In-Memory Processing:**
- Problem: 500 candidates fetched, scored, sorted, and diversity-ranked entirely in Python memory.
- Files: `packages/api/app/services/recommendation_service.py` (lines 174-199)
- Cause: Complex scoring logic requires full content objects.
- Improvement path: Consider materialized views for pre-computed scores, or caching of scored results.

## Fragile Areas

**Authentication State Management:**
- Files: `apps/mobile/lib/core/auth/auth_state.dart`
- Why fragile: Complex state machine with `forceUnconfirmed`, `remember_me`, race conditions, timeout handling. Multiple bug fixes indicate this area is error-prone.
- Safe modification: Always test with both confirmed and unconfirmed users, various providers (email, social).
- Test coverage: Unit tests exist but may not cover all race condition scenarios.

**Database Migration System:**
- Files: `packages/api/alembic/versions/*`, `packages/api/alembic/env.py`
- Why fragile: Complex deployment environment (Railway + Supabase pooler). Lock timeouts, FK constraint issues, multiple heads.
- Safe modification: Always test migrations on copy of production data. Use maintenance windows for destructive changes.
- Test coverage: No automated migration testing in CI.

**Recommendation Engine:**
- Files: `packages/api/app/services/recommendation_service.py`, `packages/api/app/services/recommendation/layers/*.py`
- Why fragile: Multiple scoring layers, complex context construction, theme matching history. Changes to one layer can affect overall scoring unpredictably.
- Safe modification: Maintain comprehensive test suite in `packages/api/tests/recommendation/`. Use A/B testing for scoring changes.
- Test coverage: 8 tests in `test_core_layer.py`, but coverage of other layers unclear.

**Flutter API Client:**
- Files: `apps/mobile/lib/core/api/api_client.dart`
- Why fragile: Session timing issues, race conditions with Supabase auth state. Workarounds like 100ms delay (line 44) indicate instability.
- Safe modification: Test on both iOS and Android, debug and release modes.
- Test coverage: Limited automated testing of auth integration.

## Scaling Limits

**Database Connection Pool:**
- Current capacity: Supabase free tier connection limits (approx 30-60 concurrent connections)
- Limit: With async operations and pooler PgBouncer, actual limit may be lower due to transaction mode.
- Scaling path: Upgrade to Supabase paid tier or migrate to Railway Postgres.

**Content Table Size:**
- Current capacity: Unknown, but large enough to cause migration timeouts.
- Limit: Free tier storage limits (~500MB).
- Scaling path: Data retention policies, archive old content, or upgrade tier.

**ML Classification Queue:**
- Current capacity: Single-threaded classification worker.
- Limit: Processing speed limited by transformer model inference time.
- Scaling path: Horizontal scaling with multiple workers, or GPU inference.

## Dependencies at Risk

**Supabase (Auth + Database):**
- Risk: Free tier limitations (connection limits, egress, storage) causing production issues.
- Impact: Migration failures, potential downtime, data isolation issues.
- Migration plan: Evaluate Railway Postgres or Neon for database. Keep Supabase for Auth or migrate to Clerk/Auth0.

**Feedparser (Python):**
- Risk: Synchronous library in async context, CPU blocking.
- Impact: Event loop blocking during RSS sync.
- Migration plan: Already mitigated with thread pool, but consider `aiohttp` + `feedparser` alternative.

**httpx (HTTP Client):**
- Risk: Timeout configuration scattered across services (5s, 10s, 30s).
- Impact: Inconsistent timeout behavior, some requests may hang.
- Migration plan: Centralize timeout configuration in `app/config.py`.

## Missing Critical Features

**Comprehensive Test Coverage:**
- Problem: Many debug scripts indicate lack of confidence in test coverage.
- Files: `packages/api/tests/` has tests but many are focused on specific components.
- Missing: Integration tests for full feed generation, end-to-end auth flow tests, migration tests.

**Error Monitoring:**
- Problem: No evidence of Sentry or similar error tracking integration (commented as TODO in `api_client.dart`).
- Impact: Production errors may go unnoticed until users report them.
- Files: `apps/mobile/lib/core/api/api_client.dart` (line 105)

**Rate Limiting:**
- Problem: No rate limiting evident on API endpoints.
- Impact: Potential for abuse, resource exhaustion.
- Files: All router files in `packages/api/app/routers/`

**Backup Strategy:**
- Problem: No documented backup/restore process for production database.
- Impact: Data loss risk in case of critical failure.

## Test Coverage Gaps

**Integration Tests:**
- What's not tested: Full feed generation with real database state, complete onboarding flow.
- Files: Most tests are unit tests with mocked dependencies.
- Risk: Integration failures only caught in production.
- Priority: High

**Mobile E2E Tests:**
- What's not tested: Full user journeys (signup → onboarding → feed usage).
- Files: `apps/mobile/test/` has widget tests but no E2E.
- Risk: UI/UX regressions, navigation issues.
- Priority: Medium

**Migration Tests:**
- What's not tested: Forward and backward migrations, multiple head resolution.
- Files: No migration-specific tests found.
- Risk: Production migration failures.
- Priority: High

**Performance Tests:**
- What's not tested: Feed generation under load, concurrent user scenarios.
- Files: `packages/api/tests/` - no load tests.
- Risk: Performance degradation with user growth.
- Priority: Medium

---

*Concerns audit: 2026-02-01*
