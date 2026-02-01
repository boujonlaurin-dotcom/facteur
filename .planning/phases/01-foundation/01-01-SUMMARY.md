---
phase: "01-foundation"
plan: "01"
subsystem: "api"
tags: ["sql", "sqlalchemy", "postgresql", "jsonb", "epic-10", "digest"]
dependencies:
  requires: []
  provides: ["daily_digest table", "digest_completions table", "closure streak tracking"]
  affects: ["01-02", "01-03", "02-01", "02-02"]
tech-stack:
  added: []
  patterns: ["JSONB for flexible array storage", "Mapped[] annotations"]
file-tracking:
  key-files:
    created:
      - "packages/api/sql/009_daily_digest_table.sql"
      - "packages/api/sql/010_digest_completions_table.sql"
      - "packages/api/sql/011_extend_user_streaks.sql"
      - "packages/api/app/models/daily_digest.py"
      - "packages/api/app/models/digest_completion.py"
    modified:
      - "packages/api/app/models/__init__.py"
      - "packages/api/app/models/user.py"
    deleted: []
decisions:
  - "JSONB items column preferred over separate junction table for simplicity"
  - "Closure tracking separate from activity tracking for distinct gamification paths"
  - "Idempotent migrations with IF NOT EXISTS for safe re-runs"
metrics:
  duration: "80s"
  started: "2026-02-01T19:40:15Z"
  completed: "2026-02-01T19:41:35Z"
---

# Phase 01 Plan 01: Database Schema for Digest System

## Summary

Created the foundational database schema for Epic 10's digest-first experience. Replaced the daily_top3 pattern (3 articles) with a 5-article digest model that creates a sense of "mission accomplished" for users. Implemented idempotent SQL migrations and corresponding SQLAlchemy models following existing codebase patterns.

**Key Deliverables:**
- `daily_digest` table with JSONB items array storing 5 articles
- `digest_completions` table tracking user daily completion stats
- Extended `user_streaks` with closure tracking fields (closure_streak, longest_closure_streak, last_closure_date)

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Create daily_digest table and model | 6d2b560 | 009_daily_digest_table.sql, daily_digest.py, __init__.py |
| 2 | Create digest_completions table and model | 886fa6c | 010_digest_completions_table.sql, digest_completion.py, __init__.py |
| 3 | Extend user_streaks with closure tracking | 6b6fb5a | 011_extend_user_streaks.sql, user.py |

## Schema Design

### daily_digest Table

```sql
CREATE TABLE daily_digest (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    target_date DATE NOT NULL,
    items JSONB NOT NULL DEFAULT '[]'::jsonb,  -- Array of 5 articles
    generated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);
```

**Items JSONB Schema:**
```json
[
  {
    "content_id": "uuid",
    "rank": 1,
    "reason": "À la Une | Sujet tendance | Source suivie",
    "source_slug": "le-monde"
  },
  ...
]
```

**Why JSONB:** Chosen over a junction table for simplicity. The 5-article structure is fixed and the JSONB approach allows atomic updates to the entire digest without complex join operations. Content references are validated at application level.

### digest_completions Table

```sql
CREATE TABLE digest_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    target_date DATE NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    articles_read INTEGER NOT NULL DEFAULT 0,
    articles_saved INTEGER NOT NULL DEFAULT 0,
    articles_dismissed INTEGER NOT NULL DEFAULT 0,
    closure_time_seconds INTEGER,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);
```

**Purpose:** Tracks when users complete their digest for:
- Streak calculations
- Engagement analytics (read/saved/dismissed counts)
- Closure time measurement (UX optimization)

### user_streaks Extension

```sql
ALTER TABLE user_streaks 
    ADD COLUMN closure_streak INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN longest_closure_streak INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN last_closure_date DATE;
```

**Design Rationale:**
- `closure_streak`: Consecutive days of digest completion (feeling "finished")
- `longest_closure_streak`: Maximum ever achieved (achievement tracking)
- `last_closure_date`: Used for streak continuity calculations

**Separation from Activity Streak:** Existing `current_streak` tracks any activity. Closure streak is a distinct gamification path specific to the digest-first experience.

## Technical Details

### Migrations

