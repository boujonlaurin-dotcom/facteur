import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/settings/screens/subscriptions_screen.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/services/premium_session_store.dart';

class _FakeUserSourcesNotifier extends UserSourcesNotifier {
  _FakeUserSourcesNotifier(this._sources);
  final List<Source> _sources;

  @override
  Future<List<Source>> build() async => _sources;
}

class _FakeCookieJar implements PremiumCookieJar {
  @override
  Future<List<Cookie>> getCookies(WebUri url) async => const [];
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

Widget _wrap(List<Source> sources) {
  final store = PremiumSessionStore(
    jar: _FakeCookieJar(),
    secureStore: _InMemorySecureStore(),
  );
  return ProviderScope(
    overrides: [
      userSourcesProvider.overrideWith(() => _FakeUserSourcesNotifier(sources)),
      premiumSessionStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: const SubscriptionsScreen(),
    ),
  );
}

Source _source({
  required String id,
  required String name,
  bool hasSubscription = false,
  bool isTrusted = false,
  bool hasPaywall = true,
  PremiumConnection? premiumConnection = const PremiumConnection(
    loginUrl: 'https://example.com/login',
    testUrl: 'https://example.com/test',
  ),
}) =>
    Source(
      id: id,
      name: name,
      type: SourceType.article,
      url: 'https://$id.example',
      isTrusted: isTrusted,
      hasSubscription: hasSubscription,
      hasPaywall: hasPaywall,
      premiumConnection: premiumConnection,
    );

void main() {
  testWidgets('lists only subscribed sources', (tester) async {
    await tester.pumpWidget(_wrap([
      _source(id: 'lemonde', name: 'Le Monde', hasSubscription: true),
      _source(id: 'freeblog', name: 'Free Blog'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Le Monde'), findsOneWidget);
    expect(find.text('Free Blog'), findsNothing);
    expect(find.text('Reconnecter'), findsOneWidget);
    expect(find.text('Dissocier'), findsOneWidget);
    expect(find.text('Ajouter un abonnement'), findsOneWidget);
  });

  testWidgets('empty state opens fallback when no connectable source',
      (tester) async {
    await tester.pumpWidget(_wrap([
      // Source libre NON suivie → ni payante éligible, ni login-connectable.
      _source(
        id: 'freeblog',
        name: 'Free Blog',
        isTrusted: false,
        hasPaywall: false,
        premiumConnection: null,
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Aucun abonnement connecté'), findsOneWidget);
    expect(find.text('Ajouter un abonnement'), findsOneWidget);

    await tester.tap(find.text('Ajouter un abonnement'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun média payant suivi'), findsOneWidget);
    expect(find.text('Choisir mes sources'), findsOneWidget);
  });

  testWidgets('add sheet lists paid sources + login-connectable followed sites',
      (tester) async {
    await tester.pumpWidget(_wrap([
      _source(id: 'lemonde', name: 'Le Monde', isTrusted: true),
      _source(id: 'mediapart', name: 'Mediapart', isTrusted: true),
      _source(id: 'unfollowed', name: 'Non suivi'),
      // Source libre suivie : connectable via login générique (décision PO).
      _source(
        id: 'freeblog',
        name: 'Gratuit suivi',
        isTrusted: true,
        hasPaywall: false,
        premiumConnection: null,
      ),
      _source(
        id: 'connected',
        name: 'Déjà connecté',
        isTrusted: true,
        hasSubscription: true,
      ),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajouter un abonnement').first);
    await tester.pumpAndSettle();

    expect(find.text('Le Monde'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('Mediapart'),
      ),
      findsOneWidget,
    );
    expect(find.text('Non suivi'), findsNothing);
    // La source libre suivie apparaît sous la section « autre site à login ».
    expect(find.text('Un autre site demande une connexion ?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('Gratuit suivi'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byType(TextField),
      'Mediapart',
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('Mediapart'),
      ),
      findsOneWidget,
    );
    expect(find.text('Le Monde'), findsNothing);
  });

  testWidgets('connect action opens the existing premium connection flow',
      (tester) async {
    await tester.pumpWidget(_wrap([
      _source(id: 'lemonde', name: 'Le Monde', isTrusted: true),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajouter un abonnement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Connecter votre abonnement'), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
  });
}
