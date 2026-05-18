import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/feed/providers/feed_load_phase_provider.dart';

/// Helper local : reproduit la logique de `advanceFeedLoadPhase` mais
/// applicable à un `ProviderContainer` plutôt qu'à un `WidgetRef`.
void _advance(ProviderContainer container, FeedLoadPhase target) {
  final notifier = container.read(feedLoadPhaseProvider.notifier);
  if (target.index > notifier.state.index) {
    notifier.state = target;
  }
}

void main() {
  group('FeedLoadPhase', () {
    test('défaut = critical', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(feedLoadPhaseProvider), FeedLoadPhase.critical);
    });

    test('progression monotonique critical -> postFrame -> idle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      _advance(container, FeedLoadPhase.postFrame);
      expect(container.read(feedLoadPhaseProvider), FeedLoadPhase.postFrame);

      _advance(container, FeedLoadPhase.idle);
      expect(container.read(feedLoadPhaseProvider), FeedLoadPhase.idle);
    });

    test('ne redescend jamais (transitions strictement croissantes)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      _advance(container, FeedLoadPhase.idle);
      expect(container.read(feedLoadPhaseProvider), FeedLoadPhase.idle);

      _advance(container, FeedLoadPhase.postFrame);
      expect(container.read(feedLoadPhaseProvider), FeedLoadPhase.idle);

      _advance(container, FeedLoadPhase.critical);
      expect(container.read(feedLoadPhaseProvider), FeedLoadPhase.idle);
    });

    test('idempotent pour la même phase', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      _advance(container, FeedLoadPhase.postFrame);
      final stateBefore = container.read(feedLoadPhaseProvider);

      _advance(container, FeedLoadPhase.postFrame);
      expect(container.read(feedLoadPhaseProvider), stateBefore);
    });

    test('extension : hasReachedPostFrame / hasReachedIdle', () {
      expect(FeedLoadPhase.critical.hasReachedPostFrame, isFalse);
      expect(FeedLoadPhase.critical.hasReachedIdle, isFalse);

      expect(FeedLoadPhase.postFrame.hasReachedPostFrame, isTrue);
      expect(FeedLoadPhase.postFrame.hasReachedIdle, isFalse);

      expect(FeedLoadPhase.idle.hasReachedPostFrame, isTrue);
      expect(FeedLoadPhase.idle.hasReachedIdle, isTrue);
    });
  });
}
