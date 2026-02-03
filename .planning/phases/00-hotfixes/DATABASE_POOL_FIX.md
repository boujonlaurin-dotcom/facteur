# Database Connection Pool Timeout Fix - Summary

## Issue
Railway logs showed:
- "Unable to check out connection from the pool due to timeout"
- "SSL connection has been closed unexpectedly"

These errors occurred when the auth middleware tried to verify `email_confirmed_at` in the database (dependencies.py lines 97-111).

## Root Cause
1. **database.py**: Used `NullPool` with `pool_pre_ping=False`, which doesn't handle connection drops well when connections sit idle and get closed by Railway/Supabase
2. **dependencies.py**: Email verification fallback made direct DB calls without timeout handling or retry logic

## Changes Made

### 1. database.py - Pool Configuration

**Before:**
- `pool_pre_ping=False`
- `poolclass=NullPool`
- No pool size or timeout configuration

**After:**
- Environment-aware pool selection (Railway/Supabase vs Local)
- For Railway/Supabase:
  - `pool_pre_ping=True` - verifies connections before use
  - `poolclass=AsyncAdaptedQueuePool` - proper connection pooling
  - `pool_size=5` - base pool size
  - `max_overflow=10` - additional connections allowed
  - `pool_timeout=30` - fail fast if pool exhausted
  - `pool_recycle=3600` - recycle stale connections after 1 hour
- For Local development: maintain `NullPool` for simplicity

### 2. dependencies.py - Retry Logic

**Added:** `_check_email_confirmed_with_retry()` helper function with:
- **Exponential backoff retry**: 3 attempts with 0.5s, 1s, 2s delays
- **Connection timeout**: 5s per attempt using `asyncio.wait_for()`
- **Exception handling**:
  - `asyncio.TimeoutError` / `SQLAlchemyTimeoutError`: Pool timeout
  - `OperationalError`: SSL connection drops
  - Generic exceptions: No retry
- **Graceful fallback**: Returns False on all failures

**Updated:** Email verification fallback to use new helper function

## Benefits

1. **Connection resilience**: Prevents "SSL connection has been closed unexpectedly"
2. **Pool management**: Properly sized pool with pre-ping prevents checkout timeouts
3. **Graceful degradation**: Auth middleware handles transient DB failures
4. **Minimal impact**: Only affects Railway/Supabase environments, local dev unchanged

## Testing Recommendations

To test connection handling:

1. **Simulate connection drop**:
   ```python
   # Restart Supabase/Railway DB while app is running
   # Verify app recovers on next request
   ```

2. **Load test**:
   ```python
   # Multiple concurrent auth requests
   # Should not exhaust pool or timeout
   ```

3. **Verify logging**:
   - Expected on retry: "⚠️ Auth: DB timeout on attempt X, retrying in Ys..."
   - Expected on success: "✅ Auth: User {id} confirmed in DB (stale JWT)"
   - Expected on failure: "❌ Auth: DB check failed after 3 attempts"

## Files Modified

- `packages/api/app/database.py`
- `packages/api/app/dependencies.py`

## Commit

```
fix: database connection pool timeout handling for Railway/Supabase
- Add pool_pre_ping=True to verify connections before use
- Configure AsyncAdaptedQueuePool for Railway/Supabase environments
- Add retry logic with exponential backoff for email verification
- Handle SSL connection drops and pool timeouts gracefully
```

Hash: `e978308`
