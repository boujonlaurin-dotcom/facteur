import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/services/premium_session_store.dart';
import 'package:facteur/features/sources/widgets/premium_source_connection.dart';

class _FakeCookieJar implements PremiumCookieJar {
  final Map<String, List<Cookie>> store = {};

  @override
  Future<List<Cookie>> getCookies(WebUri url) async =>
      List<Cookie>.of(store[url.host] ?? const []);

  @override
  Future<void> setCookie(
    WebUri url, {
    required String name,
    required String value,
    String? domain,
    String path = '/',
    int? expiresDate,
    bool? isSecure,
    bool? isHttpOnly,
    HTTPCookieSameSitePolicy? sameSite,
  }) async {}

  @override
  Future<void> deleteCookies(WebUri url) async {}
}

class _InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> map = {};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

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

  testWidgets(
      'PremiumSourceConnection gates the login CTA until navigation, then '
      'completes the confirmation flow and captures session at confirm',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var connected = false;
    final jar = _FakeCookieJar();
    // Seed cookies on the media domain so the capture at _confirm persists.
    jar.store['example.com'] = [Cookie(name: 'sid', value: 'abc')];
    final store = PremiumSessionStore(
      jar: jar,
      secureStore: _InMemorySecureStore(),
    );

    final source = Source(
      id: 'source-id',
      name: 'Premium Source',
      type: SourceType.article,
      url: 'https://example.com',
      premiumConnection: const PremiumConnection(
        loginUrl: 'https://example.com/login',
        testUrl: 'https://example.com/test',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [premiumSessionStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: PremiumSourceConnection(
            source: source,
            onConnected: () async {
              connected = true;
            },
            // Le builder de test bypass PremiumWebView : on expose un bouton qui
            // déclenche onLoadStop pour simuler une navigation dans la WebView.
            webViewBuilder: (_, url, onLoadStop) => Column(
              children: [
                Text(url),
                TextButton(
                  onPressed: () =>
                      onLoadStop?.call(WebUri('https://example.com/logged-in')),
                  child: const Text('simulate-navigation'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Connecter votre abonnement'), findsOneWidget);

    await tester.ensureVisible(find.text('Commencer'));
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    // Step 1 (login) : titre porté par la sémantique des pills, URL de login
    // affichée, et CTA masqué tant que l'utilisateur n'a pas navigué (fix #1).
    expect(find.bySemanticsLabel('Connexion'), findsOneWidget);
    expect(find.text('https://example.com/login'), findsOneWidget);
    expect(find.text('Continuer'), findsNothing);

    // Simule la navigation dans la WebView → le CTA doit apparaître.
    await tester.tap(find.text('simulate-navigation'));
    await tester.pumpAndSettle();
    expect(find.text('Continuer'), findsOneWidget);

    await tester.ensureVisible(find.text('Continuer'));
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    // Step 2 (vérification) : copy honnête, plus de promesse d'« article test ».
    expect(find.bySemanticsLabel('Vérification'), findsOneWidget);
    expect(find.text('https://example.com/test'), findsOneWidget);

    await tester.ensureVisible(find.text('Je suis connecté(e)'));
    await tester.tap(find.text('Je suis connecté(e)'));
    await tester.pumpAndSettle();

    expect(connected, isTrue);
    expect(find.text('Abonnement connecté'), findsOneWidget);
    // Session captured at confirm.
    expect(await store.hasSession(source), isTrue);

    semantics.dispose();
  });
}
