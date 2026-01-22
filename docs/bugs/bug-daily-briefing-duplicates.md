# Bug: Daily Briefing Generation Duplicates & Scheduling

**Date:** 2026-01-22  
**Status:** Diagnosed  
**Severity:** Medium  

## Summary

The Daily Top 3 Briefing generation has two issues:

1. **Duplicate entries** - Some users receive 6 briefing items instead of 3 due to a race condition
2. **Inconsistent execution** - Users reported not receiving their briefing this morning (Jan 22)

## Root Cause Analysis

### Issue 1: Duplicate Entries

**Cause:** The idempotency check in `top3_job.py` (lines 139-146) uses `SELECT` before `INSERT` 
but doesn't commit after each user. If the job is triggered multiple times or if there's any 
retry mechanism, duplicates can be inserted.

```python
# Current code - not atomic
exists_stmt = select(DailyTop3).where(...)
if (await session.execute(exists_stmt)).first():
    continue
# ... generate and add items ...
# Commit happens OUTSIDE the user loop at line 229
await session.commit()
```

### Issue 2: Scheduling Confusion

**Observation:** Yesterday (Jan 21) had 30 items generated at **10:22 UTC** (manual trigger), 
not at 7:00 UTC (8:00 Paris) as expected. Today (Jan 22) the job ran at 7:00 UTC correctly.

**Possible causes:**
- Railway deployment may have restarted between yesterday's scheduled time and today
- The scheduler might not persist across restarts (APScheduler in-memory state)
- Yesterday was the first day after the feature was deployed

## Evidence

**Jan 21:**
- 30 items for 10 users, generated at 10:22:57 UTC (manual)

**Jan 22:**
- 48 items total (should be 36 for 12 users)
- 8 users have 3 items each (correct)
- 4 users have 6 items each (duplicates)
- Generated at 07:00:00 UTC (automated + duplicate)

## Reproduction

```bash
cd /Users/laurinboujon/Desktop/Projects/Work Projects/Facteur/packages/api
source venv/bin/activate && python scripts/inspect_full_briefings.py
```

## Impact

- Some users see duplicate articles in their briefing
- Database bloat from extra rows
- Potential confusion in the mobile app when displaying briefing

## Files Impacted

- `packages/api/app/workers/top3_job.py` (main fix)
- `packages/api/app/models/daily_top3.py` (optional: add unique constraint)
