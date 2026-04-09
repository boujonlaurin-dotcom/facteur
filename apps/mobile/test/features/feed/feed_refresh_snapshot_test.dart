import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';

/// Tests unitaires pour PreviousImpression + FeedSnapshot.
/// Story 4.5b — Feed Refresh Viewport-Aware + Undo.
void main() {
  group('PreviousImpression (JSON round-trip)', () {
    test('fromJson parses content_id + datetime', () {
      final prev = PreviousImpression.fromJson({
        'content_id': 'abc-123',
        'previous_last_impressed_at': '2026-04-01T10:30:00.000Z',
      });

      expect(prev.contentId, 'abc-123');
      expect(prev.previousLastImpressedAt, isNotNull);
      expect(prev.previousLastImpressedAt!.toUtc().year, 2026);
      expect(prev.previousLastImpressedAt!.toUtc().hour, 10);
    });

    test('fromJson handles null previous_last_impressed_at', () {
      final prev = PreviousImpression.fromJson({
        'content_id': 'xyz-789',
        'previous_last_impressed_at': null,
      });

      expect(prev.contentId, 'xyz-789');
      expect(prev.previousLastImpressedAt, isNull);
    });

    test('toJson round-trip preserves contentId and timestamp', () {
      final ts = DateTime.utc(2026, 4, 9, 12, 0, 0);
      final original = PreviousImpression(
        contentId: 'round-trip',
        previousLastImpressedAt: ts,
      );

      final json = original.toJson();
      expect(json['content_id'], 'round-trip');
      expect(json['previous_last_impressed_at'], '2026-04-09T12:00:00.000Z');

      final decoded = PreviousImpression.fromJson(
        json.cast<String, dynamic>(),
      );
      expect(decoded.contentId, original.contentId);
      expect(
        decoded.previousLastImpressedAt?.toUtc(),
        original.previousLastImpressedAt?.toUtc(),
      );
    });

    test('toJson serializes null timestamp as null', () {
      final prev = PreviousImpression(contentId: 'no-ts');
      final json = prev.toJson();

      expect(json['content_id'], 'no-ts');
      expect(json['previous_last_impressed_at'], isNull);
    });
  });

  group('FeedSnapshot', () {
    test('copyWith replaces impressionsBackup only', () {
      final original = FeedSnapshot(
        items: const [],
        carousels: const [],
        page: 3,
        hasNext: true,
        impressionsBackup: const [],
      );

      final updated = original.copyWith(
        impressionsBackup: [
          PreviousImpression(contentId: 'c1'),
          PreviousImpression(contentId: 'c2'),
        ],
      );

      expect(updated.page, 3);
      expect(updated.hasNext, true);
      expect(updated.impressionsBackup.length, 2);
      expect(updated.impressionsBackup.first.contentId, 'c1');
      // Original untouched
      expect(original.impressionsBackup.isEmpty, true);
    });

    test('copyWith without args preserves all fields', () {
      final snap = FeedSnapshot(
        items: const [],
        carousels: const [],
        page: 7,
        hasNext: false,
        impressionsBackup: [PreviousImpression(contentId: 'x')],
      );

      final copy = snap.copyWith();

      expect(copy.page, 7);
      expect(copy.hasNext, false);
      expect(copy.impressionsBackup.length, 1);
      expect(copy.impressionsBackup.first.contentId, 'x');
    });
  });
}
