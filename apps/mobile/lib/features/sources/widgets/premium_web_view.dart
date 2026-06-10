import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/source_model.dart';
import '../services/premium_session_store.dart';

/// Mots-clés paywall (FR) testés en mode reader pour détecter une session
/// expirée. Volontairement spécifiques pour limiter les faux positifs (un
/// simple « s'abonner » en pied de page ne suffit pas).
const List<String> kPremiumPaywallKeywords = [
  'pour lire la suite',
  'cet article est réservé',
  'article réservé aux abonnés',
  'réservé aux abonnés',
  'contenu réservé aux abonnés',
  'la lecture de cet article est réservée',
];

/// WebView des sources payantes, adossée à `flutter_inappwebview` (store de
/// cookies persistant partagé), calquée sur `youtube_player_widget.dart`.
///
/// Deux modes :
/// - **connexion** (`enableScrollBridge: false`) : l'utilisateur se logue au
///   média ; on capture la session.
/// - **reader** (`enableScrollBridge: true`) : lecture d'un article ; on porte
///   le ScrollBridge (footer auto-hide + progression) et on détecte un paywall
///   (session expirée).
///
/// Réinjection garantie avant chargement : `onWebViewCreated → await restore →
/// loadUrl` (donc pas d'`initialUrlRequest`).
class PremiumWebView extends StatefulWidget {
  const PremiumWebView({
    super.key,
    required this.source,
    required this.url,
    required this.sessionStore,
    this.enableScrollBridge = false,
    this.detectPaywall = false,
    this.onWebViewCreated,
    this.onLoadStop,
    this.onGestureStart,
    this.onGestureDelta,
    this.onGestureEnd,
    this.onProgress,
    this.onScrollY,
    this.onPaywallDetected,
    this.gestureRecognizers,
  });

  final Source source;
  final WebUri url;
  final PremiumSessionStore sessionStore;

  /// Reader = true (footer auto-hide + progression). Connexion = false.
  final bool enableScrollBridge;

  /// Injecte le test paywall sur chaque `onLoadStop` (reader, source connectée).
  final bool detectPaywall;

  final ValueChanged<InAppWebViewController>? onWebViewCreated;
  final ValueChanged<WebUri?>? onLoadStop;
  final VoidCallback? onGestureStart;
  final ValueChanged<double>? onGestureDelta;
  final ValueChanged<double>? onGestureEnd;

  /// Progression de lecture (0..100, brut depuis le JS).
  final ValueChanged<double>? onProgress;
  final ValueChanged<double>? onScrollY;
  final VoidCallback? onPaywallDetected;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  @override
  State<PremiumWebView> createState() => _PremiumWebViewState();
}

class _PremiumWebViewState extends State<PremiumWebView> {
  static const String _chromeUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  @override
  Widget build(BuildContext context) {
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      // Store de cookies partagé & persistant (clé de la persistance de
      // session) — surtout pas d'incognito ni de purge cache.
      incognito: false,
      clearCache: false,
      cacheEnabled: true,
      // SSO médias (Google/Apple) + partage du jar de cookies natif.
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      // UA navigateur Chrome (pas de marqueur "wv") pour éviter les blocages
      // de connexion côté médias.
      userAgent: _chromeUserAgent,
      transparentBackground: false,
    );

    return InAppWebView(
      initialSettings: settings,
      gestureRecognizers: widget.gestureRecognizers,
      onWebViewCreated: _handleCreated,
      onLoadStop: _handleLoadStop,
    );
  }

  Future<void> _handleCreated(InAppWebViewController controller) async {
    widget.onWebViewCreated?.call(controller);

    controller.addJavaScriptHandler(
      handlerName: 'ScrollBridge',
      callback: (args) {
        if (args.isEmpty) return;
        final raw = args.first;
        if (raw is String) _handleScrollBridgeMessage(raw);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'PaywallDetected',
      callback: (args) {
        widget.onPaywallDetected?.call();
      },
    );

    // Réinjection AVANT chargement (ordre garanti), puis chargement manuel.
    try {
      await widget.sessionStore.restoreForSource(widget.source, widget.url);
    } catch (_) {
      // Une session illisible ne doit pas empêcher le chargement.
    }
    if (!mounted) return;
    await controller.loadUrl(urlRequest: URLRequest(url: widget.url));
  }

  Future<void> _handleLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    // Capture opportuniste : toute page chargée avec succès rafraîchit la
    // session persistée.
    try {
      await widget.sessionStore.captureForSource(widget.source, widget.url);
    } catch (_) {
      // best-effort
    }

    if (widget.enableScrollBridge) {
      await controller.evaluateJavascript(source: _kScrollBridgeJs);
    }
    if (widget.detectPaywall) {
      await controller.evaluateJavascript(source: _paywallProbeJs);
    }

    widget.onLoadStop?.call(url);
  }

  void _handleScrollBridgeMessage(String msg) {
    if (msg == 'gesture_start') {
      widget.onGestureStart?.call();
      return;
    }
    if (msg.startsWith('gesture_delta:')) {
      final delta = double.tryParse(msg.substring(14));
      if (delta != null) widget.onGestureDelta?.call(delta);
      return;
    }
    if (msg.startsWith('gesture_end:')) {
      final vel = double.tryParse(msg.substring(12)) ?? 0;
      widget.onGestureEnd?.call(vel);
      return;
    }
    if (msg == 'gesture_cancel') {
      widget.onGestureEnd?.call(0);
      return;
    }
    if (msg.startsWith('scroll_y:')) {
      final y = double.tryParse(msg.substring(9));
      if (y != null) widget.onScrollY?.call(y);
      return;
    }
    if (msg.startsWith('progress:')) {
      final pct = double.tryParse(msg.substring(9));
      if (pct != null) widget.onProgress?.call(pct);
    }
  }

  /// JS du test paywall (reader, source connectée). Liste de mots-clés FR
  /// dupliquée volontairement côté client.
  String get _paywallProbeJs {
    final keywordsJs = kPremiumPaywallKeywords
        .map((k) => "'${k.replaceAll("'", "\\'")}'")
        .join(',');
    return '''
      (function() {
        try {
          var text = (document.body && document.body.innerText || '').toLowerCase();
          var kws = [$keywordsJs];
          for (var i = 0; i < kws.length; i++) {
            if (text.indexOf(kws[i]) !== -1) {
              window.flutter_inappwebview.callHandler('PaywallDetected');
              return;
            }
          }
        } catch (e) {}
      })();
    ''';
  }
}

