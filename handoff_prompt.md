# Handoff: Debugging Supabase 405 Method Not Allowed (Release Builds Only)

## 🛑 The Problem
The Flutter Android app receives a **405 Method Not Allowed** error (body empty) when attempting to Login or Signup/Register via Supabase.
- **Scope**: Happens **ONLY in Release builds** (APK). Debug builds work perfectly.
- **Impact**: Users cannot log in or sign up.

## ✅ Investigations & Negative Results (What we know is NOT the cause)
1.  **Environment Variables / Secrets Injection**: PROVEN FALSE.
    - We hardcoded the correct `SUPABASE_URL` and `SUPABASE_ANON_KEY` directly in `constants.dart`. The 405 persists.
2.  **Missing Internet Permission**: PROVEN FALSE.
    - We identified `android.permission.INTERNET` was missing from `src/main/AndroidManifest.xml`. We added it. The 405 persists.
3.  **Supabase Initialization**:
    - App launches without crashing.
    - Debug logs show the correct URL being used: `https://ykuadtelnzavrqzbfdve.supabase.co`

## 🕵️ Current Suspects & Recommended Next Steps
The previous agent (me) hit a wall. Here is the recommended path for the new expert:

### 1. Network Inspection (The "Smoking Gun")
We are blind to what *exactly* is being sent in Release mode.
- **Action**: Use a tool like **HTTP Toolkit**, **Charles Proxy**, or an on-device interceptor (like **Chucker** or **Alice** added temporarily to Release) to capture the exact HTTP Request/Response.
- **What to look for**:
    - Is the method actually `POST`?
    - Is the URL correct (e.g. no double slashes `//` or missing segments)?
    - Is there a 30x Redirect happening before the 405?
    - Are headers being stripped (e.g. `apikey`, `Authorization`)?

### 2. R8 / Minification / Obfuscation
RELEASE builds typically use R8.
- **Action**: Check `apps/mobile/android/app/build.gradle`.
- **Verify**: Is `minifyEnabled true`? (It appeared to be false/default in the file view, but verify).
- **Hypothesis**: If enabled, R8 might be stripping JSON serialization classes used by `gotrue` (Supabase Auth).
- **Fix**: Add `@Keep` rules or update `proguard-rules.pro` for Supabase models.

### 3. User Agent / Firewall
- **Hypothesis**: Supabase (Kong/GoTrue) might be rejecting the default Release User-Agent.
- **Action**: Try overriding the `headers` in `Supabase.initialize` to mimic a standard browser or the working Debug agent.

## 📂 Key Files
- Config: `apps/mobile/lib/config/constants.dart` (Currently has hardcoded credentials for debugging).
- Manifest: `apps/mobile/android/app/src/main/AndroidManifest.xml` (Internet permission was just added).
- Gradle: `apps/mobile/android/app/build.gradle.kts`.

Good luck.
