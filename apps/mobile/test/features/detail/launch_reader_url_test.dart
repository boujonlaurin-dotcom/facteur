import 'package:facteur/features/detail/screens/content_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Records a single launchUrl invocation so tests can assert the exact mode
/// and window target the reader chose.
class _LaunchCall {
  _LaunchCall(this.uri, this.mode, this.webOnlyWindowName);
  final Uri uri;
  final LaunchMode mode;
  final String? webOnlyWindowName;
}

void main() {
  group('launchReaderUrl', () {
    final uri = Uri.parse('https://lemonde.fr/article/abc?secret=token');

    test('web branch opens immediately in _blank without canLaunchUrl', () async {
      final calls = <_LaunchCall>[];
      var canLaunchCalled = false;

      final ok = await launchReaderUrl(
        uri,
        isWeb: true,
        canLaunch: (u) async {
          canLaunchCalled = true;
          return true;
        },
        launch: (u, {mode = LaunchMode.platformDefault, webOnlyWindowName}) async {
          calls.add(_LaunchCall(u, mode, webOnlyWindowName));
          return true;
        },
      );

      expect(ok, isTrue);
      expect(canLaunchCalled, isFalse, reason: 'web must not gate on canLaunchUrl');
      expect(calls, hasLength(1));
      expect(calls.single.mode, LaunchMode.platformDefault);
      expect(calls.single.webOnlyWindowName, '_blank');
    });

    test('web branch logs result_false and never throws when launch fails', () async {
      final crumbs = <String>[];

      final ok = await launchReaderUrl(
        uri,
        isWeb: true,
        breadcrumb: (msg, {level = SentryLevel.info, data = const {}}) =>
            crumbs.add(msg),
        launch: (u, {mode = LaunchMode.platformDefault, webOnlyWindowName}) async =>
            false,
      );

      expect(ok, isFalse);
      expect(crumbs, containsAllInOrder(['attempt', 'result_false']));
    });

    test('web branch swallows exceptions and logs them', () async {
      final crumbs = <String>[];

      final ok = await launchReaderUrl(
        uri,
        isWeb: true,
        breadcrumb: (msg, {level = SentryLevel.info, data = const {}}) =>
            crumbs.add(msg),
        launch: (u, {mode = LaunchMode.platformDefault, webOnlyWindowName}) async =>
            throw Exception('blocked'),
      );

      expect(ok, isFalse);
      expect(crumbs, containsAllInOrder(['attempt', 'exception']));
    });

    test('breadcrumb data carries urlHost only, never the full URL', () async {
      Map<String, Object?>? captured;

      await launchReaderUrl(
        uri,
        isWeb: true,
        logData: const {'contentId': 'c1', 'trigger': 'cta'},
        breadcrumb: (msg, {level = SentryLevel.info, data = const {}}) {
          captured ??= data;
        },
        launch: (u, {mode = LaunchMode.platformDefault, webOnlyWindowName}) async =>
            true,
      );

      expect(captured, isNotNull);
      expect(captured!['urlHost'], 'lemonde.fr');
      expect(captured!['isWeb'], true);
      expect(captured!['contentId'], 'c1');
      // No field should leak the full URL (path/query with the secret token).
      for (final value in captured!.values) {
        expect(value.toString(), isNot(contains('secret=token')));
        expect(value.toString(), isNot(contains('/article/abc')));
      }
    });

    test('mobile branch gates on canLaunchUrl and uses externalApplication', () async {
      final calls = <_LaunchCall>[];

      final ok = await launchReaderUrl(
        uri,
        isWeb: false,
        canLaunch: (u) async => true,
        launch: (u, {mode = LaunchMode.platformDefault, webOnlyWindowName}) async {
          calls.add(_LaunchCall(u, mode, webOnlyWindowName));
          return true;
        },
      );

      expect(ok, isTrue);
      expect(calls.single.mode, LaunchMode.externalApplication);
      expect(calls.single.webOnlyWindowName, isNull);
    });

    test('mobile branch returns false and skips launch when canLaunch is false', () async {
      var launched = false;
      final crumbs = <String>[];

      final ok = await launchReaderUrl(
        uri,
        isWeb: false,
        canLaunch: (u) async => false,
        breadcrumb: (msg, {level = SentryLevel.info, data = const {}}) =>
            crumbs.add(msg),
        launch: (u, {mode = LaunchMode.platformDefault, webOnlyWindowName}) async {
          launched = true;
          return true;
        },
      );

      expect(ok, isFalse);
      expect(launched, isFalse);
      expect(crumbs, containsAllInOrder(['attempt', 'result_false']));
    });
  });
}
