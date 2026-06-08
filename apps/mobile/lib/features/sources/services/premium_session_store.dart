import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/source_model.dart';

/// Persistance de la session d'une source payante (cookies du média).
///
/// `webview_flutter` n'expose pas les cookies → la session du média se perdait
/// à chaque recyclage de WebView / redémarrage de l'app, forçant l'utilisateur
/// à se reconnecter à chaque article. On capture les cookies via le
/// `CookieManager` partagé d'`flutter_inappwebview` (store persistant) et on les
/// recopie en `flutter_secure_storage` pour les **réinjecter** à l'ouverture de
/// chaque WebView (filet de sécurité contre la disparition des cookies de
/// session au redémarrage natif).
///
/// Les deux dépendances (cookies natifs, stockage sécurisé) sont abstraites
/// ([PremiumCookieJar], [SecureKeyValueStore]) pour rester unit-testable sans
/// plateforme.

/// Abstraction fine autour de `CookieManager.instance()` (testabilité).
abstract class PremiumCookieJar {
  Future<List<Cookie>> getCookies(WebUri url);

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
  });

  Future<void> deleteCookies(WebUri url);
}

/// Implémentation réelle adossée au `CookieManager` partagé d'inappwebview.
class InAppPremiumCookieJar implements PremiumCookieJar {
  InAppPremiumCookieJar([CookieManager? manager])
      : _manager = manager ?? CookieManager.instance();

  final CookieManager _manager;

  @override
  Future<List<Cookie>> getCookies(WebUri url) => _manager.getCookies(url: url);

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
    await _manager.setCookie(
      url: url,
      name: name,
      value: value,
      domain: domain,
      path: path,
      expiresDate: expiresDate,
      isSecure: isSecure,
      isHttpOnly: isHttpOnly,
      sameSite: sameSite,
    );
  }

  @override
  Future<void> deleteCookies(WebUri url) => _manager.deleteCookies(url: url);
}

/// Abstraction minimale autour de `FlutterSecureStorage` (testabilité).
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// eTLD+1 normalisé d'une URL — miroir Dart de `domain_key` (backend).
/// `https://www.lemonde.fr/x` → `lemonde.fr`. Approximation FR-first
/// (deux derniers labels) avec garde pour quelques suffixes composés.
String premiumDomainKey(String? url) {
  if (url == null) return '';
  var raw = url.trim();
  if (raw.isEmpty) return '';
  if (!raw.contains('//')) raw = '//$raw';
  final host = (Uri.tryParse(raw)?.host ?? '').toLowerCase();
  if (host.isEmpty) return '';
  final labels = host.split('.');
  if (labels.length <= 2) return host;
  const multiPartTlds = {
    'co.uk',
    'org.uk',
    'gov.uk',
    'ac.uk',
    'com.au',
    'co.jp',
    'co.nz',
  };
  final lastTwo = labels.sublist(labels.length - 2).join('.');
  if (multiPartTlds.contains(lastTwo) && labels.length >= 3) {
    return labels.sublist(labels.length - 3).join('.');
  }
  return lastTwo;
}

class PremiumSessionStore {
  PremiumSessionStore({
    required PremiumCookieJar jar,
    required SecureKeyValueStore secureStore,
  })  : _jar = jar,
        _secure = secureStore;

  final PremiumCookieJar _jar;
  final SecureKeyValueStore _secure;

  static const String _keyPrefix = 'premium_session';

  String _domainFor(Source source, [WebUri? url]) {
    if (url != null) {
      final fromUrl = premiumDomainKey(url.toString());
      if (fromUrl.isNotEmpty) return fromUrl;
    }
    return premiumDomainKey(source.url);
  }

  String _keyFor(Source source, [WebUri? url]) =>
      '$_keyPrefix::${source.id}::${_domainFor(source, url)}';

  /// Capture les cookies courants du média pour [url] et les persiste.
  /// No-op si aucun cookie (on n'écrase pas une session valide par du vide).
  Future<void> captureForSource(Source source, WebUri url) async {
    final cookies = await _jar.getCookies(url);
    if (cookies.isEmpty) return;
    final encoded = jsonEncode(cookies.map(_cookieToJson).toList());
    await _secure.write(_keyFor(source, url), encoded);
  }

  /// Réinjecte les cookies persistés dans le `CookieManager` avant chargement.
  /// Retourne `true` si une session existait et a été réinjectée.
  Future<bool> restoreForSource(Source source, WebUri url) async {
    final raw = await _secure.read(_keyFor(source, url));
    if (raw == null || raw.isEmpty) return false;
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return false;
    }
    var injected = false;
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final name = map['name'] as String?;
      if (name == null || name.isEmpty) continue;
      await _jar.setCookie(
        url,
        name: name,
        value: (map['value'] as String?) ?? '',
        domain: map['domain'] as String?,
        path: (map['path'] as String?) ?? '/',
        expiresDate: map['expiresDate'] as int?,
        isSecure: map['isSecure'] as bool?,
        isHttpOnly: map['isHttpOnly'] as bool?,
        sameSite: _sameSiteFromString(map['sameSite'] as String?),
      );
      injected = true;
    }
    return injected;
  }

  /// Une session persistée existe-t-elle pour cette source ?
  Future<bool> hasSession(Source source) async {
    final raw = await _secure.read(_keyFor(source));
    return raw != null && raw.isNotEmpty;
  }

  /// Supprime la session persistée + purge les cookies natifs du média.
  Future<void> clearForSource(Source source) async {
    await _secure.delete(_keyFor(source));
    final url = source.url?.trim();
    if (url != null && url.isNotEmpty) {
      final normalized = url.contains('//') ? url : 'https://$url';
      final parsed = Uri.tryParse(normalized);
      if (parsed != null && parsed.host.isNotEmpty) {
        await _jar.deleteCookies(WebUri.uri(parsed));
      }
    }
  }

  Map<String, dynamic> _cookieToJson(Cookie cookie) => {
        'name': cookie.name,
        'value': cookie.value?.toString() ?? '',
        if (cookie.expiresDate != null) 'expiresDate': cookie.expiresDate,
        if (cookie.domain != null) 'domain': cookie.domain,
        if (cookie.path != null) 'path': cookie.path,
        if (cookie.isSecure != null) 'isSecure': cookie.isSecure,
        if (cookie.isHttpOnly != null) 'isHttpOnly': cookie.isHttpOnly,
        if (cookie.sameSite != null)
          'sameSite': _sameSiteToString(cookie.sameSite),
      };

  static String? _sameSiteToString(HTTPCookieSameSitePolicy? policy) {
    if (policy == HTTPCookieSameSitePolicy.LAX) return 'Lax';
    if (policy == HTTPCookieSameSitePolicy.STRICT) return 'Strict';
    if (policy == HTTPCookieSameSitePolicy.NONE) return 'None';
    return null;
  }

  static HTTPCookieSameSitePolicy? _sameSiteFromString(String? value) {
    switch (value) {
      case 'Lax':
        return HTTPCookieSameSitePolicy.LAX;
      case 'Strict':
        return HTTPCookieSameSitePolicy.STRICT;
      case 'None':
        return HTTPCookieSameSitePolicy.NONE;
      default:
        return null;
    }
  }
}
