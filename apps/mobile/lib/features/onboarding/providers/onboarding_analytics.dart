import '../../../core/services/analytics_service.dart';
import 'onboarding_provider.dart';

/// Instrumentation du funnel d'onboarding (story 31.1).
///
/// Avant, une seule des treize étapes émettait un event : impossible de dire où
/// le parcours se perd, alors que 63 % des installs n'émettent aucun event
/// produit. Plutôt que de saupoudrer des appels dans chaque écran de question,
/// on branche un unique observateur sur les transitions de
/// [OnboardingState] : chaque changement d'étape ferme la précédente
/// (`onboarding_step_completed`) et ouvre la suivante (`onboarding_step_viewed`).
///
/// Volontairement tolérant : un `step_name` déjà vu ne réémet rien (les
/// transitions `isTransitioning` / `showReaction` rebuildent l'état sans changer
/// d'étape), et la reprise Hive d'une position sauvegardée ne fabrique pas de
/// faux abandon puisqu'on ne compte que les transitions observées.
///
/// Le tracker appartient à `OnboardingScreen`, pas au provider : ce dernier est
/// lu par des surfaces hors onboarding (digest, filtres) et le brancher là
/// émettrait un faux `onboarding_started` à chaque cold boot d'un utilisateur
/// déjà installé.
class OnboardingStepTracker {
  OnboardingStepTracker(this._analytics);

  final AnalyticsService _analytics;

  String? _currentStepName;
  int? _currentStepIndex;

  /// À appeler au montage de l'écran d'onboarding puis à chaque changement
  /// d'état du provider.
  void onState(OnboardingState state) {
    final stepName = state.currentStepName;
    if (stepName == 'unknown' || stepName == _currentStepName) return;

    // `_currentStepName` nul = première étape observée : le tracker n'a encore
    // rien ouvert, il n'y a donc pas d'étape précédente à clore.
    final previousStepName = _currentStepName;
    if (previousStepName == null) {
      // `onboarding_started` ne compte que les vrais débuts : une reprise
      // (position restaurée depuis Hive) n'est pas un nouveau parcours.
      if (state.globalQuestionIndex == 0) {
        _analytics.trackOnboardingStep(
          event: 'onboarding_started',
          stepName: stepName,
          stepIndex: state.globalQuestionIndex,
          totalSteps: state.totalSteps,
        );
      }
    } else {
      _analytics.trackOnboardingStep(
        event: 'onboarding_step_completed',
        stepName: previousStepName,
        stepIndex: _currentStepIndex ?? 0,
        totalSteps: state.totalSteps,
      );
    }

    _currentStepName = stepName;
    _currentStepIndex = state.globalQuestionIndex;

    _analytics.trackOnboardingStep(
      event: 'onboarding_step_viewed',
      stepName: stepName,
      stepIndex: state.globalQuestionIndex,
      totalSteps: state.totalSteps,
    );
  }
}
