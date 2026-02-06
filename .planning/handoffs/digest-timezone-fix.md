# Fix: Timezone Bug in Digest Algorithm

**Status:** ✅ Ready for Deploy  
**Date:** 2026-02-06  
**Priority:** P0 - Critical  
**Root Cause:** Timezone mismatch between `datetime.utcnow()` and PostgreSQL `timestamptz`

---

## Problem

The digest algorithm was returning only curated sources instead of user's followed sources. All items had score 0.5 (emergency fallback) because scoring operations were failing silently.

## Root Cause

Using `datetime.utcnow()` (timezone-naive) to compare with `content.published_at` (timezone-aware from DB) caused `TypeError` in datetime arithmetic. Exception was caught silently, resulting in all scores = 0.0.

**Bug example:**
```python
# ❌ BROKEN
hours_old = (datetime.utcnow() - content.published_at).total_seconds() / 3600

# ✅ FIXED  
hours_old = (datetime.now(timezone.utc) - content.published_at).total_seconds() / 3600
```

## Files Changed

| File | Lines | Change |
|------|-------|--------|
| `digest_selector.py` | 306, 395, 498, 513 | Use `datetime.now(timezone.utc)` |
| `recommendation/layers/core.py` | 50-67 | Fix timezone comparison logic |
| `recommendation_service.py` | 150 | ScoringContext `now` parameter |
| `briefing_service.py` | 54, 158 | Timezone-aware datetimes |
| `routers/feed.py` | 92 | Lookback window calculation |

## Impact

- **Before:** 0% articles from followed sources, all scores = 0.5
- **After:** Proper scoring with recency bonuses (+30, +25, +15...), followed sources prioritized

## Prevention

**Rule:** Always use `datetime.now(timezone.utc)` when:
1. Comparing with PostgreSQL `timestamptz` columns
2. Performing datetime arithmetic with DB timestamps
3. Creating ScoringContext

**Never mix timezone-aware and timezone-naive datetimes in arithmetic.**

## Post-Deploy Checklist

- [ ] Regenerate digest for test user (force=true)
- [ ] Verify 60%+ articles from followed sources
- [ ] Check scores are diverse (not all 0.5)
- [ ] Monitor for `digest_scoring_failed` errors

---

**Epic:** 10 - Digest Central  
**Deploy:** Required immediately
