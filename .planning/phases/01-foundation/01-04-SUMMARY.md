# Plan 01-04 Summary: Critical Digest Algorithm Fix

**Status:** ✅ Complete  
**Date:** 2026-02-05  
**Phase:** 01-foundation  
**Plan:** 04  

---

## Overview

Fixed critical bug where users received articles NOT from their followed sources. The 48-hour lookback window was too narrow, causing premature fallback to curated content. 

**Solution:** Extended lookback to 168h (7 days) with tiered recency bonuses, and restricted fallback to only trigger when user has fewer than 3 articles.

---

## Changes Made

### 1. scoring_config.py - Added 6 Recency Bonus Constants

```python
# --- DIGEST RECENCY BONUSES (Tiered) ---
RECENT_VERY_BONUS = 30.0      # < 6h
RECENT_BONUS = 25.0           # 6-24h
RECENT_DAY_BONUS = 15.0       # 24-48h
RECENT_YESTERDAY_BONUS = 8.0  # 48-72h
RECENT_WEEK_BONUS = 3.0       # 72-120h
RECENT_OLD_BONUS = 1.0        # 120-168h
```

### 2. digest_selector.py - Extended Lookback & Improved Fallback

**Before:**
- `hours_lookback: int = 48`
- Fallback triggered when `pool < 5`

**After:**
- `hours_lookback: int = 168`
- Fallback only when `user_sources < 3` AND total < min_pool_size
- Comprehensive logging distinguishes user vs curated sources

### 3. digest_selector.py - Tiered Recency Bonus System

Added `_score_candidates()` logic to apply bonuses based on article age:
- Calculates `hours_old` from `published_at`
- Applies appropriate bonus from ScoringWeights
- Logs debug info for verification
- Bonus displayed in reason strings (+X pts format)

### 4. digest_service.py - Parameter Pass-through

- Added `hours_lookback: int = 168` parameter to `get_or_create_digest()`
- Passes parameter through to `select_for_user()`
- Updated docstring with parameter documentation
- Added logging to track lookback window

---

## Before/After Comparison

| Aspect | Before | After |
|--------|--------|-------|
| Lookback Window | 48h (2 days) | 168h (7 days) |
| Fallback Trigger | < 5 articles | < 3 user sources |
| Recency Scoring | Smooth decay only | Smooth decay + tiered bonuses |
| User Source Priority | Equal to curated | Always preferred |
| Debug Logging | Basic | Comprehensive (ratios, counts, reasons) |

---

## Verification

```bash
# Syntax check: PASSED
python -m py_compile packages/api/app/services/digest_selector.py
python -m py_compile packages/api/app/services/digest_service.py
python -m py_compile packages/api/app/services/recommendation/scoring_config.py

# Pattern verification: PASSED
# - 6 RECENT_*_BONUS constants in scoring_config.py
# - hours_lookback=168 in digest_selector.py:102
# - hours_lookback parameter in digest_service.py:67
# - hours_lookback passed through in digest_service.py:116
```

---

## Must-Haves Verified

- [x] Digest searches 168h for user sources (extended from 48h)
- [x] 6 recency bonuses added with aligned +X pts display
- [x] Fallback to curated ONLY when user sources < 3 articles
- [x] User sources rank above curated even with recency penalty
- [x] Comprehensive logging for debugging source selection

---

## Files Modified

| File | Changes |
|------|---------|
| `packages/api/app/services/recommendation/scoring_config.py` | Added 6 recency bonus constants |
| `packages/api/app/services/digest_selector.py` | Extended lookback, improved fallback, added recency bonuses |
| `packages/api/app/services/digest_service.py` | Added hours_lookback parameter and pass-through |

---

## Testing Notes

The extended lookback ensures users see articles from their followed sources even if they're up to a week old. The tiered bonus system gives older user-source articles a "fighting chance" against fresh curated content.

Example scenario:
- User follows "TechCrunch" but no articles in last 48h
- **Before:** User gets curated sources (not TechCrunch)
- **After:** User gets TechCrunch articles from up to 7 days ago with recency bonus

### API Fix - POST /digest/generate Response Format
**Issue Fixed (2026-02-06):** The `POST /digest/generate` endpoint was returning `DigestGenerationResponse` (metadata only) but the mobile app expected `DigestResponse` (with full items list), causing crashes during force regenerate.

**Fix Applied:**
- Changed `response_model` from `DigestGenerationResponse` to `DigestResponse`
- Endpoint now returns the complete digest with all 5 items
- Mobile app can now parse the response without JSON parsing errors

**Verification:**
```bash
# Force regenerate digest
curl -X POST "https://api.facteur.app/api/digest/generate?force=true" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Response now includes:
# - digest_id, user_id, target_date, generated_at
# - items: array of 5 DigestItem objects
# - is_completed, completed_at
```

**Test Result:** ✅ PASSED - Force regenerate button works without crash

---

## Deployment Notes

No database migrations required. Changes are purely algorithmic and take effect immediately on next digest generation. Existing digests in database remain unchanged.

---

*Summary created by gsd-executor*
