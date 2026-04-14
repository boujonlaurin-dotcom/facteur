import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('learningCheckpointShownThisSessionProvider', () {
    test('S1 — ProviderContainer fresh → false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(learningCheckpointShownThisSessionProvider),
          isFalse);
    });

    test('S2 — après state = true → true (jusqu\'à dispose)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(learningCheckpointShownThisSessionProvider.notifier)
          .state = true;

      expect(container.read(learningCheckpointShownThisSessionProvider),
          isTrue);
    });

    test('S3 — nouveau ProviderContainer → false (simule cold start)', () {
      final firstContainer = ProviderContainer();
      firstContainer
          .read(learningCheckpointShownThisSessionProvider.notifier)
          .state = true;
      firstContainer.dispose();

      final freshContainer = ProviderContainer();
      addTearDown(freshContainer.dispose);
      expect(freshContainer.read(learningCheckpointShownThisSessionProvider),
          isFalse);
    });
  });
}