All migrations are **idempotent** (safe to run multiple times):
- `CREATE TABLE IF NOT EXISTS`
- `CREATE INDEX IF NOT EXISTS`
- `CREATE UNIQUE INDEX IF NOT EXISTS`
- `CREATE POLICY IF NOT EXISTS`
- `ADD COLUMN IF NOT EXISTS`
- `COMMENT ON` for documentation

### Row Level Security (RLS)

| Table | Policy | Access |
|-------|--------|--------|
| daily_digest | SELECT own only | Users read-only their digests |
| digest_completions | SELECT/INSERT/UPDATE own | Users manage their completions |

### SQLAlchemy Models

Both models follow existing patterns:
- `Mapped[]` type annotations (SQLAlchemy 2.0 style)
- `PGUUID` for UUID columns
- Proper `__table_args__` with indexes and constraints
- Type hints with `TYPE_CHECKING` for forward references
- Comprehensive docstrings

### Indexes

| Table | Index | Purpose |
|-------|-------|---------|
| daily_digest | uq_daily_digest_user_date | One digest per user per day |
| daily_digest | ix_daily_digest_user_id | User lookup |
| daily_digest | ix_daily_digest_target_date | Date-based queries |
| digest_completions | uq_digest_completions_user_date | One completion per user per day |
| digest_completions | ix_digest_completions_user_id | User lookup |
| digest_completions | ix_digest_completions_completed_at | Streak calculations |
| user_streaks | ix_user_streaks_last_closure_date | Streak queries |
| user_streaks | ix_user_streaks_closure_streak | Leaderboard queries |

## Deviation from Plan

None - plan executed exactly as written.

## Decisions Made

### 1. JSONB for Items Array

**Decision:** Store the 5 articles as a JSONB array rather than a junction table.

**Rationale:**
- Fixed-size array (always 5 items) makes junction table overkill
- Atomic updates to entire digest (no partial update issues)
- Simpler queries (no joins needed to get full digest)
- Content references validated at application level

**Tradeoff:** Loses referential integrity at database level, gains simplicity.

### 2. Separate Closure Streak

**Decision:** Add closure_streak as new columns rather than reusing existing streak fields.

**Rationale:**
- Existing `current_streak` tracks any activity (reading any article)
- Closure streak is specific to digest completion (different achievement path)
- Allows parallel gamification systems
- Can be deprecated independently if digest model changes

### 3. Idempotent Migrations

**Decision:** Use `IF NOT EXISTS` for all DDL operations.

**Rationale:**
- Safe for multiple runs in development
- Allows rollback and re-application
- Compatible with Supabase SQL console execution

## Verification

### Files Created

- ✅ `packages/api/sql/009_daily_digest_table.sql` (84 lines)
- ✅ `packages/api/sql/010_digest_completions_table.sql` (110 lines)
- ✅ `packages/api/sql/011_extend_user_streaks.sql` (51 lines)
- ✅ `packages/api/app/models/daily_digest.py` (68 lines)
- ✅ `packages/api/app/models/digest_completion.py` (65 lines)

### Files Modified

- ✅ `packages/api/app/models/__init__.py` - Added DailyDigest and DigestCompletion exports
- ✅ `packages/api/app/models/user.py` - Added closure tracking fields to UserStreak

### Commit History

```
6b6fb5a feat(01-01): extend user_streaks with closure tracking
886fa6c feat(01-01): create digest_completions table and model
6d2b560 feat(01-01): create daily_digest table and model
```

## Next Phase Readiness

### Blockers

None - schema ready for implementation.

### Dependencies for Next Plans

| Plan | Depends On | Status |
|------|------------|--------|
| 01-02 | daily_digest table | ✅ Ready |
| 01-03 | digest_completions table | ✅ Ready |
| 02-01 | All tables | ✅ Ready |
| 02-02 | All tables + closure streak | ✅ Ready |

## API Implications

The schema enables these API endpoints:

- `GET /api/v1/digest/today` - Get user's daily digest (uses daily_digest table)
- `POST /api/v1/digest/{id}/complete` - Mark digest complete (uses digest_completions table)
- `GET /api/v1/user/streaks` - Include closure streak in response
- `GET /api/v1/user/closure-progress` - Track progress toward completion

## Notes

- Migrations designed for Supabase PostgreSQL (uses `gen_random_uuid()`, `auth.uid()`)
- No foreign key constraints on content_id in JSONB (intentional - content may be archived)
- `target_date` uses DATE type (not TIMESTAMP) for clean day boundaries
- All timestamp columns include timezone information
