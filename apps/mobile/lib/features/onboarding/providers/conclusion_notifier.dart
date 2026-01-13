import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/api/providers.dart';
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

  /// Démarre le processus de conclusion (animation + sauvegarde API)
  Future<void> startConclusion() async {
    state = const ConclusionLoading();
    _apiCompleted = false;
    _animationCompleted = false;

    // 1. Démarrer le timer d'animation minimum (3 secondes)
    _minAnimationTimer = Timer(const Duration(seconds: 3), () {
      _animationCompleted = true;
      _checkCompletion();
    });

    // 2. Démarrer l'appel API (en parallèle de l'animation)
    try {
      await _saveOnboarding();
      _apiCompleted = true;
      _checkCompletion();
    } catch (e) {
      // Annuler le timer et montrer l'erreur immédiatement
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

  /// Sauvegarde les réponses d'onboarding via l'API
  Future<void> _saveOnboarding() async {
    final answers = _ref.read(onboardingProvider).answers;
    final userService = _ref.read(userApiServiceProvider);

    // Logger le début de la sauvegarde
    // ignore: avoid_print
    print('Début sauvegarde onboarding...');

    // Appel API avec le service
    final result = await userService.saveOnboarding(answers);

    if (result.success) {
      // Succès : sauvegarder le profil localement
      await _saveProfileLocally(result.profile!);

      // Marquer les sources sélectionnées comme "de confiance"
      await _trustSelectedSources(answers.preferredSources);

      // Effacer les réponses temporaires d'onboarding
      await _ref.read(onboardingProvider.notifier).clearSavedData();

      // Logger le succès
      // ignore: avoid_print
      print(
        'Onboarding sauvegardé avec succès ! '
        'Profil: ${result.profile!.id}, '
        'Intérêts: ${result.interestsCreated}, '
        'Préférences: ${result.preferencesCreated}',
      );
    } else {
      // Erreur retournée par l'API
      // ignore: avoid_print
      print('Erreur sauvegarde onboarding: ${result.errorMessage}');
      throw Exception(result.friendlyErrorMessage);
    }
  }

  /// Sauvegarde le profil localement après succès API
  Future<void> _saveProfileLocally(UserProfile profile) async {
    try {
      final box = await Hive.openBox('user_profile');
      await box.put('profile', profile.toJson());
      await box.put('onboarding_completed', true);
      await box.put('pending_sync', false); // Synchronisé avec succès

      // ignore: avoid_print
      print('Profil sauvegardé localement');
    } catch (e) {
      // Ignorer les erreurs de cache local
      // ignore: avoid_print
      print('Erreur sauvegarde locale (non-bloquant): $e');
    }
  }

  /// Marque les sources sélectionnées comme "de confiance"
  Future<void> _trustSelectedSources(List<String>? sourceIds) async {
    if (sourceIds == null || sourceIds.isEmpty) return;

    final repository = _ref.read(sourcesRepositoryProvider);

    for (final sourceId in sourceIds) {
      try {
        await repository.trustSource(sourceId);
        // ignore: avoid_print
        print('Source $sourceId marquée comme de confiance');
      } catch (e) {
        // Non-bloquant: continuer même si une source échoue
        // ignore: avoid_print
        print('Erreur trust source $sourceId: $e');
      }
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

    // ignore: avoid_print
    print('Mode dégradé activé : onboarding complété localement uniquement');
  }

  /// Sauvegarde en mode dégradé (local uniquement)
  Future<void> _saveProfileLocallyDegraded() async {
    try {
      final answers = _ref.read(onboardingProvider).answers;
      final box = await Hive.openBox('user_profile');

      // Marquer comme complété localement
      await box.put('onboarding_completed', true);
      await box.put('pending_sync', true); // Flag pour sync future

      // Sauvegarder les réponses pour sync future
      await box.put('answers_backup', answers.toJson());

      // ignore: avoid_print
      print('Mode dégradé : données sauvegardées localement pour sync future');
    } catch (e) {
      // ignore: avoid_print
      print('Erreur sauvegarde locale mode dégradé: $e');
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
