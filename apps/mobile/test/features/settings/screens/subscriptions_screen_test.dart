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
}) =>
    Source(
      id: id,
      name: name,
      type: SourceType.article,
      url: 'https://$id.example',
      hasSubscription: hasSubscription,
      hasPaywall: true,
      premiumConnection: const PremiumConnection(
        loginUrl: 'https://example.com/login',
        testUrl: 'https://example.com/test',
      ),
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
  });

  testWidgets('shows empty state when no subscriptions', (tester) async {
    await tester.pumpWidget(_wrap([
      _source(id: 'freeblog', name: 'Free Blog'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Aucun abonnement connecté'), findsOneWidget);
  });
}
