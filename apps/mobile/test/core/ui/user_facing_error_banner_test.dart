import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/errors/user_facing_error_notifier.dart';
import 'package:facteur/core/ui/notification_service.dart';
import 'package:facteur/core/ui/user_facing_error_banner.dart';

void main() {
  Widget harness() {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      scaffoldMessengerKey: NotificationService.messengerKey,
      navigatorKey: NotificationService.navigatorKey,
      home: const Scaffold(body: SizedBox.expand()),
    );
  }

  testWidgets('bannière standard : message + CTA « Nous dire »',
      (tester) async {
    await tester.pumpWidget(harness());
    var reportTapped = false;

    UserFacingErrorBanner.show(
      NotificationService.messengerKey.currentState!,
      const UserFacingErrorEvent(
        source: UserErrorSource.http5xx,
        signature: 'sig',
      ),
      onReport: () => reportTapped = true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // entrée slide-in

    expect(find.text('Un truc s\'est mal passé de notre côté.'), findsOneWidget);
    expect(find.text('Nous dire'), findsOneWidget);

    await tester.tap(find.text('Nous dire'));
    await tester.pump();
    expect(reportTapped, isTrue);
  });

  testWidgets('variante shortAck : ack court, pas de CTA', (tester) async {
    await tester.pumpWidget(harness());

    UserFacingErrorBanner.show(
      NotificationService.messengerKey.currentState!,
      const UserFacingErrorEvent(
        source: UserErrorSource.timeout,
        signature: 'sig',
        shortAck: true,
      ),
      onReport: () {},
    );
    await tester.pump();

    expect(find.text('On est au courant, merci.'), findsOneWidget);
    expect(find.text('Nous dire'), findsNothing);

    // Laisse l'auto-dismiss (1,5s) fermer la bannière → pas de timer pendant.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(find.text('On est au courant, merci.'), findsNothing);
  });

  testWidgets('feuille de report : saisie + Envoyer déclenche onSubmit',
      (tester) async {
    await tester.pumpWidget(harness());
    String? submitted;

    unawaited(
      UserFacingErrorBanner.showReportSheet(
        NotificationService.navigatorKey.currentContext!,
        onSubmit: (comment) async => submitted = comment,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Qu\'est-ce qui s\'est passé ?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'écran blanc');
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(submitted, 'écran blanc');
  });
}
