import 'package:facteur/config/routes.dart';
import 'package:facteur/core/auth/auth_state.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/onboarding/providers/onboarding_analytics.dart';
import 'package:facteur/features/onboarding/providers/onboarding_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// Story 31.1 — onboarding sans compte (session anonyme Supabase).
void main() {
  User makeUser({bool isAnonymous = false, String? emailConfirmedAt}) => User(
        id: 'user-123',
        appMetadata: const {'provider': 'email'},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: emailConfirmedAt,
        isAnonymous: isAnonymous,
      );

  group('AuthState.isAnonymous', () {
    test('false sans session', () {
      expect(const AuthState().isAnonymous, isFalse);
    });

    test('true sur une session anonyme', () {
      expect(AuthState(user: makeUser(isAnonymous: true)).isAnonymous, isTrue);
    });

    test('reste true entre la conversion et la confirmation de l\'adresse', () {
      // Supabase ne bascule `is_anonymous` qu'à la confirmation : le marqueur
      // « compte créé » côté client est pendingEmailConfirmation.
      final state = AuthState(
        user: makeUser(isAnonymous: true),
        pendingEmailConfirmation: 'facteur@example.com',
      );
      expect(state.isAnonymous, isTrue);
      expect(state.isEmailConfirmed, isFalse);
    });
  });

  group('Gardes du router', () {
    test('avant conversion : la garde email non confirmé se tait partout', () {
      expect(
        shouldBypassEmailConfirmationGate(
          isAnonymous: true,
          pendingEmailConfirmation: null,
          isOnOnboarding: false,
        ),
        isTrue,
      );
    });

    test('après conversion : bypass seulement sur les écrans d\'onboarding', () {
      expect(
        shouldBypassEmailConfirmationGate(
          isAnonymous: true,
          pendingEmailConfirmation: 'facteur@example.com',
          isOnOnboarding: true,
        ),
        isTrue,
        reason: 'la conclusion doit pouvoir enregistrer le profil',
      );
      expect(
        shouldBypassEmailConfirmationGate(
          isAnonymous: true,
          pendingEmailConfirmation: 'facteur@example.com',
          isOnOnboarding: false,
        ),
        isFalse,
        reason: 'une fois sorti de l\'onboarding, direction /emailConfirmation',
      );
    });

    test('un compte réel non confirmé n\'est jamais exempté', () {
      expect(
        shouldBypassEmailConfirmationGate(
          isAnonymous: false,
          pendingEmailConfirmation: 'facteur@example.com',
          isOnOnboarding: true,
        ),
        isFalse,
      );
    });

    test(
        '« j\'ai déjà un compte » : /login accessible même sur une session '
        'non-anonyme périmée (keychain iOS)', () {
      // Session anonyme fraîche → OK (identique à avant le fix).
      expect(
        canReachLoginBeforeAccount(
          isAnonymous: true,
          needsOnboarding: false,
          pendingEmailConfirmation: null,
        ),
        isTrue,
      );
      // Le cas iOS : session périmée non-anonyme restaurée du keychain, mais
      // qui a encore besoin de faire son onboarding → /login doit rester
      // accessible (sinon le bouton reste inerte, garde 3 rebondit).
      expect(
        canReachLoginBeforeAccount(
          isAnonymous: false,
          needsOnboarding: true,
          pendingEmailConfirmation: null,
        ),
        isTrue,
      );
      // Compte déjà créé, email en attente → on force /emailConfirmation.
      expect(
        canReachLoginBeforeAccount(
          isAnonymous: true,
          needsOnboarding: true,
          pendingEmailConfirmation: 'facteur@example.com',
        ),
        isFalse,
      );
      // Non-anonyme + onboarding terminé → pas une sortie pré-compte.
      expect(
        canReachLoginBeforeAccount(
          isAnonymous: false,
          needsOnboarding: false,
          pendingEmailConfirmation: null,
        ),
        isFalse,
      );
    });
  });

  group('OnboardingState.currentStepName', () {
    test('dérive une clé snake_case de la question courante', () {
      const overview = OnboardingState(
        currentQuestionIndex: 2, // mediaConcentration
      );
      expect(overview.currentStepName, 'media_concentration');

      const section2 = OnboardingState(
        currentSection: OnboardingSection.appPreferences,
        currentQuestionIndex: 1, // independence
      );
      expect(section2.currentStepName, 'independence');

      const section3 = OnboardingState(
        currentSection: OnboardingSection.sourcePreferences,
        currentQuestionIndex: 4, // finalize (v8 : digestMode retirée, 5→4)
      );
      expect(section3.currentStepName, 'finalize');
    });

    test('index hors bornes (reprise Hive d\'une ancienne version) → unknown',
        () {
      const state = OnboardingState(
        currentSection: OnboardingSection.appPreferences,
        currentQuestionIndex: 9,
      );
      expect(state.currentStepName, 'unknown');
    });
  });

  group('OnboardingStepTracker', () {
    test('ouvre le funnel puis enchaîne completed/viewed à chaque étape', () {
      final analytics = _RecordingAnalytics();
      final tracker = OnboardingStepTracker(analytics);

      tracker.onState(const OnboardingState());
      tracker.onState(const OnboardingState(currentQuestionIndex: 1));

      expect(analytics.events, [
        ('onboarding_started', 'intro1', 0),
        ('onboarding_step_viewed', 'intro1', 0),
        ('onboarding_step_completed', 'intro1', 0),
        ('onboarding_step_viewed', 'intro2', 1),
      ]);
    });

    test('un rebuild sans changement d\'étape n\'émet rien', () {
      final analytics = _RecordingAnalytics();
      final tracker = OnboardingStepTracker(analytics);

      tracker.onState(const OnboardingState());
      tracker.onState(const OnboardingState(isTransitioning: true));

      expect(analytics.events, hasLength(2));
    });

    test('une reprise en cours de parcours n\'est pas un nouveau départ', () {
      final analytics = _RecordingAnalytics();
      final tracker = OnboardingStepTracker(analytics);

      tracker.onState(const OnboardingState(currentQuestionIndex: 3));

      expect(analytics.events, [('onboarding_step_viewed', 'objective', 3)]);
    });
  });
}

/// `AnalyticsService.disabled()` avale tout : on intercepte l'appel pour
/// observer la séquence d'events.
class _RecordingAnalytics extends AnalyticsService {
  _RecordingAnalytics() : super.disabled();

  final List<(String, String, int)> events = [];

  @override
  Future<void> trackOnboardingStep({
    required String event,
    required String stepName,
    required int stepIndex,
    required int totalSteps,
  }) async {
    events.add((event, stepName, stepIndex));
  }
}