/// ScrollBridge porté depuis `content_detail_screen.dart` : logique de geste
/// identique, seul l'émetteur change (`ScrollBridge.postMessage(...)` →
/// `window.flutter_inappwebview.callHandler('ScrollBridge', ...)`). Les messages
/// émis sont strictement les mêmes, donc le parsing Dart est inchangé.
const String _kScrollBridgeJs = '''
  (function() {
    if (window.__facteurScrollBridge) return;
    window.__facteurScrollBridge = true;
    function emit(msg) {
      window.flutter_inappwebview.callHandler('ScrollBridge', msg);
    }
    var lastTouchY = 0;
    var lastTouchT = 0;
    var velocity = 0;
    var touchActive = false;
    var pendingDy = 0;
    var rafScheduled = false;
    var raf = window.requestAnimationFrame
      ? function(cb) { window.requestAnimationFrame(cb); }
      : function(cb) { setTimeout(cb, 16); };
    function flushGesture() {
      rafScheduled = false;
      var dy = pendingDy;
      pendingDy = 0;
      if (Math.abs(dy) < 1) return;
      if (dy >  150) dy =  150;
      if (dy < -150) dy = -150;
      emit('gesture_delta:' + (-dy));
    }
    document.addEventListener('touchstart', function(e) {
      if (e.touches.length > 1) { touchActive = false; return; }
      lastTouchY = e.touches[0].clientY;
      lastTouchT = (window.performance && performance.now) ? performance.now() : Date.now();
      velocity = 0;
      pendingDy = 0;
      touchActive = true;
      emit('gesture_start');
    }, { passive: true, capture: true });
    document.addEventListener('touchmove', function(e) {
      if (!touchActive || e.touches.length > 1) return;
      var y = e.touches[0].clientY;
      var t = (window.performance && performance.now) ? performance.now() : Date.now();
      var dy = y - lastTouchY;
      var dt = t - lastTouchT;
      if (dt > 0) {
        velocity = 0.7 * velocity + 0.3 * (dy / dt);
      }
      lastTouchY = y;
      lastTouchT = t;
      pendingDy += dy;
      if (!rafScheduled) {
        rafScheduled = true;
        raf(flushGesture);
      }
    }, { passive: true, capture: true });
    document.addEventListener('touchend', function(e) {
      if (!touchActive) return;
      touchActive = false;
      if (rafScheduled) flushGesture();
      emit('gesture_end:' + (-velocity * 1000));
    }, { passive: true, capture: true });
    document.addEventListener('touchcancel', function(e) {
      if (!touchActive) return;
      touchActive = false;
      if (rafScheduled) flushGesture();
      emit('gesture_cancel');
    }, { passive: true, capture: true });
    var lastProgress = 0;
    var progressTimer = null;
    var scrollYTimer = null;
    function flushProgress() {
      progressTimer = null;
      var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
      if (maxScroll <= 0) return;
      var pct = parseFloat((window.scrollY / maxScroll * 100).toFixed(1));
      pct = Math.min(100, Math.max(0, pct));
      if (pct !== lastProgress) {
        lastProgress = pct;
        emit('progress:' + pct);
      }
    }
    function flushScrollY() {
      scrollYTimer = null;
      emit('scroll_y:' + window.scrollY);
    }
    window.addEventListener('scroll', function() {
      if (!scrollYTimer) scrollYTimer = setTimeout(flushScrollY, 100);
      if (!progressTimer) progressTimer = setTimeout(flushProgress, 300);
    }, { passive: true });
  })();
''';
