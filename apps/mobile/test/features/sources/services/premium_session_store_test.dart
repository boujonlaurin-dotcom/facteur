import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/services/premium_session_store.dart';

class _FakeCookieJar implements PremiumCookieJar {
  final Map<String, List<Cookie>> store = {};
  final List<String> deletedHosts = [];

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
  }) async {
    final list = store.putIfAbsent(url.host, () => <Cookie>[]);
    list.removeWhere((c) => c.name == name);
    list.add(Cookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expiresDate: expiresDate,
      isSecure: isSecure,
      isHttpOnly: isHttpOnly,
      sameSite: sameSite,
    ));
  }

  @override
  Future<void> deleteCookies(WebUri url) async {
    deletedHosts.add(url.host);
    store.remove(url.host);
  }
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

Source _source({String url = 'https://www.lemonde.fr'}) => Source(
      id: 'src-1',
      name: 'Le Monde',
      type: SourceType.article,
      url: url,
    );

void main() {
  group('premiumDomainKey', () {
    test('normalizes subdomains to eTLD+1', () {
      expect(premiumDomainKey('https://www.lemonde.fr/article'), 'lemonde.fr');
      expect(premiumDomainKey('https://m.lemonde.fr/'), 'lemonde.fr');
      expect(premiumDomainKey('https://abonnes.lemonde.fr'), 'lemonde.fr');
      expect(premiumDomainKey('lemonde.fr'), 'lemonde.fr');
    });

    test('handles multi-part tld and invalids', () {
      expect(premiumDomainKey('https://www.theguardian.co.uk/x'),
          'theguardian.co.uk');
      expect(premiumDomainKey(null), '');
      expect(premiumDomainKey('   '), '');
    });
  });

  group('PremiumSessionStore', () {
    late _FakeCookieJar jar;
    late _InMemorySecureStore secure;
    late PremiumSessionStore store;

    setUp(() {
      jar = _FakeCookieJar();
      secure = _InMemorySecureStore();
      store = PremiumSessionStore(jar: jar, secureStore: secure);
    });

    test('capture → restore → clear round-trip', () async {
      final source = _source();
      final url = WebUri('https://www.lemonde.fr/article');
      jar.store['www.lemonde.fr'] = [
        Cookie(name: 'sid', value: 'abc', domain: '.lemonde.fr', path: '/'),
        Cookie(name: 'auth', value: 'xyz', isSecure: true, isHttpOnly: true),
      ];

      // capture
      await store.captureForSource(source, url);
      expect(await store.hasSession(source), isTrue);
      expect(secure.map.keys.single,
          'premium_session::src-1::lemonde.fr');

      // wipe native cookies (simulate kill/relaunch losing session cookies)
      jar.store.clear();
      expect(await jar.getCookies(url), isEmpty);

      // restore re-injects
      final restored = await store.restoreForSource(source, url);
      expect(restored, isTrue);
      final cookies = await jar.getCookies(url);
      expect(cookies.map((c) => c.name).toSet(), {'sid', 'auth'});
      expect(cookies.firstWhere((c) => c.name == 'sid').value, 'abc');

      // clear
      await store.clearForSource(source);
      expect(await store.hasSession(source), isFalse);
      expect(jar.deletedHosts, contains('www.lemonde.fr'));
      expect(await jar.getCookies(url), isEmpty);
    });

    test('capture is a no-op when there are no cookies', () async {
      final source = _source();
      final url = WebUri('https://www.lemonde.fr/article');
      await store.captureForSource(source, url);
      expect(secure.map, isEmpty);
      expect(await store.hasSession(source), isFalse);
    });

    test('key matches across subdomains (capture www, query source home)',
        () async {
      final source = _source(url: 'https://lemonde.fr');
      jar.store['www.lemonde.fr'] = [
        Cookie(name: 'sid', value: 'abc'),
      ];
      await store.captureForSource(
          source, WebUri('https://www.lemonde.fr/x'));

      // hasSession uses source.url (lemonde.fr) → same eTLD+1 key
      expect(await store.hasSession(source), isTrue);
      // restore on a different subdomain hits the same key
      final restored = await store.restoreForSource(
          source, WebUri('https://m.lemonde.fr/y'));
      expect(restored, isTrue);
    });

    test('restore returns false when no session stored', () async {
      final source = _source();
      final restored = await store.restoreForSource(
          source, WebUri('https://www.lemonde.fr/x'));
      expect(restored, isFalse);
    });
  });
}
