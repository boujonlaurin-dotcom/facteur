import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:home_widget/home_widget.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

import 'app.dart';
import 'config/constants.dart';
import 'core/auth/supabase_storage.dart';
import 'core/services/posthog_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/ui/notification_service.dart';
import 'features/flux_continu/services/tournee_progress_service.dart';

import 'package:timeago/timeago.dart' as timeago;
import 'package:timeago/src/messages/fr_messages.dart'
    as fr_messages; // ignore: implementation_imports
import 'core/utils/fr_compact_messages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sentry init — wrappe le reste du bootstrap pour capturer toute exception
  // pendant l'init. Si DSN absent (dev local sans clé), l'init est skip.
  // Cf. docs/bugs/bug-android-disconnect-race.md (P5 — instrumentation).
  if (SentryConstants.isEnabled) {
    await SentryFlutter.init((options) {
      options.dsn = SentryConstants.dsn;
      options.environment = SentryConstants.environment;
      if (SentryConstants.release.isNotEmpty) {
        options.release = SentryConstants.release;
      }
      // Sample 100% des erreurs, pas de perf tracing pour le moment.
      options.tracesSampleRate = 0.0;
      // Ne pas envoyer les PII par défaut.
      options.sendDefaultPii = false;
    }, appRunner: _bootstrap);
  } else {
    await _bootstrap();
  }
}

Future<void> _bootstrap() async {
  final bootSw = Stopwatch()..start();

  timeago.setLocaleMessages('fr', fr_messages.FrMessages());
  timeago.setLocaleMessages('fr_short', FrCompactMessages());

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // Orientation : doit être résolu avant 1ère frame, sinon flash rotation
  // sur devices qui lancent en landscape.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Hive.initFlutter();

  final boxesSw = Stopwatch()..start();
  final initResults = await Future.wait<Object>([
    _openBoxSafe<dynamic>('settings'),
    _openBoxSafe<dynamic>('auth_prefs'),
    _openBoxSafe<String>('supabase_auth_persistence'),
    _openBoxSafe<String>('feed_cache'),
    SharedPreferences.getInstance(),
  ]);
  final boxes = initResults.take(4).cast<Box<dynamic>>().toList();
  final sharedPreferences = initResults[4] as SharedPreferences;
  final authBox = boxes[1];
  final supabaseBox = boxes[2];
  debugPrint(
    '[PERF] boot.hive_boxes_ms=${boxesSw.elapsedMilliseconds} (4 boxes + prefs parallel)',
  );

  debugPrint('Main: Hive auth_prefs keys: ${authBox.keys.toList()}');
  debugPrint(
    'Main: Hive auth_prefs remember_me: ${authBox.get('remember_me')}',
  );
  debugPrint(
    'Main: Hive supabase_auth_persistence keys: ${supabaseBox.keys.toList()}',
  );
  if (supabaseBox.containsKey('supabase_session')) {
    final session = supabaseBox.get('supabase_session');
    debugPrint(
      'Main: Hive supabase_session found (length: ${session?.length})',
    );
  } else {
    debugPrint('Main: Hive supabase_session NOT FOUND in box.');
  }

  // Validation Supabase config (sans ça, on crash plus tard)
  if (SupabaseConstants.url.isEmpty || SupabaseConstants.anonKey.isEmpty) {
    debugPrint('ERROR: Supabase URL or Anon Key is missing.');
    _runErrorApp(
      'Configuration Supabase manquante. Vérifiez vos paramètres --dart-define.',
    );
    return;
  }

  // Bind navigator key AVANT runApp : ref statique consommée par le plugin
  // notifications lors de son init différé.
  PushNotificationService.setNavigatorKey(NotificationService.navigatorKey);

  // PushNotificationService.init() est différé post-runApp : la codebase
  // n'appelle jamais getNotificationAppLaunchDetails, donc le tap depuis
  // cold-launch n'est pas géré aujourd'hui — déférer l'init ne régresse rien
  // et économise ~100-400ms (timezone DB load + platform channel).
  final initsSw = Stopwatch()..start();
  final posthog = PostHogService();
  String? appVersion;
  try {
    await Future.wait<void>([
      Supabase.initialize(
        url: SupabaseConstants.url,
        anonKey: SupabaseConstants.anonKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SupabaseHiveStorage(),
        ),
        headers: {'X-Client-Info': 'supabase-flutter/2.5.0'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint(
            'Main: Supabase.initialize TIMEOUT 10s — throwing to catch block',
          );
          throw TimeoutException(
            'Supabase.initialize timeout after 10 seconds',
          );
        },
      ),
      _initPosthogSafe(posthog),
      _initRevenueCatSafe(),
      _initDownloaderSafe(),
      PackageInfo.fromPlatform().then((info) {
        appVersion = '${info.version}+${info.buildNumber}';
      }).catchError((Object _) {
        // Best-effort — version tracking degrades gracefully
      }),
    ]);
  } catch (e) {
    debugPrint('ERROR: Failed to initialize Supabase: $e');
    _runErrorApp(
      'Erreur d\'initialisation Supabase. Vérifiez la validité de vos clés.',
    );
    return;
  }
  debugPrint('[PERF] boot.critical_inits_ms=${initsSw.elapsedMilliseconds}');

  final hasSession = Supabase.instance.client.auth.currentSession != null;
  debugPrint('Main: Supabase Session restored immediately: $hasSession');

  if (hasSession) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      unawaited(
        posthog.identify(
          userId: user.id,
          properties: _userIdentifyProperties(user, appVersion: appVersion),
        ),
      );
      unawaited(_loginRevenueCatSafe(user.id));
    }
  }
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    switch (data.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
        final user = data.session?.user;
        if (user != null) {
          posthog.identify(
            userId: user.id,
            properties: _userIdentifyProperties(user, appVersion: appVersion),
          );
          unawaited(_loginRevenueCatSafe(user.id));
        }
        break;
      case AuthChangeEvent.signedOut:
        posthog.reset();
        unawaited(_logoutRevenueCatSafe());
        break;
      default:
        break;
    }
  });

  debugPrint('[PERF] boot.pre_runapp_ms=${bootSw.elapsedMilliseconds}');

  // Lancer l'app
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const FacteurApp(),
    ),
  );

  // Inits différés post-runApp : non bloquants pour la 1ère frame.
  // - Notif scheduling (alarm, permissions, diagnostics)
  // - Home Widget callback registration
  unawaited(_initDeferredServices(posthog: posthog));
}

