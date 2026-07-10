import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Source déclenchante d'une bannière « un truc s'est mal passé ».
///
/// Whitelist stricte (anti-faux-positif) : seuls ces cas remontent à
/// l'utilisateur. Tout le reste continue à filer chez Sentry en silence.
enum UserErrorSource { flutterError, http5xx, timeout }

extension UserErrorSourceTag on UserErrorSource {
  /// Valeur de tag Sentry / PostHog (stable, snake_case).
  String get tag => switch (this) {
        UserErrorSource.flutterError => 'flutter_error',
        UserErrorSource.http5xx => 'http_5xx',
        UserErrorSource.timeout => 'timeout',
      };
}

/// Évènement « bannière à afficher » consommé par le wiring root (app.dart).
@immutable
class UserFacingErrorEvent {
  const UserFacingErrorEvent({
    required this.source,
    required this.signature,
    this.route,
    this.detail,
    this.shortAck = false,
  });

  final UserErrorSource source;

  /// Hash `(source, statusCode|exceptionType, route)` — sert au cooldown
  /// par-signature ET de contexte Sentry.
  final String signature;

  /// Route logique où l'erreur s'est produite (best-effort).
  final String? route;

  /// Contexte court, déjà rédigé/redacted, joint au rapport Sentry.
  final String? detail;

  /// `true` → variante ultra-discrète « on est au courant, merci » (l'user a
  /// déjà signalé récemment ; pas de CTA, auto-dismiss court).
  final bool shortAck;
}

/// Notifier global (singleton, agnostique de BuildContext — même forme que
/// `ApiGoneNotifier`) qui centralise la logique de cooldown avant d'exposer
/// un [UserFacingErrorEvent] à l'UI top-level.
///
/// Toute la plomberie de fréquence vit ici pour rester testable sans widget :
/// un clock et une instance SharedPreferences sont injectables.
class UserFacingErrorNotifier extends ChangeNotifier {
  UserFacingErrorNotifier._();
  static final UserFacingErrorNotifier instance = UserFacingErrorNotifier._();

  /// Constructeur de test : clock + prefs injectés, kill-switch forçable.
  @visibleForTesting
  UserFacingErrorNotifier.forTesting({
    required Future<SharedPreferences> Function() prefs,
    required DateTime Function() now,
    bool enabled = true,
  })  : _prefsLoader = prefs,
        _now = now,
        _enabled = enabled;

  // --- Cooldowns (LOCKED, cf. plan) ------------------------------------
  static const Duration _globalCooldown = Duration(minutes: 5);
  static const Duration _signatureCooldown = Duration(minutes: 30);
  static const Duration _reportShortAckWindow = Duration(hours: 24);

  static const String _kLastShownAt = 'user_error_banner_last_shown_at';
  static const String _kReportLastSentAt = 'user_error_report_last_sent_at';
  static const String _kSigPrefix = 'user_error_sig_';

  Future<SharedPreferences> Function() _prefsLoader =
      SharedPreferences.getInstance;
  DateTime Function() _now = DateTime.now;

  /// Kill-switch : off par défaut (dark launch). Réglé au boot via
  /// [configureEnabled] (aligné sur `UserErrorBannerConstants.enabled`),
  /// forçable en test.
  bool _enabled = false;

  /// Garde synchrone anti-tempête : évite que N erreurs par-frame lancent N
  /// I/O prefs concurrentes avant que le premier cooldown ne soit persisté.
  bool _reportInFlight = false;

  UserFacingErrorEvent? _pendingEvent;
  UserFacingErrorEvent? get pendingEvent => _pendingEvent;

  /// Branche le kill-switch de build (appelé une fois au boot).
  void configureEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Point d'entrée unique des 3 sources whitelistées. Applique les cooldowns
  /// puis publie un évènement si la bannière doit s'afficher. No-op silencieux
  /// sinon (kill-switch off, cooldown actif, etc.).
  Future<void> report({
    required UserErrorSource source,
    required String signature,
    String? route,
    String? detail,
  }) async {
    if (!_enabled) return;
    if (_reportInFlight) return;
    _reportInFlight = true;
    try {
      final SharedPreferences prefs;
      try {
        prefs = await _prefsLoader();
      } catch (_) {
        // Prefs indisponibles → on n'affiche rien plutôt que de risquer un spam.
        return;
      }
      final now = _now();

      // 1. Cooldown par-signature (30 min) — muet si même souci récent.
      final sigKey = '$_kSigPrefix${_hash(signature)}';
      if (_within(prefs.getInt(sigKey), now, _signatureCooldown)) return;

      // 2. Cooldown global (5 min) — au plus une bannière par fenêtre.
      if (_within(prefs.getInt(_kLastShownAt), now, _globalCooldown)) return;

      // 3. Variante « déjà signalé récemment » (24h) → ack ultra-discret.
      final shortAck =
          _within(prefs.getInt(_kReportLastSentAt), now, _reportShortAckWindow);

      final ms = now.millisecondsSinceEpoch;
      await prefs.setInt(sigKey, ms);
      await prefs.setInt(_kLastShownAt, ms);

      _pendingEvent = UserFacingErrorEvent(
        source: source,
        signature: signature,
        route: route,
        detail: detail,
        shortAck: shortAck,
      );
      notifyListeners();
    } finally {
      _reportInFlight = false;
    }
  }

  /// À appeler après un envoi « Nous dire » réussi : arme la fenêtre 24h qui
  /// bascule les prochaines bannières en variante courte.
  Future<void> markReported() async {
    try {
      final prefs = await _prefsLoader();
      await prefs.setInt(_kReportLastSentAt, _now().millisecondsSinceEpoch);
    } catch (_) {
      // best-effort
    }
  }

  /// Consomme l'évènement après affichage (évite le re-trigger sur rebuild).
  void clear() {
    if (_pendingEvent == null) return;
    _pendingEvent = null;
    notifyListeners();
  }

  bool _within(int? lastMs, DateTime now, Duration window) {
    if (lastMs == null) return false;
    final elapsed = now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
    return !elapsed.isNegative && elapsed < window;
  }

  /// Hash stable et court d'une signature (clé SharedPrefs bornée).
  String _hash(String signature) {
    var h = 0;
    for (final code in signature.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }
}
