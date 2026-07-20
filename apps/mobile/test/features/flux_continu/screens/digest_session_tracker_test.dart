import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/flux_continu/screens/flux_continu_screen.dart';

/// Story 9.8 — garde-fou doomscroll : la comptabilité de session Essentiel.
/// Chrono foreground (suspendu en arrière-plan), complétion de clôture, et
/// émission fire-once. Horloge injectée → 100 % déterministe.
void main() {
  final t0 = DateTime(2026, 7, 18, 9, 0, 0);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  group('DigestSessionTracker', () {
    test('cumule uniquement le temps foreground (arrière-plan exclu)', () {
      final tracker = DigestSessionTracker()..start(at(0));
      // 30 s foreground, 300 s en arrière-plan, 20 s foreground.
      tracker.pause(at(30));
      tracker.resume(at(330));
      final payload = tracker.finish(at(350));

      expect(payload, isNotNull);
      // 30 + 20 = 50 s ; les 300 s d'arrière-plan ne comptent pas.
      expect(payload!.totalTimeSeconds, 50);
    });

    test('elapsedAt n\'inclut pas le temps suspendu', () {
      final tracker = DigestSessionTracker()..start(at(0));
      tracker.pause(at(10));
      // Suspendu : le temps qui passe ne compte plus.
      expect(tracker.elapsedAt(at(999)).inSeconds, 10);
      tracker.resume(at(1000));
      expect(tracker.elapsedAt(at(1005)).inSeconds, 15);
    });

    test('markClosureSeen est idempotent et porté par le payload', () {
      final tracker = DigestSessionTracker()..start(at(0));
      expect(tracker.closureAchieved, isFalse);
      tracker.markClosureSeen();
      tracker.markClosureSeen(); // fire-once implicite (idempotent).
      expect(tracker.closureAchieved, isTrue);

      final payload = tracker.finish(at(5));
      expect(payload!.closureAchieved, isTrue);
    });

    test('sans clôture atteinte → closureAchieved false', () {
      final tracker = DigestSessionTracker()..start(at(0));
      final payload = tracker.finish(at(5));
      expect(payload!.closureAchieved, isFalse);
    });

    test('finish n\'émet qu\'une seule fois (garde fire-once)', () {
      final tracker = DigestSessionTracker()..start(at(0));
      final first = tracker.finish(at(5));
      final second = tracker.finish(at(10));

      expect(first, isNotNull);
      expect(tracker.hasEmitted, isTrue);
      // Deuxième appel (ex. dispose après un finish anticipé) → aucun doublon.
      expect(second, isNull);
    });

    test('durée arrondie aux secondes entières', () {
      final tracker = DigestSessionTracker()..start(t0);
      final payload = tracker.finish(t0.add(const Duration(milliseconds: 1900)));
      // 1,9 s → 1 s (troncature Duration.inSeconds).
      expect(payload!.totalTimeSeconds, 1);
    });
  });
}
