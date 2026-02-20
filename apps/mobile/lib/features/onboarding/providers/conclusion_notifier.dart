import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../../../models/onboarding_result.dart';
import '../../../models/user_profile.dart';
import '../../../features/sources/providers/sources_providers.dart';
import 'onboarding_provider.dart';

/// État de l'animation de conclusion
sealed class ConclusionState {
  const ConclusionState();
}

class ConclusionLoading extends ConclusionState {
  const ConclusionLoading();
}

class ConclusionSuccess extends ConclusionState {
  const ConclusionSuccess();
}

class ConclusionError extends ConclusionState {
  final String message;
  const ConclusionError(this.message);
}

/// Notifier pour gérer l'animation de conclusion et la sauvegarde
class ConclusionNotifier extends StateNotifier<ConclusionState> {
  ConclusionNotifier(this._ref) : super(const ConclusionLoading());

  final Ref _ref;
  Timer? _minAnimationTimer;
  bool _apiCompleted = false;
  bool _animationCompleted = false;

  static const _maxRetries = 2;
  static const _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  /// Démarre le processus de conclusion (animation + sauvegarde API)
  Future<void> startConclusion() async {
    state = const ConclusionLoading();
    _apiCompleted = false;
    _animationCompleted = false;

    // 1. Démarrer le timer d'animation minimum (10 secondes)
    _minAnimationTimer = Timer(const Duration(seconds: 10), () {
      _animationCompleted = true;
      _checkCompletion();
    });

    // 2. Démarrer l'appel API (en parallèle de l'animation)
    try {
      await _saveOnboardingWithRetry();
      _apiCompleted = true;
      _checkCompletion();
    } catch (e) {
      // Tous les retries ont échoué → montrer l'erreur
      _minAnimationTimer?.cancel();
      state = ConclusionError(e.toString());
    }
  }

  /// Vérifie si on peut passer à l'étape suivante
  void _checkCompletion() {
    // Ne naviguer que si l'API ET l'animation sont terminées
    if (_apiCompleted && _animationCompleted) {
      state = const ConclusionSuccess();
    }
  }

  /// Sauvegarde avec retry automatique pour erreurs transitoires
  Future<void> _saveOnboardingWithRetry() async {
    final answers = _ref.read(onboardingProvider).answers;
    final userService = _ref.read(userApiServiceProvider);

    debugPrint('Début sauvegarde onboarding...');

    OnboardingResult? lastResult;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (attempt > 0) {
        final delay = _retryDelays[attempt - 1];
        debugPrint('Onboarding: retry $attempt/$_maxRetries après ${delay.inSeconds}s...');
        await Future<void>.delayed(delay);
      }

      var result = await userService.saveOnboarding(answers);

      // Si erreur auth (JWT stale), refresh session et réessayer immédiatement
      if (!result.success && result.errorType == ErrorType.auth) {
        debugPrint('Onboarding: erreur auth, tentative de refresh session...');
        try {
          await _ref.read(authStateProvider.notifier).refreshUser();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          debugPrint('Onboarding: session rafraîchie, retry API...');
          result = await userService.saveOnboarding(answers);
        } catch (e) {
          debugPrint('Onboarding: échec refresh session: $e');
        }
      }

      if (result.success) {
        await _saveProfileLocally(result.profile!);
        // Trust sources en parallèle avec timeout (important pour le digest)
        await _trustSelectedSourcesWithTimeout(answers.preferredSources);
        await _ref.read(onboardingProvider.notifier).clearSavedData();

        debugPrint(
          'Onboarding sauvegardé avec succès ! '
          'Profil: ${result.profile!.id}, '
          'Intérêts: ${result.interestsCreated}, '
          'Préférences: ${result.preferencesCreated}',
        );
        return; // Succès, on sort
      }

      lastResult = result;

      // Ne pas retenter les erreurs de validation (données invalides → retry inutile)
      if (result.errorType == ErrorType.validation) {
        break;
      }

      debugPrint(
        'Onboarding: échec tentative ${attempt + 1}/${_maxRetries + 1} '
        '(${result.errorType}): ${result.errorMessage}',
      );
    }

    // Tous les retries ont échoué
    debugPrint('Erreur sauvegarde onboarding après retries: ${lastResult?.errorMessage}');
    throw Exception(lastResult?.friendlyErrorMessage ?? 'Erreur inconnue');
  }

  /// Sauvegarde le profil localement après succès API
  Future<void> _saveProfileLocally(UserProfile profile) async {
    try {
      final box = await Hive.openBox('user_profile');
      await box.put('profile', profile.toJson());
      await box.put('onboarding_completed', true);
      await box.put('pending_sync', false); // Synchronisé avec succès

      debugPrint('Profil sauvegardé localement');
    } catch (e) {
      debugPrint('Erreur sauvegarde locale (non-bloquant): $e');
    }
  }

  /// Marque les sources sélectionnées comme "de confiance" (avec timeout)
  /// Awaité pour que les UserSource existent avant la génération du digest
  Future<void> _trustSelectedSourcesWithTimeout(List<String>? sourceIds) async {
    if (sourceIds == null || sourceIds.isEmpty) return;

    final repository = _ref.read(sourcesRepositoryProvider);

    try {
      await Future.wait(
        sourceIds.map((sourceId) async {
          try {
            await repository.trustSource(sourceId);
            debugPrint('Source $sourceId marquée comme de confiance');
          } catch (e) {
            debugPrint('Erreur trust source $sourceId: $e');
          }
        }),
      ).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('Trust sources timeout (5s) — digest utilisera le fallback');
    } catch (e) {
      debugPrint('Erreur globale trust sources: $e');
    }
  }

  /// Réessayer après une erreur
  Future<void> retry() async {
    await startConclusion();
  }

  /// Mode dégradé : continuer sans sauvegarder
  Future<void> continueAnyway() async {
    // Marquer comme complété localement uniquement (mode dégradé)
    await _saveProfileLocallyDegraded();

    // Marquer l'onboarding comme finalisé
    _ref.read(onboardingProvider.notifier).finalizeOnboarding();

    state = const ConclusionSuccess();

    debugPrint('Mode dégradé activé : onboarding complété localement uniquement');
  }

  /// Sauvegarde en mode dégradé (local uniquement)
  Future<void> _saveProfileLocallyDegraded() async {
    try {
      final answers = _ref.read(onboardingProvider).answers;
      final box = await Hive.openBox('user_profile');

      await box.put('onboarding_completed', true);
      await box.put('pending_sync', true); // Flag pour sync future
      await box.put('answers_backup', answers.toJson());

      debugPrint('Mode dégradé : données sauvegardées localement pour sync future');
    } catch (e) {
      debugPrint('Erreur sauvegarde locale mode dégradé: $e');
    }
  }

  @override
  void dispose() {
    _minAnimationTimer?.cancel();
    super.dispose();
  }
}

/// Provider du notifier de conclusion
final conclusionNotifierProvider =
    StateNotifierProvider.autoDispose<ConclusionNotifier, ConclusionState>(
  (ref) => ConclusionNotifier(ref),
);
