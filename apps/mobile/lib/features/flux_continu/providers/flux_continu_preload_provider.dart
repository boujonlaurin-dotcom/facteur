import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import 'flux_continu_provider.dart';

/// Kicks off `fluxContinuProvider.future` in the background as soon as the
/// user is authenticated, email-confirmed and past onboarding — so by the
/// time GoRouter has finished its redirect to `/flux-continu`, the four
/// underlying endpoints (digest/both, top-themes, feed page 1, essentiel)
/// are already in-flight or resolved.
///
/// Mirrors the pattern of `feedPreloadProvider` but targets the home screen.
/// The provider exposes no state — it's a pure side-effect trigger meant to
/// be watched from the top-level widget tree (`FacteurApp`) so it stays
/// active for the entire authenticated session.
///
/// Idempotency: [Ref.read] on an [AsyncNotifierProvider.future] while a build
/// is already in flight returns the pending future instead of starting a new
/// one, so re-triggering on auth state changes is safe.
final fluxContinuPreloadProvider = Provider<void>((ref) {
  final authState = ref.watch(authStateProvider);

  final shouldPreload = authState.isAuthenticated &&
      authState.isEmailConfirmed &&
      !authState.needsOnboarding;

  if (!shouldPreload) return;

  // Fire-and-forget. If a fetch fails, the user will get the normal error
  // flow when they actually land on /flux-continu.
  // ignore: unused_result
  ref.read(fluxContinuProvider.future);
});
