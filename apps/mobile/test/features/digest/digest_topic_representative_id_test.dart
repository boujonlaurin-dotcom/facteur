import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/models/digest_models.dart';

/// Regression coverage for the 3-counter bias-analysis alignment fix.
/// The new `representative_content_id` JSON field is the pivot used by the
/// backend to compute perspectives. Mobile must:
///  - parse it when present (fresh digests),
///  - tolerate its absence (legacy cached digests).
void main() {
  group('DigestTopic.representativeContentId', () {
    test('parses representative_content_id when present', () {
      final json = {
        'topic_id': 'c1',
        'label': 'Retraites',
        'rank': 1,
        'reason': 'Selected',
        'articles': <dynamic>[],
        'representative_content_id': '11111111-2222-3333-4444-555555555555',
      };

      final topic = DigestTopic.fromJson(json);

      expect(topic.representativeContentId,
          equals('11111111-2222-3333-4444-555555555555'));
    });

    test('falls back to null when representative_content_id is absent', () {
      final json = {
        'topic_id': 'c1',
        'label': 'Legacy topic',
        'rank': 1,
        'reason': 'Selected',
        'articles': <dynamic>[],
      };

      final topic = DigestTopic.fromJson(json);

      expect(topic.representativeContentId, isNull);
    });

    test('roundtrip preserves the field through toJson/fromJson', () {
      final original = DigestTopic(
        topicId: 'c1',
        label: 'Retraites',
        representativeContentId: 'abc-123',
      );

      final restored = DigestTopic.fromJson(original.toJson());

      expect(restored.representativeContentId, equals('abc-123'));
    });
  });
}