/// Init FlutterDownloader avec fallback silencieux (non-critique).
Future<void> _initDownloaderSafe() async {
  try {
    await FlutterDownloader.initialize(debug: false, ignoreSsl: false);
  } catch (e) {
    debugPrint('Main: FlutterDownloader init failed (non-critical): $e');
  }
}

/// Init PostHog avec fallback silencieux : la télémétrie ne doit jamais
/// crasher le boot.
Future<void> _initPosthogSafe(PostHogService posthog) async {
  try {
    await posthog.init();
  } catch (e) {
    debugPrint('Main: PostHog init failed (non-critical): $e');
  }
}

/// Init RevenueCat — paywall MVP V1, source de vérité de l'entitlement
/// `premium`. Skip silencieux si pas de clé API configurée (dev sans paywall
/// ou plateforme web).
Future<void> _initRevenueCatSafe() async {
  if (kIsWeb) return;
  final bool isIOS = Platform.isIOS;
  if (!RevenueCatConstants.isConfigured(isIOS: isIOS)) {
    debugPrint('Main: RevenueCat skipped (no API key for current platform)');
    return;
  }
  try {
    await Purchases.setLogLevel(LogLevel.warn);
    final apiKey = isIOS
        ? RevenueCatConstants.iosApiKey
        : RevenueCatConstants.androidApiKey;
    await Purchases.configure(PurchasesConfiguration(apiKey));
  } catch (e) {
    debugPrint('Main: RevenueCat init failed (non-critical): $e');
  }
}

/// Identifie l'utilisateur courant côté RevenueCat (post-login Supabase).
/// Permet à un achat Web Billing fait depuis la landing — où l'`app_user_id`
/// est déjà le user_id Supabase — de suivre le bon compte dans l'app.
Future<void> _loginRevenueCatSafe(String userId) async {
  if (kIsWeb) return;
  try {
    await Purchases.logIn(userId);
  } catch (e) {
    debugPrint('Main: Purchases.logIn failed (non-critical): $e');
  }
}

/// Délie l'identité RevenueCat au logout : évite que l'utilisateur suivant
/// hérite par erreur des entitlements du précédent sur un device partagé.
Future<void> _logoutRevenueCatSafe() async {
  if (kIsWeb) return;
  try {
    await Purchases.logOut();
  } catch (e) {
    debugPrint('Main: Purchases.logOut failed (non-critical): $e');
  }
}

