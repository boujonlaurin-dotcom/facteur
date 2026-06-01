import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/widgets/premium_source_connection.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('PremiumSourceConnection completes login test confirmation flow',
      (tester) async {
    var connected = false;
    final source = Source(
      id: 'source-id',
      name: 'Premium Source',
      type: SourceType.article,
      premiumConnection: const PremiumConnection(
        loginUrl: 'https://example.com/login',
        testUrl: 'https://example.com/test',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: PremiumSourceConnection(
          source: source,
          onConnected: () async {
            connected = true;
          },
          webViewBuilder: (_, url) => Center(child: Text(url)),
        ),
      ),
    );

    expect(find.text('Connecter votre abonnement'), findsOneWidget);

    await tester.ensureVisible(find.text('Commencer'));
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('https://example.com/login'), findsOneWidget);

    await tester.ensureVisible(find.text('Continuer vers l\'article test'));
    await tester.tap(find.text('Continuer vers l\'article test'));
    await tester.pumpAndSettle();
    expect(find.text('Article test'), findsOneWidget);
    expect(find.text('https://example.com/test'), findsOneWidget);

    await tester.ensureVisible(find.text('L\'article s\'affiche correctement'));
    await tester.tap(find.text('L\'article s\'affiche correctement'));
    await tester.pumpAndSettle();

    expect(connected, isTrue);
    expect(find.text('Abonnement connecté'), findsOneWidget);
  });
}
