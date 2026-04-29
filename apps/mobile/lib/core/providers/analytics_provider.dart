import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:facteur/core/api/api_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/core/services/posthog_service.dart';

part 'analytics_provider.g.dart';

/// PostHog wrapper — keepAlive so identify/reset calls persist across rebuilds.
@Riverpod(keepAlive: true)
PostHogService posthogService(PosthogServiceRef ref) {
  return PostHogService();
}

@Riverpod(keepAlive: true)
AnalyticsService analyticsService(AnalyticsServiceRef ref) {
  try {
    final apiClient = ref.watch(apiClientProvider);
    final posthog = ref.watch(posthogServiceProvider);
    return AnalyticsService(apiClient, posthog: posthog);
  } catch (_) {
    // Upstream providers (Supabase-backed apiClient) not available — e.g.
    // widget tests that don't initialize the full harness. Fall back to a
    // no-op instance so every `trackXxx` call silently succeeds.
    return AnalyticsService.disabled();
  }
}
