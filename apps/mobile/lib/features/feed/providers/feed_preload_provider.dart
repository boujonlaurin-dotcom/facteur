import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import 'feed_provider.dart';

/// R5.1 — minimum age (seconds) of a cached default feed below which the
/// preload is a no-op. The mobile cache TTL is 10 min and the backend
/// page-1 cache TTL is 30 s, so when the local cache is fresh (< 60 s)
/// triggering the preload would just hit the backend cache for nothing,
/// inflating the volume of `/api/feed/` calls. See
/// `docs/bugs/bug-infinite-load-requests.md` (Round 5).
const int _preloadSkipIfCacheYoungerThanSeconds = 60;

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

  // R5.1 — Skip preload when the local cache was just refreshed: the
  // user almost certainly has the feed data already, the next build of
  // `feedProvider` will paint instantly from cache, and we avoid hitting
  // `/api/feed/` for nothing. We only short-circuit on a clearly fresh
  // entry — anything older than the threshold proceeds to preload.
  final userId = authState.user?.id;
  final cache = ref.read(feedCacheServiceProvider);
  if (userId != null && cache != null) {
    final cached = cache.readRaw(userId);
    if (cached != null) {
      final age = DateTime.now().difference(cached.savedAt).inSeconds;
      if (age < _preloadSkipIfCacheYoungerThanSeconds) {
        return;
      }
    }
  }

  // Fire-and-forget. If it fails, the user will get the normal error flow
  // when they actually open the Feed tab.
  // ignore: unused_result
  ref.read(feedProvider.future);
});
