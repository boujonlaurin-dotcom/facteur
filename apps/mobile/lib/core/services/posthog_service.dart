import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'package:facteur/config/constants.dart';

/// Wrapper minimal autour du SDK PostHog pour Facteur (Story 14.1).
///
/// Dual-track avec l'analytics maison (`/analytics/events`) : tout passe
/// par [AnalyticsService._logEvent], qui appelle ce service en fire-and-forget.
/// Si [PostHogConstants.isEnabled] est faux (dev sans clé), toutes les
/// méthodes sont des no-op silencieux.
///
/// L'état `_initialized` est statique : le SDK PostHog étant lui-même un
/// singleton global, tous les wrappers (main.dart init + provider Riverpod)
/// partagent le même statut.
class PostHogService {
  static bool _initialized = false;

  bool get isEnabled => PostHogConstants.isEnabled;

  /// Configure et démarre le SDK. Doit être appelé une seule fois au boot.
  Future<void> init() async {
    if (_initialized || !isEnabled) return;
    try {
      final config = PostHogConfig(PostHogConstants.apiKey)
        ..host = PostHogConstants.host
        ..captureApplicationLifecycleEvents = true
        ..debug = kDebugMode;
      await Posthog().setup(config);
      _initialized = true;
    } catch (e) {
      debugPrint('PostHog init failed: $e');
    }
  }

  /// Associe le distinct_id PostHog à l'user Supabase et pose les user
  /// properties de cohorte (acquisition_source, is_creator_ytbeur…).
  Future<void> identify({
    required String userId,
    Map<String, Object>? properties,
  }) async {
    if (!_initialized) return;
    try {
      await Posthog().identify(
        userId: userId,
        userProperties: properties,
      );
    } catch (e) {
      debugPrint('PostHog identify failed: $e');
    }
  }

  /// Capture un event produit.
  Future<void> capture({
    required String event,
    Map<String, Object>? properties,
  }) async {
    if (!_initialized) return;
    try {
      await Posthog().capture(
        eventName: event,
        properties: properties,
      );
    } catch (e) {
      debugPrint('PostHog capture failed ($event): $e');
    }
  }

  /// Reset le distinct_id (appelé au logout pour éviter de mélanger
  /// les comptes sur un même device).
  Future<void> reset() async {
    if (!_initialized) return;
    try {
      await Posthog().reset();
    } catch (e) {
      debugPrint('PostHog reset failed: $e');
    }
  }

  /// Visible pour tests uniquement — reset l'état statique.
  @visibleForTesting
  static void resetForTesting() => _initialized = false;
}
