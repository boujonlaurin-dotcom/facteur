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

    test('veille/dashboard (legacy widget link) → flux continu', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://veille/dashboard'),
      );
      expect(action.target, WidgetDeepLinkTarget.veille);
      expect(action.route, '/flux-continu');
    });

    test('veille bare host → flux continu', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://veille'),
      );
      expect(action.target, WidgetDeepLinkTarget.veille);
      expect(action.route, '/flux-continu');
    });

    test('feed host → feed target', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://feed'),
      );
      expect(action.target, WidgetDeepLinkTarget.feed);
      expect(action.route, '/feed');
    });

    test('feed/content/<id> → article reader (Flux deep link)', () {
      final action = DeepLinkService.parse(
        Uri.parse(
          'io.supabase.facteur://feed/content/abc-123?pos=4&topicId=tech',
        ),
      );
      expect(action.target, WidgetDeepLinkTarget.article);
      expect(action.route, '/feed/content/abc-123');
      expect(action.articleId, 'abc-123');
      expect(action.position, 4);
      expect(action.topicId, 'tech');
    });

    test('feed/content/<id> with empty host → article reader', () {
      // Some Android intent shapes drop the host and prepend it as a path
      // segment instead. Both shapes should resolve to the article reader.
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur:///feed/content/abc-123?pos=7'),
      );
      expect(action.target, WidgetDeepLinkTarget.article);
      expect(action.route, '/feed/content/abc-123');
      expect(action.articleId, 'abc-123');
      expect(action.position, 7);
    });

    test('feed/content/ (id missing) falls back to feed target', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://feed/content/'),
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
