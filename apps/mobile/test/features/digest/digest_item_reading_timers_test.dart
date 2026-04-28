import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/digest/providers/digest_provider.dart';

/// Sprint 1.2 — per-item timer for digest content_interaction events.
/// Ensures follow-up actions (save/like/dismiss) report a non-zero
/// `time_spent_seconds` while the open event (`read`) stays at 0.
void main() {
  group('DigestItemReadingTimers', () {
    test('consume returns elapsed seconds for follow-up actions', () {
      final timers = DigestItemReadingTimers();
      final opened = DateTime(2026, 4, 24, 10, 0, 0);
      timers.start('article-1', now: opened);

      final saved = timers.consume(
        'article-1',
        'save',
        now: opened.add(const Duration(seconds: 42)),
      );
      expect(saved, 42);
    });

    test('read itself always reports 0s (open event, not duration)', () {
      final timers = DigestItemReadingTimers();
      timers.start(
        'article-1',
        now: DateTime(2026, 4, 24, 10, 0, 0),
      );
      final duration = timers.consume(
        'article-1',
        'read',
        now: DateTime(2026, 4, 24, 10, 5, 0),
      );
      expect(duration, 0);
    });

    test('caps at 1800 seconds (30 min)', () {
      final timers = DigestItemReadingTimers();
      final opened = DateTime(2026, 4, 24, 10, 0, 0);
      timers.start('article-2', now: opened);

      final duration = timers.consume(
        'article-2',
        'save',
        now: opened.add(const Duration(hours: 3)),
      );
      expect(duration, DigestItemReadingTimers.maxSeconds);
    });

    test('returns 0 when no prior read action was recorded', () {
      final timers = DigestItemReadingTimers();
      final duration = timers.consume('article-3', 'save');
      expect(duration, 0);
    });

    test('consume clears the timer to avoid double-counting', () {
      final timers = DigestItemReadingTimers();
      final opened = DateTime(2026, 4, 24, 10, 0, 0);
      timers.start('article-4', now: opened);

      final first = timers.consume(
        'article-4',
        'save',
        now: opened.add(const Duration(seconds: 30)),
      );
      final second = timers.consume(
        'article-4',
        'like',
        now: opened.add(const Duration(seconds: 60)),
      );

      expect(first, 30);
      expect(second, 0, reason: 'Timer must be consumed only once.');
    });

    test('clamps negative elapsed (clock skew) to 0', () {
      final timers = DigestItemReadingTimers();
      final opened = DateTime(2026, 4, 24, 10, 0, 0);
      timers.start('article-5', now: opened);

      final duration = timers.consume(
        'article-5',
        'save',
        now: opened.subtract(const Duration(seconds: 5)),
      );
      expect(duration, 0);
    });
  });
}
