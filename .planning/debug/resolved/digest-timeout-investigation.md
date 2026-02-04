# Debug Investigation - Digest Loading Timeout

**Status:** Active Investigation  
**Issue:** API request to `/api/digest` times out after 30s even with valid token  
**Environment:** Production (Railway)  
**Last Test:** 2026-02-03

---

## Problem Summary

1. ✅ Token is correctly attached (logs show "ApiClient: Attaching token eyJhbGciOi...")
2. ✅ Authentication is working
3. ❌ Request to `GET /api/digest` times out after 30 seconds
4. ❌ Same issue in production and local backend

**Root Cause Hypothesis:** 
- Database query in digest generation is hanging
- Missing indexes causing slow queries
- User has no sources / special condition causing infinite loop

---

## Quick Test Commands

### Test 1: Direct API Call with Curl
```bash
# Replace YOUR_JWT_TOKEN with actual token from app logs
curl -v https://facteur-production.up.railway.app/api/digest \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -m 60
```

### Test 2: Check If Specific User Has Sources
```sql
-- Run in Supabase SQL Editor
SELECT 
    up.user_id,
    up.onboarding_completed,
    COUNT(us.source_id) as source_count
FROM user_profiles up
LEFT JOIN user_sources us ON up.user_id = us.user_id
WHERE up.user_id = 'USER_ID_HERE'
GROUP BY up.user_id, up.onboarding_completed;
```

### Test 3: Test Feed Endpoint (Known Working)
```bash
# Replace YOUR_JWT_TOKEN
curl -v https://facteur-production.up.railway.app/api/feed \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -m 10
```

---

## Investigation Steps

### Step 1: Verify Token Works for Other Endpoints
Test if the token works for other API endpoints that don't involve digest generation:
- `/api/feed` - Should return articles
- `/api/users/profile` - Should return user profile
- `/api/streaks` - Should return streak info

If these also timeout → Token/session issue or backend is down  
If these work → Problem is specific to digest generation

### Step 2: Check User Has Sources
The digest generation requires the user to have sources. If no sources:
- Algorithm tries fallback to curated sources
- May hang if fallback logic has issues

SQL to check:
```sql
SELECT COUNT(*) FROM user_sources WHERE user_id = 'USER_ID';
```

### Step 3: Check Recent Backend Logs
Access Railway dashboard logs for errors:
1. Go to https://railway.app/dashboard
2. Find facteur-production service
3. Check logs for errors during digest requests

Look for:
- SQL errors
- Digest generation timeouts
- "digest_selection_started" but no "digest_selection_completed"

### Step 4: Test With Hardcoded Digest (Bypass Generation)
As a temporary fix to test the UI, we can:
1. Create a mock API endpoint that returns static data
2. Or modify the backend to skip generation and return empty digest

---

## Files to Check

### Backend (packages/api)
- `app/services/digest_service.py` - Main digest logic
- `app/services/digest_selector.py` - Article selection algorithm
- `app/routers/digest.py` - API endpoint

### Frontend (apps/mobile)
- `lib/features/digest/providers/digest_provider.dart` - State management
- `lib/features/digest/repositories/digest_repository.dart` - API calls
- `lib/core/api/api_client.dart` - HTTP client with timeout

---

## Temporary Workaround for UI Testing

To test the UI without waiting for backend fix:

1. **Option A: Use Mock Data**
   Modify `digest_repository.dart` to return mock data instead of API call:
   ```dart
   // Temporary: Return mock data
   return DigestResponse(
     digestId: 'test-123',
     userId: 'user-123',
     targetDate: DateTime.now(),
     generatedAt: DateTime.now(),
     items: _generateMockItems(),
   );
   ```

2. **Option B: Increase Timeout**
   In `api_client.dart`, change:
   ```dart
   connectTimeout: const Duration(seconds: 120), // Instead of 30
   ```

---

## Questions to Answer

1. Does the user have any sources configured?
2. Do other API endpoints work with the same token?
3. What errors appear in Railway backend logs?
4. Is this affecting all users or just this specific user?

---

## Next Actions

**Immediate:**
- [ ] Test feed endpoint to isolate the problem
- [ ] Check Railway logs for backend errors
- [ ] Verify user has sources in database

**If user has no sources:**
- [ ] Complete onboarding flow to add sources
- [ ] Or manually add sources via admin/SQL

**If backend issue:**
- [ ] Investigate digest_selector hanging
- [ ] Check database performance
- [ ] Add timeout handling in digest generation

---

*Created: 2026-02-03*  
*For: Phase 2 Frontend UAT - Test 1*
