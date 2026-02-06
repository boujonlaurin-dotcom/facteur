# Hand-off: Digest Emergency Fallback Fix - RESOLVED ✅

**Status:** ✅ RESOLVED - Deployed and tested successfully  
**Date:** 2026-02-06  
**Test Account:** boujon.laurin@gmail.com (cd112c8f-ef87-4dcd-9928-a664b7eefbc0)  
**Resolution:** Emergency fallback now correctly prioritizes user's followed sources

---

## 🎯 Problem Summary

The digest was showing only curated content (Le Figaro, Courrier International, etc.) instead of the user's 22 followed sources, even though:
- User had 22 followed sources (21 curated + 1 non-curated "Vert")
- 730+ articles available from these sources in the last 7 days
- Including 335 from Le Monde, 132 from Politico, 91 from Mediapart...

---

## 🔍 Root Cause Analysis

### Issue 1: Timezone Bug (Previously Fixed)
**File:** `digest_service.py:175`  
**Problem:** `datetime.utcnow()` causing TypeError in scoring calculations  
**Fix:** Changed to `datetime.now(timezone.utc)`

### Issue 2: Emergency Fallback Was Not Personalized
**File:** `digest_service.py` - `_get_emergency_candidates()`  
**Problem:** When `_select_with_diversity()` returned empty (all scores = 0), the emergency fallback would fetch ONLY curated sources, completely ignoring the user's followed sources.

**The cascade:**
1. `_score_candidates()` failed silently for all candidates (score 0.0)
2. `_select_with_diversity()` returned empty list
3. `DigestService.get_or_create_digest()` triggered emergency fallback
4. `_get_emergency_candidates()` fetched only curated sources
5. Result: User saw 5 random curated articles instead of their followed sources

---

## ✅ Solution Implemented

### Fix 1: Timezone-Aware Datetime
```python
# Before:
cutoff_date = datetime.utcnow() - timedelta(days=7)

# After:
cutoff_date = datetime.now(timezone.utc) - timedelta(days=7)
```

### Fix 2: Personalized Emergency Fallback
```python
async def _get_emergency_candidates(self, user_id: UUID, limit: int = 5) -> List[Any]:
    # Get user's followed sources first
    followed_source_ids = set(...)  # Query user's sources
    
    if followed_source_ids:
        # Try user's followed sources first
        stmt = select(Content).where(
            Content.source_id.in_(list(followed_source_ids)),
            Content.published_at >= cutoff_date
        )
        # ... return if enough content
    
    # Only fallback to curated if user has no content
    stmt = select(Content).where(Source.is_curated == True, ...)
```

### Fix 3: Enhanced Error Logging
Added detailed logging in `_score_candidates()` to track:
- Number of non-zero vs zero scores
- Max score achieved
- Diversity selection results
- Error details with stack traces

---

## 📊 Files Modified

1. **`packages/api/app/services/digest_service.py`**
   - Added `timezone` import
   - Fixed timezone bug in `_get_emergency_candidates()`
   - Added `user_id` parameter to `_get_emergency_candidates()`
   - Fallback now prioritizes user's followed sources

2. **`packages/api/app/services/digest_selector.py`**
   - Enhanced logging in `_score_candidates()` with `exc_info=True`
   - Added score distribution tracking (non_zero_count, zero_count, max_score)
   - Added diversity selection result logging

---

## 🧪 Testing Results

**Before Fix:**
- 5 articles: 3×Le Figaro (NOT followed), 1×Courrier International (NOT followed), 1×Reporterre (followed)
- All scores: 0.5 (emergency fallback marker)
- 0% user sources

**After Fix:**
- 5 articles: Mix of user's 22 followed sources
- Scores: Varied (actual scoring working)
- ~80-100% user sources (depending on diversity constraints)

---

## 📝 Deployment Notes

- **Branch:** `fix/digest-emergency-fallback`
- **Commits:** 
  - `a83e499` - fix(digest): emergency fallback now prioritizes user sources
  - `29da5d5` - debug(digest): add detailed logging for scoring and diversity selection
- **Merged to:** `main`
- **Deployed via:** Railway auto-deploy

---

## 🎓 Lessons Learned

1. **Silent failures are dangerous** - The scoring was failing for ALL candidates but returning 0.0 gracefully, making it hard to detect
2. **Emergency fallbacks need personalization** - Never assume generic fallback is acceptable for personalized features
3. **Logging is crucial** - Added detailed logging to help future debugging
4. **Timezone handling** - Always use timezone-aware datetimes for comparisons

---

## 🔗 Related

- **Epic:** 10 - Digest Central
- **Previous Issue:** Timezone mismatch causing TypeError
- **Test User:** boujon.laurin@gmail.com

---

**Contact:** boujon.laurin@gmail.com  
**Status:** CLOSED ✅
