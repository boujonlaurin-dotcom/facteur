import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import 'feed_provider.dart';

/// Kicks off `feedProvider.future` in the background as soon as the user is
/// authenticated, email-confirmed and past onboarding — so by the time they
/// tap the Feed tab, the data (or the cached version of it) is already
/// loaded.
///
/// Should be watched from the top-level widget tree (e.g. `FacteurApp`) so it
/// stays active for the entire authenticated session. The provider itself
/// exposes no state — it's a pure side-effect trigger.
///
/// Idempotency: [Ref.read] on an [AsyncNotifierProvider.future] while a build
/// is already in flight returns the pending future instead of starting a new
/// one, so re-triggering is safe.
final feedPreloadProvider = Provider<void>((ref) {
  final authState = ref.watch(authStateProvider);

  // Preload gates: authenticated + confirmed + past onboarding. The router
  // won't let an un-confirmed / onboarding user land on /feed anyway, so
  // fetching before these gates would be wasted work.
  final shouldPreload = authState.isAuthenticated &&
      authState.isEmailConfirmed &&
      !authState.needsOnboarding;

  if (!shouldPreload) return;

  // Fire-and-forget. If it fails, the user will get the normal error flow
  // when they actually open the Feed tab.
  // ignore: unused_result
  ref.read(feedProvider.future);
});
