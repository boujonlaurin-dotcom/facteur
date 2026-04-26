import 'package:facteur/core/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeepLinkService.parse', () {
    test('digest host without article → digest target', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://digest'),
      );
      expect(action.target, WidgetDeepLinkTarget.digest);
      expect(action.route, '/digest');
      expect(action.articleId, isNull);
    });

    test('digest with trailing slash (no article) → digest target', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://digest/'),
      );
      expect(action.target, WidgetDeepLinkTarget.digest);
      expect(action.route, '/digest');
    });

    test('digest host with article id → article reader route', () {
      final action = DeepLinkService.parse(
        Uri.parse(
          'io.supabase.facteur://digest/abc-123?pos=2&topicId=international',
        ),
      );
      expect(action.target, WidgetDeepLinkTarget.article);
      expect(action.route, '/feed/content/abc-123');
      expect(action.articleId, 'abc-123');
      expect(action.position, 2);
      expect(action.topicId, 'international');
    });

    test('feed host → feed target', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://feed'),
      );
      expect(action.target, WidgetDeepLinkTarget.feed);
      expect(action.route, '/feed');
    });

    test('login-callback URI is ignored (handled by Supabase SDK)', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://login-callback#access_token=xyz'),
      );
      expect(action.target, WidgetDeepLinkTarget.ignored);
      expect(action.route, isNull);
    });

    test('foreign scheme → unhandled', () {
      final action = DeepLinkService.parse(
        Uri.parse('https://facteur.app/digest'),
      );
      expect(action.target, WidgetDeepLinkTarget.unhandled);
    });

    test('unknown host on facteur scheme → unhandled', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://unknown-target'),
      );
      expect(action.target, WidgetDeepLinkTarget.unhandled);
    });

    test('article id with empty pos query falls back to null position', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://digest/abc?pos='),
      );
      expect(action.target, WidgetDeepLinkTarget.article);
      expect(action.position, isNull);
    });
  });
}
