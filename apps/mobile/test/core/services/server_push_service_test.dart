import 'package:facteur/core/services/server_push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerPushService.timeToOpenSeconds', () {
    final now = DateTime.utc(2026, 7, 18, 8, 0, 0);

    test('computes delay from ISO UTC sent_at', () {
      expect(
        ServerPushService.timeToOpenSeconds('2026-07-18T07:58:30+00:00', now),
        90,
      );
    });

    test('null or empty sent_at returns null', () {
      expect(ServerPushService.timeToOpenSeconds(null, now), isNull);
      expect(ServerPushService.timeToOpenSeconds('', now), isNull);
    });

    test('unparseable sent_at returns null (vieux payloads)', () {
      expect(ServerPushService.timeToOpenSeconds('pas-une-date', now), isNull);
    });

    test('sent_at in the future returns null (horloge décalée)', () {
      expect(
        ServerPushService.timeToOpenSeconds('2026-07-18T08:05:00+00:00', now),
        isNull,
      );
    });
  });
}
