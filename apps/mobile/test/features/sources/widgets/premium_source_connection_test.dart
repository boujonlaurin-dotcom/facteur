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
            // Le builder de test bypass PremiumWebView : on expose des boutons
            // qui déclenchent onLoadStop / onPaywallDetected / onLoadError pour
            // simuler les événements de la WebView.
            webViewBuilder: (_, url, onLoadStop,
                    {onPaywallDetected, onLoadError}) =>
                Column(
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

    expect(find.text('Connecter Premium Source'), findsOneWidget);

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

  testWidgets(
      'step 2 shows a non-blocking paywall warning on onPaywallDetected '
      'without disabling the confirm CTA', (tester) async {
    final jar = _FakeCookieJar();
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
            onConnected: () async {},
            webViewBuilder: (_, url, onLoadStop,
                    {onPaywallDetected, onLoadError}) =>
                Column(
              children: [
                TextButton(
                  onPressed: () =>
                      onLoadStop?.call(WebUri('https://example.com/x')),
                  child: const Text('simulate-navigation'),
                ),
                TextButton(
                  onPressed: () => onPaywallDetected?.call(),
                  child: const Text('simulate-paywall'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // intro → step 1 → navigation → step 2
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('simulate-navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    // Consigne de l'étape 2 rendue, pas encore de warning.
    expect(
      find.textContaining('Ouvre un article réservé aux abonnés'),
      findsOneWidget,
    );
    expect(find.textContaining('semble encore réservé'), findsNothing);

    // La sonde remonte un paywall → bannière visible, CTA toujours actif.
    await tester.tap(find.text('simulate-paywall'));
    await tester.pumpAndSettle();
    expect(find.textContaining('semble encore réservé'), findsOneWidget);

    await tester.ensureVisible(find.text('Je suis connecté(e)'));
    await tester.tap(find.text('Je suis connecté(e)'));
    await tester.pumpAndSettle();
    // Le CTA n'était pas bloqué : la connexion aboutit malgré le warning.
    expect(find.text('Abonnement connecté'), findsOneWidget);
  });

  testWidgets(
      'a failed page load surfaces the guidance overlay, and Retry clears it',
      (tester) async {
    final store = PremiumSessionStore(
      jar: _FakeCookieJar(),
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
            onConnected: () async {},
            webViewBuilder: (_, url, onLoadStop,
                    {onPaywallDetected, onLoadError}) =>
                Column(
              children: [
                TextButton(
                  onPressed: () => onLoadError?.call(404),
                  child: const Text('simulate-error'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    // Pas d'overlay tant que la page charge.
    expect(find.text('Réessayer'), findsNothing);

    await tester.tap(find.text('simulate-error'));
    await tester.pumpAndSettle();
    expect(find.text('La page ne s’est pas chargée'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    // « Réessayer » efface l'overlay (et reconstruit la WebView).
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('La page ne s’est pas chargée'), findsNothing);
  });

  group('siteRootFor + generic connection origin normalization', () {
    test('reduces a feed URL to the site origin', () {
      expect(
        siteRootFor('https://www.cerveauetpsycho.fr/rss.xml'),
        'https://www.cerveauetpsycho.fr/',
      );
      expect(siteRootFor('https://example.com/feed/'), 'https://example.com/');
    });

    test('is idempotent on an already-root URL and adds the trailing slash', () {
      expect(siteRootFor('https://example.com/'), 'https://example.com/');
      expect(siteRootFor('https://example.com'), 'https://example.com/');
    });

    test('preserves scheme and port', () {
      expect(
        siteRootFor('http://localhost:8080/x/y'),
        'http://localhost:8080/',
      );
    });

    test('returns null for non-http(s) / hostless / invalid URLs', () {
      expect(siteRootFor('not a url'), isNull);
      expect(siteRootFor(''), isNull);
      expect(siteRootFor('mailto:foo@bar.com'), isNull);
      // Même contrat http(s)-only que le back-end `origin_url`.
      expect(siteRootFor('ftp://weird-host/x'), isNull);
    });

    test('forceGenericConnection normalizes a feed URL to the origin', () {
      final source = Source(
        id: 's',
        name: 'Cerveau & Psycho',
        type: SourceType.article,
        url: 'https://www.cerveauetpsycho.fr/rss.xml',
      );
      final conn = forceGenericConnection(source);
      expect(conn, isNotNull);
      expect(conn!.loginUrl, 'https://www.cerveauetpsycho.fr/');
      expect(conn.testUrl, 'https://www.cerveauetpsycho.fr/');
      expect(conn.isGeneric, isTrue);
    });
  });
}
