# Bug Report: Auth Bounced Silent & Email Delivery Failure

**Status:** FIXED (403 Issue) / PENDING (Email Delivery)  
**Severity:** CRITICAL (Blocker for User Onboarding)  
**Created:** 2026-01-20

## 1. Description
Two interrelated issues affect the authentication flow:
1.  **Race Condition (Fixed):** Users with unconfirmed emails were "silently bounced" back to login without error messages due to a race condition between `_init()` logout and Router redirection.
2.  **Email Delivery / 403 Forbidden (Fixed):** Even after fixing the redirection, users cannot confirm their accounts.
    *   **Infrastructure:** Confirmation emails are not received (suspect Supabase configuration or spam filters).
    *   **Backend Mismatch:** Users manually confirmed in the database (via SQL) still receive `403 Forbidden` ("Email not confirmed") from the backend API. Ideally, the backend should respect `auth.users.email_confirmed_at`.

## 2. Root Cause Analysis
### Bounced Silent (Fixed)
*   **Cause:** `AuthStateNotifier._init()` called `signOut()` for unconfirmed users, which cleared the error state before the UI could display it.
*   **Fix:** Removed explicit `signOut()`, added `forceUnconfirmed` flag, and relied on Router redirection.

### 403 Forbidden Mismatch (Fixed)
*   **Cause:** `refreshUser()` did NOT reset `forceUnconfirmed: false` after successful session refresh. Once 403 set this flag, users were stuck forever.
*   **Fix:** Updated `auth_state.dart` to reset `forceUnconfirmed: false` when refreshed user has valid `email_confirmed_at`.

## 3. Implementation Status
- [x] **Mobile Race Condition:** Fixed via `AuthState.forceUnconfirmed` and Router logic.
- [x] **Localization:** All Auth errors translated to French.
- [x] **Resend Logic:** Centralized in `AuthStateNotifier` with debug logs.
- [x] **Backend 403:** Fixed - `refreshUser()` now resets `forceUnconfirmed: false`.
- [ ] **Infrastructure:** Email delivery reliability needs verification (Supabase config/spam filters).

## 4. Solution (2026-01-20)
```dart
state = state.copyWith(
  user: user,
  forceUnconfirmed: isNowConfirmed ? false : state.forceUnconfirmed,
);
```
