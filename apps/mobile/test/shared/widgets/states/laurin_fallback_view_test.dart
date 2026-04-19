import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/constants.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/shared/strings/loader_error_strings.dart';
import 'package:facteur/shared/widgets/states/laurin_fallback_view.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: FacteurTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  group('LaurinFallbackView', () {
    testWidgets('renders title, retry and mail button', (tester) async {
      await tester.pumpWidget(_wrap(
        LaurinFallbackView(onRetry: () {}),
      ));

      expect(find.text(LaurinFallbackStrings.title), findsOneWidget);
      expect(
        find.text(LaurinFallbackStrings.retryLabel),
        findsOneWidget,
      );
      expect(find.text(LaurinFallbackStrings.mailLabel), findsOneWidget);
    });

    testWidgets('shows WhatsApp button only when number is configured',
        (tester) async {
      await tester.pumpWidget(_wrap(
        LaurinFallbackView(onRetry: () {}),
      ));

      // Number is empty by default in this branch — see TODO in constants.dart.
      if (LaurinContact.hasWhatsapp) {
        expect(find.text(LaurinFallbackStrings.whatsappLabel), findsOneWidget);
      } else {
        expect(find.text(LaurinFallbackStrings.whatsappLabel), findsNothing);
      }
    });

    testWidgets('invokes onRetry when retry button is tapped', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_wrap(
        LaurinFallbackView(onRetry: () => calls++),
      ));

      await tester.tap(find.text(LaurinFallbackStrings.retryLabel));
      await tester.pump();

      expect(calls, 1);
    });

    testWidgets('mail button copies the prefilled message to the clipboard',
        (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>;
            clipboardText = args['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(_wrap(
        LaurinFallbackView(onRetry: () {}),
      ));

      await tester.tap(find.text(LaurinFallbackStrings.mailLabel));
      await tester.pump();

      expect(clipboardText, LaurinFallbackStrings.prefilledMessage);
    });
  });
}
