import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Source _sub(String id, String name) => Source(
      id: id,
      name: name,
      type: SourceType.article,
      url: 'https://$id.example',
      isTrusted: true,
      hasSubscription: true,
      hasPaywall: true,
    );

/// Clé de session telle que la calcule [PremiumSessionStore] (miroir privé).
String _sessionKey(Source s) =>
    'premium_session::${s.id}::${premiumDomainKey(s.url)}';

void main() {
  test('lists subscribed sources whose local session is missing', () async {
    final lemonde = _sub('lemonde', 'Le Monde');
    final mediapart = _sub('mediapart', 'Mediapart');
    final secure = _InMemorySecureStore();
    // Mediapart a une session locale, Le Monde non.
    secure.map[_sessionKey(mediapart)] = '[{"name":"sid","value":"x"}]';

    final container = ProviderContainer(
      overrides: [
        userSourcesProvider
            .overrideWith(() => _FakeUserSourcesNotifier([lemonde, mediapart])),
        premiumSessionStoreProvider.overrideWithValue(
          PremiumSessionStore(jar: _FakeCookieJar(), secureStore: secure),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Laisse `userSourcesProvider` résoudre avant de lire le dérivé.
    await container.read(userSourcesProvider.future);

    final needing =
        await container.read(subscriptionsNeedingReconnectProvider.future);

    expect(needing.map((s) => s.id), ['lemonde']);
  });

  test('is empty once every subscription has a local session', () async {
    final lemonde = _sub('lemonde', 'Le Monde');
    final secure = _InMemorySecureStore();
    secure.map[_sessionKey(lemonde)] = '[{"name":"sid","value":"x"}]';

    final container = ProviderContainer(
      overrides: [
        userSourcesProvider
            .overrideWith(() => _FakeUserSourcesNotifier([lemonde])),
        premiumSessionStoreProvider.overrideWithValue(
          PremiumSessionStore(jar: _FakeCookieJar(), secureStore: secure),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(userSourcesProvider.future);

    final needing =
        await container.read(subscriptionsNeedingReconnectProvider.future);

    expect(needing, isEmpty);
  });

  test('loginConnectableSourcesProvider surfaces free followed http sources',
      () async {
    final paid = _sub('lemonde', 'Le Monde')
        .copyWith(hasSubscription: false); // payant éligible
    final freeFollowed = Source(
      id: 'blog',
      name: 'Blog Suivi',
      type: SourceType.article,
      url: 'https://blog.example',
      isTrusted: true,
    );
    final freeUnfollowed = Source(
      id: 'other',
      name: 'Autre',
      type: SourceType.article,
      url: 'https://other.example',
    );

    final container = ProviderContainer(
      overrides: [
        userSourcesProvider.overrideWith(
          () => _FakeUserSourcesNotifier([paid, freeFollowed, freeUnfollowed]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(userSourcesProvider.future);

    final connectable = container.read(loginConnectableSourcesProvider);

    // Le payant éligible est exclu (couvert par eligibleSubscriptionSources) ;
    // la source libre non suivie aussi. Seul le libre suivi reste.
    expect(connectable.map((s) => s.id), ['blog']);
  });
}