/// Services lancés après [runApp] : aucun n'est requis pour la 1ère frame.
///
/// Inclut la planification de la notification quotidienne (system call lente),
/// la vérification d'exact alarm permission, le diagnostic notifs, et
/// l'enregistrement du callback Home Widget. Tout est fire-and-forget côté
/// boot — si un service échoue, le démarrage de l'app n'est pas affecté.
Future<void> _initDeferredServices({required PostHogService posthog}) async {
  final sw = Stopwatch()..start();

  try {
    unawaited(
      HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback),
    );
  } catch (e) {
    debugPrint('Main: Home Widget init failed (non-critical): $e');
  }

  Map<String, dynamic>? bootNotifDiag;
  bool? bootPushEnabledHive;
  try {
    final pushNotificationService = PushNotificationService();
    // L'init plugin (timezone DB + platform channel) coûte ~100-400ms ;
    // déférée car aucun consommateur du tap-callback ne s'active dans la
    // 1ère seconde post-runApp.
    await pushNotificationService.init();

    final settingsBox = Hive.box<dynamic>('settings');
    final pushEnabled = settingsBox.get('push_notifications_enabled',
        defaultValue: true) as bool;
    bootPushEnabledHive = pushEnabled;

    // Diagnostic + scheduling sont indépendants : collecter le diagnostic
    // pendant la planification (alarms + permission). `pushEnabled=false`
    // → on collecte quand même le diagnostic (cf. bug-notifications-stalled).
    final diagFuture = pushNotificationService.getDiagnostics();
    if (pushEnabled) {
      await pushNotificationService.ensureExactAlarmPermission();
      // Si une notification personnalisée (avec les sujets du digest) a été
      // planifiée par DigestNotifier._updateNotificationWithTopics(), on la
      // préserve — écraser avec le corps statique régresserait la feature.
      final alreadyScheduled =
          await pushNotificationService.isDigestNotificationScheduled();
      if (!alreadyScheduled) {
        final scheduled =
            await pushNotificationService.scheduleDailyDigestNotification();
        if (!scheduled) {
          debugPrint(
            'Main: WARNING — digest notification scheduling failed, retrying...',
          );
          await pushNotificationService.requestExactAlarmPermission();
          final retryOk =
              await pushNotificationService.scheduleDailyDigestNotification();
          debugPrint('Main: Retry result: $retryOk');
        }
      } else {
        debugPrint(
          'Main: Digest notification already scheduled — skipping static placeholder.',
        );
      }
    }
    bootNotifDiag = await diagFuture;
  } catch (e, s) {
    debugPrint('ERROR: Deferred push notifications init failed: $e\n$s');
  }

  if (bootNotifDiag != null) {
    final diagProps = <String, Object>{
      'push_enabled_hive': bootPushEnabledHive ?? false,
    };
    bootNotifDiag.forEach((k, v) {
      if (v != null) diagProps[k] = v as Object;
    });
    unawaited(posthog.capture(event: 'notif_diag', properties: diagProps));
  }

  debugPrint('[PERF] boot.deferred_inits_ms=${sw.elapsedMilliseconds}');
}

/// User properties pushed à chaque `$identify` PostHog. Permet de filtrer
/// dashboard et insights par email/provider sans devoir matcher manuellement
/// les distinct_id Supabase.
Map<String, Object> _userIdentifyProperties(User user, {String? appVersion}) {
  final props = <String, Object>{};
  if (user.email != null && user.email!.isNotEmpty) {
    props['email'] = user.email!;
  }
  final providers = user.appMetadata['providers'];
  if (providers is List) {
    props['auth_providers'] = providers.join(',');
  }
  if (appVersion != null) {
    props['app_version'] = appVersion;
  }
  return props;
}

/// Background callback for home widget interactions (required by home_widget).
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  // Widget taps are handled via PendingIntents in Kotlin, so this is a no-op.
  debugPrint('HomeWidget callback: $uri');
}

/// Open a Hive box safely — if corrupted, delete and recreate it.
///
/// Une corruption sur la box `supabase_auth_persistence` provoque un logout
/// silencieux (la session est perdue). On logge donc explicitement l'événement
/// pour télémétrie.
/// TODO(sentry): remplacer par `Sentry.captureMessage(level: error)` dès que
/// `sentry_flutter` sera initialisé.
/// Cf. docs/bugs/bug-android-session-forced-logouts.md.
Future<Box<T>> _openBoxSafe<T>(String name) async {
  try {
    return await Hive.openBox<T>(name);
  } catch (e) {
    debugPrint('Main: Hive box "$name" corrupted, recreating: $e');
    debugPrint(
      '[AUTH_TELEMETRY] event=hive_box_corrupted box_name=$name error=$e',
    );
    await Hive.deleteBoxFromDisk(name);
    return await Hive.openBox<T>(name);
  }
}

void _runErrorApp(String message) {
  runApp(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
