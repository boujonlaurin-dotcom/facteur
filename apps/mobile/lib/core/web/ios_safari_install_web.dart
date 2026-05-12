import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Lit `navigator.standalone` (propriété iOS-only non typée dans `package:web`).
@JS('navigator.standalone')
external JSAny? _navigatorStandalone;

/// Vrai si l'utilisateur est sur iOS Safari (iPhone/iPad/iPod) **et** que la
/// page n'est pas déjà en mode standalone (= déjà ajoutée à l'écran d'accueil
/// et lancée comme PWA).
///
/// Exclut Chrome iOS (`CriOS`), Firefox iOS (`FxiOS`) et Edge iOS (`EdgiOS`) :
/// ces navigateurs ne supportent pas "Ajouter à l'écran d'accueil" de la
/// même manière, et la modal ne leur serait pas utile.
bool? _cached;
bool checkIosSafariNonStandalone() => _cached ??= _compute();

bool _compute() {
  final ua = web.window.navigator.userAgent;
  final isIosDevice =
      ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod');
  if (!isIosDevice) return false;

  final isOtherBrowser =
      ua.contains('CriOS') || ua.contains('FxiOS') || ua.contains('EdgiOS');
  if (isOtherBrowser) return false;

  if (!ua.contains('Safari')) return false;

  final standalone = _navigatorStandalone;
  final isStandalone = standalone != null && standalone.dartify() == true;
  return !isStandalone;
}
