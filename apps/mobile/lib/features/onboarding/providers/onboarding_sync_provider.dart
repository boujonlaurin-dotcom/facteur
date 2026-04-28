import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import 'onboarding_provider.dart';

/// Re-sync onboarding answers saved locally when the previous attempt failed.
///
/// Le notifier `ConclusionNotifier` pose `pending_sync = true` + `answers_backup`
/// dans la box Hive `user_profile` quand tous les retries API échouent. Ce
/// provider observe l'auth et, à chaque passage à l'état authentifié, tente
/// silencieusement un renvoi best-effort. Succès → flags nettoyés. Échec →
/// on réessaiera au prochain lancement.
class OnboardingSyncNotifier extends StateNotifier<void> {
  OnboardingSyncNotifier(this._ref) : super(null) {
    _ref.listen<AuthState>(authStateProvider, (previous, next) {
      final wasAuthenticated = previous?.isAuthenticated ?? false;
      if (!wasAuthenticated && next.isAuthenticated) {
        _attemptResync();
      }
    }, fireImmediately: true);
  }

  final Ref _ref;
  bool _inFlight = false;

  static const _boxName = 'user_profile';
  static const _pendingSyncKey = 'pending_sync';
  static const _answersBackupKey = 'answers_backup';

  Future<void> _attemptResync() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final box = await Hive.openBox(_boxName);
      final pending = box.get(_pendingSyncKey) as bool? ?? false;
      if (!pending) return;

      final rawBackup = box.get(_answersBackupKey);
      if (rawBackup == null) {
        await box.put(_pendingSyncKey, false);
        return;
      }

      final answers = OnboardingAnswers.fromJson(
        Map<String, dynamic>.from(rawBackup as Map),
      );

      debugPrint(
        '[ONBOARDING_TELEMETRY] event=resync_start pending=true',
      );

      final userService = _ref.read(userApiServiceProvider);
      final result = await userService.saveOnboarding(answers);

      if (result.success) {
        await box.put(_pendingSyncKey, false);
        await box.delete(_answersBackupKey);
        if (result.profile != null) {
          await box.put('profile', result.profile!.toJson());
          await box.put('onboarding_completed', true);
        }
        // Resync a écrit le profil côté serveur : forcer la relecture par
        // `authStateProvider` pour que `needsOnboarding` ne reste pas bloqué
        // à `true` (décision prise par `_checkOnboardingStatus` lancé avant
        // que le resync ne termine).
        await _ref
            .read(authStateProvider.notifier)
            .refreshOnboardingStatus();
        debugPrint('[ONBOARDING_TELEMETRY] event=resync_success');
      } else {
        debugPrint(
          '[ONBOARDING_TELEMETRY] event=resync_failed '
          'error_type=${result.errorType} message=${result.errorMessage}',
        );
      }
    } catch (e) {
      debugPrint('[ONBOARDING_TELEMETRY] event=resync_exception error=$e');
    } finally {
      _inFlight = false;
    }
  }
}

/// Provider à watcher depuis `FacteurApp` pour activer la re-sync automatique.
final onboardingSyncProvider =
    StateNotifierProvider<OnboardingSyncNotifier, void>(
  (ref) => OnboardingSyncNotifier(ref),
);
