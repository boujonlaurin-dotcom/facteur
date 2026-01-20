# Bug: Account Creation & Authentication Flow Issues

Several issues have been identified in the authentication and registration flow.

## 1. Missing Registration Confirmation Message
**Problem**: After creating an account, the user is not clearly informed that they need to validate their email.
**Root Cause**: In `lib/features/auth/screens/login_screen.dart`, the app listens for `pendingEmailConfirmation` and pushes the `EmailConfirmationScreen`. However, the app's router also listens for `onAuthStateChange`. When Supabase returns the new user, the router often redirects to the `Home` or `Onboarding` screen immediately, before the manual navigation to the confirmation screen can occur or stay visible.

## 2. Email Validation Link Redirect Error
**Problem**: Clicking "valider" in the validation email leads to an error page instead of redirecting to the app.
**Root Cause**: 
- The app lack explicit deep link handling / callback route for Supabase auth.
- The `redirect_to` URL configured in Supabase might not match what the app expects or what is allowed in the Supabase project settings.

## 3. Unclear Error Messages
**Problem**: Error messages during login/signup are often generic ("Une erreur est survenue") and not helpful for the user.
**Root Cause**: `lib/features/auth/utils/auth_error_messages.dart` has a limited set of translations and falls back to a generic message for many Supabase errors.

## 4. Login Without Email Validation
**Problem**: Users can log in and access the app even if their email is not validated.
**Root Cause**: 
- Supabase setting "Confirm email" might be disabled, OR
- The app's `isAuthenticated` check only verifies the presence of a `User` object without checking the `email_confirmed_at` property.
- The backend API dependencies also don't enforce email confirmation.

# Proposed Fixes
1. **Dedicated Route**: Create a `/email-confirmation` route in GoRouter and use the redirect logic to enforce it if `email_confirmed_at` is null.
2. **Deep Link Support**: Add deep link handling in `main.dart` and `GoRouter` to capture the auth callback.
3. **Enforced Validation**: Update `AuthState.isAuthenticated` and backend dependencies to require email confirmation.
4. **Enhanced Translations**: Update `AuthErrorMessages.dart` with more comprehensive translations.
