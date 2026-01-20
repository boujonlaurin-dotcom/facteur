# 🛑 Handoff: Authentication Debugging & Solutions

## 📋 Context
- **Project**: Facteur (Flutter Mobile + FastAPI Backend + Supabase).
- **Current Status**: "Infinite Loader" on splash screen is **FIXED**.
- **Current Critical Bug**: User log in -> Authenticated -> Immediately bounced back to Login Screen (Blank) with **NO Error Message**.
- **Previous Critical Bug**: If allowed to pass, User gets **403 Forbidden** on Feed (Backend rejects unconfirmed email).

---

## 🐞 Problem Analysis

### 1. The "Silent Bounce" (Current)
**Symptom**: User logs in, sees nothing, back to login form.
**Root Cause**:
In `AuthStateNotifier._init()` (lib/core/auth/auth_state.dart), we added logic to **Force Logout** if email is not confirmed:
```dart
if (!isConfirmed) {
  await _supabase.auth.signOut(); // <--- Triggers onAuthStateChange(SIGNED_OUT)
  session = null;
  state = state.copyWith(error: 'Veuillez confirmer...'); // <--- SETS ERROR
}
```
**The Conflict**:
`AuthStateNotifier` listens to `_supabase.auth.onAuthStateChange`. When `signOut()` is called, the listener fires and likely **resets the state to a clean unauthenticated state**, wiping out the `error` message we just set.
Result: User is logged out (correct) but sees no message (bad UX).

### 2. The 403 Forbidden (Previous)
**Symptom**: If we let the user through, `ApiClient` receives 403 from Backend.
**Root Cause**:
- **Backend check**: Strict. `payload.get("email_confirmed_at")` MUST be present.
- **Frontend check (`isEmailConfirmed`)**: Loose/Incorrect?
The Mobile App Router allowed the user to go to `/feed`, meaning `authState.isEmailConfirmed` returned `true`, even though the backend rejected the token.

---

## 🛠️ Action Plan for Solution (E2E)

### Step 1: Fix `isEmailConfirmed` Logic
The logic in `lib/core/auth/auth_state.dart` is likely too permissive.
**Task**:
- Inspect `isEmailConfirmed` getter.
- Ensure it returns `false` if `user.emailConfirmedAt` is null (unless provider is NOT email).
- **Goal**: The App MUST agree with Backend. If Backend says 403, App must say `isEmailConfirmed = false`.

### Step 2: Remove "Force Logout" & Use Router
The `Force Logout` logic was a "hark hack" to stop the 403.
**Task**:
- **Revert** the "Force Logout" block in `AuthStateNotifier._init`.
- Instead, rely on the **Router** (`lib/config/routes.dart`).
- The Router ALREADY has logic: `if (!isEmailConfirmed) return RoutePaths.emailConfirmation;`.
- If Step 1 is done correctly (`isEmailConfirmed` returns false), the Router will **automatically** send the user to the `EmailConfirmationScreen`.

### Step 3: Verify `EmailConfirmationScreen`
**Task**:
- Check `lib/features/auth/screens/email_confirmation_screen.dart`.
- Ensure it displays a clear message.
- Ensure it has a **"Resend Email"** button (or add it there).
- This is the correct UX pattern (instead of bouncing to login).

### Step 4: Validate "Resend Email" Feature
**Task**:
- Ensure `AuthStateNotifier.resendConfirmationEmail` is implemented (It is).
- Wire it to the button in `EmailConfirmationScreen`.

---

## 📂 Key Files
- `apps/mobile/lib/core/auth/auth_state.dart` (Logic Hub)
- `apps/mobile/lib/config/routes.dart` (Navigation Guard)
- `apps/mobile/lib/features/auth/screens/login_screen.dart` (Current buggy UI)
- `apps/mobile/lib/features/auth/screens/email_confirmation_screen.dart` (Target UI)
- `packages/api/app/dependencies.py` (Backend Truth)

## ⚠️ Infrastructure Note
- **Local Dev**: Backend runs on `http://localhost:8080`.
- **Supabase**: Ensure `constants.dart` matches the Project ID used by Backend.
