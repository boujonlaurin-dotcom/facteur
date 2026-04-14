import 'package:facteur/features/learning_checkpoint/config/learning_checkpoint_flags.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_cooldown_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('learningCheckpointCooldownProvider', () {
    test('C1 — pas de timestamp → false (pas de cooldown)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final active =
          await container.read(learningCheckpointCooldownProvider.future);
      expect(active, isFalse);
    });

    test('C2 — timestamp < 24h → true (cooldown actif)', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final oneHourAgo = nowMs - const Duration(hours: 1).inMilliseconds;
      SharedPreferences.setMockInitialValues({
        LearningCheckpointFlags.kLastActionAtKey: oneHourAgo,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final active =
          await container.read(learningCheckpointCooldownProvider.future);
      expect(active, isTrue);
    });

    test('C3 — timestamp > 24h → false (cooldown expiré)', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final twentyFiveHoursAgo =
          nowMs - const Duration(hours: 25).inMilliseconds;
      SharedPreferences.setMockInitialValues({
        LearningCheckpointFlags.kLastActionAtKey: twentyFiveHoursAgo,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final active =
          await container.read(learningCheckpointCooldownProvider.future);
      expect(active, isFalse);
    });

    test('C4 — timestamp exactement 24h → false (borne supérieure exclue)',
        () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final exactly24h = nowMs - const Duration(hours: 24).inMilliseconds;
      SharedPreferences.setMockInitialValues({
        LearningCheckpointFlags.kLastActionAtKey: exactly24h,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final active =
          await container.read(learningCheckpointCooldownProvider.future);
      // elapsed < 24h → false. À la borne exactement, elapsed >= 24h → false.
      expect(active, isFalse);
    });
  });
}
