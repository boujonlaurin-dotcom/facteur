import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/models/onboarding_result.dart';
import 'package:facteur/models/user_profile.dart';

/// Garantit que le résultat d'onboarding transporte bien les compteurs de
/// sources renvoyés par le serveur. C'est ce contrat qui permet à l'app de
/// détecter un écart (sources ignorées) au lieu de l'avaler silencieusement.
void main() {
  UserProfile buildProfile() => UserProfile(
        id: 'profile-1',
        userId: 'user-1',
        ageRange: 'unknown',
        onboardingCompleted: true,
        gamificationEnabled: true,
        weeklyGoal: 5,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  group('OnboardingResult source counters', () {
    test('success carries sources created / requested / skipped', () {
      final result = OnboardingResult.success(
        profile: buildProfile(),
        sourcesCreated: 5,
        sourcesRequested: 7,
        sourcesSkipped: 2,
      );

      expect(result.success, isTrue);
      expect(result.sourcesCreated, equals(5));
      expect(result.sourcesRequested, equals(7));
      expect(result.sourcesSkipped, equals(2));
    });

    test('counters are null when not provided (backward compatible)', () {
      final result = OnboardingResult.success(profile: buildProfile());

      expect(result.sourcesCreated, isNull);
      expect(result.sourcesRequested, isNull);
      expect(result.sourcesSkipped, isNull);
    });

    test('error result has no source counters', () {
      final result = OnboardingResult.error('boom', type: ErrorType.network);

      expect(result.success, isFalse);
      expect(result.sourcesCreated, isNull);
      expect(result.sourcesSkipped, isNull);
    });
  });
}
