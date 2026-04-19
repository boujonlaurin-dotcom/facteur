import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/shared/strings/loader_error_strings.dart';
import 'package:facteur/shared/widgets/states/friendly_error_view.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: FacteurTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  group('FriendlyErrorView', () {
    testWidgets('renders network message when error mentions socket',
        (tester) async {
      await tester.pumpWidget(_wrap(
        FriendlyErrorView(
          error: Exception('SocketException: connection failed'),
          onRetry: () {},
        ),
      ));

      expect(find.text(FriendlyErrorStrings.networkTitle), findsOneWidget);
      expect(find.text(FriendlyErrorStrings.networkSubtitle), findsOneWidget);
      expect(find.text(FriendlyErrorStrings.retryLabel), findsOneWidget);
    });

    testWidgets('renders timeout message for TimeoutException', (tester) async {
      await tester.pumpWidget(_wrap(
        FriendlyErrorView(
          error: TimeoutException('took too long'),
          onRetry: () {},
        ),
      ));

      expect(find.text(FriendlyErrorStrings.timeoutTitle), findsOneWidget);
    });

    testWidgets('renders 503 message for service unavailable',
        (tester) async {
      await tester.pumpWidget(_wrap(
        FriendlyErrorView(
          error: Exception('HTTP 503 service unavailable'),
          onRetry: () {},
        ),
      ));

      expect(find.text(FriendlyErrorStrings.serverDownTitle), findsOneWidget);
    });

    testWidgets('falls back to generic message for unknown errors',
        (tester) async {
      await tester.pumpWidget(_wrap(
        FriendlyErrorView(
          error: Exception('something weird'),
          onRetry: () {},
        ),
      ));

      expect(find.text(FriendlyErrorStrings.genericTitle), findsOneWidget);
    });

    testWidgets('invokes onRetry when retry button is tapped', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_wrap(
        FriendlyErrorView(
          error: Exception('boom'),
          onRetry: () => calls++,
        ),
      ));

      await tester.tap(find.text(FriendlyErrorStrings.retryLabel));
      await tester.pump();

      expect(calls, 1);
    });
  });
}
