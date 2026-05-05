import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:home_widget/home_widget.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

import 'app.dart';
import 'config/constants.dart';
import 'core/auth/supabase_storage.dart';
import 'core/services/posthog_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/ui/notification_service.dart';

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
    await SentryFlutter.init(
      (options) {
        options.dsn = SentryConstants.dsn;
        options.environment = SentryConstants.environment;
        if (SentryConstants.release.isNotEmpty) {
          options.release = SentryConstants.release;
        }
        // Sample 100% des erreurs, pas de perf tracing pour le moment.
        options.tracesSampleRate = 0.0;
        // Ne pas envoyer les PII par défaut.
        options.sendDefaultPii = false;
      },
      appRunner: _bootstrap,
    );
  } else {
    await _bootstrap();
  }
}

Future<void> _bootstrap() async {

  // Initialiser timeago
  timeago.setLocaleMessages('fr', fr_messages.FrMessages());
  timeago.setLocaleMessages('fr_short', FrCompactMessages());

  // Orientation portrait uniquement
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // Initialiser Hive (storage local)
  await Hive.initFlutter();

  // Initialiser flutter_downloader (Android DownloadManager) pour la mise
  // à jour APK : permet au téléchargement de continuer en arrière-plan.
  try {
    await FlutterDownloader.initialize(debug: false, ignoreSsl: false);
  } catch (e) {
    debugPrint('Main: FlutterDownloader init failed (non-critical): $e');
  }

  // Pré-ouvrir les boxes et vérifier leur contenu
  // Try-catch avec fallback : si un box est corrompu, on le recrée vide
  debugPrint('Main: Opening Hive boxes...');
  await _openBoxSafe<dynamic>('settings');
  final authBox = await _openBoxSafe<dynamic>('auth_prefs');
  final supabaseBox = await _openBoxSafe<String>('supabase_auth_persistence');
  await _openBoxSafe<String>('feed_cache');

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

  // Initialiser les notifications push locales (sans forcer la permission)
  Map<String, dynamic>? bootNotifDiag;
  bool? bootPushEnabledHive;
  try {
    debugPrint('Main: Initializing push notifications...');
    final pushNotificationService = PushNotificationService();
    PushNotificationService.setNavigatorKey(NotificationService.navigatorKey);
    await pushNotificationService.init();

    // Planifier uniquement si l'utilisateur a déjà autorisé les notifications
    final settingsBox = Hive.box<dynamic>('settings');
    final pushEnabled = settingsBox.get('push_notifications_enabled',
        defaultValue: true) as bool;
    bootPushEnabledHive = pushEnabled;
    if (pushEnabled) {
      // S'assurer que la permission exact alarm est toujours valide
      // (peut être révoquée par une mise à jour Android ou un changement système)
      await pushNotificationService.ensureExactAlarmPermission();

      // Ne planifier la notification statique que si aucune n'existe déjà.
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
              'Main: WARNING — digest notification scheduling failed, retrying...');
          // Retry après re-demande explicite de permission
          await pushNotificationService.requestExactAlarmPermission();
          final retryOk =
              await pushNotificationService.scheduleDailyDigestNotification();
          debugPrint('Main: Retry result: $retryOk');
        }
      } else {
        debugPrint(
            'Main: Digest notification already scheduled — skipping static placeholder.');
      }
    }

    // Toujours collecter le diagnostic — y compris quand pushEnabled=false —
    // pour mesurer le parc côté télémétrie (cf. bug-notifications-stalled).
    bootNotifDiag = await pushNotificationService.getDiagnostics();
    debugPrint('Main: Push diagnostics: $bootNotifDiag');
    debugPrint('Main: Push notifications initialized (enabled: $pushEnabled)');
  } catch (e, s) {
    debugPrint('ERROR: Failed to initialize push notifications: $e\n$s');
  }

  // Initialize Home Widget for Android home screen widget
  try {
    HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);
    debugPrint('Main: Home Widget initialized.');
  } catch (e) {
    debugPrint('Main: Home Widget init failed (non-critical): $e');
  }

  // Validation Supabase avant initialisation
  if (SupabaseConstants.url.isEmpty || SupabaseConstants.anonKey.isEmpty) {
    debugPrint('ERROR: Supabase URL or Anon Key is missing.');
    _runErrorApp(
      'Configuration Supabase manquante. Vérifiez vos paramètres --dart-define.',
    );
    return;
  }

  // Initialisation Analytics
  // Note: On le fait tôt pour choper le launch
  // Mais on a besoin de Dio qui est dans le container...
  // On va le faire via le provider plus tard ou ici si on instancie manuellement
  // Pour l'instant on laisse le provider s'en occuper au premier build de FacteurApp

  try {
    final url = SupabaseConstants.url;
    final key = SupabaseConstants.anonKey;

    // Initialiser Supabase avec timeout de sécurité
    debugPrint('Main: Initializing Supabase...');
    debugPrint('Main: Supabase URL: ${SupabaseConstants.url}');
    await Supabase.initialize(
      url: url,
      anonKey: key,
      authOptions: FlutterAuthClientOptions(
        localStorage: SupabaseHiveStorage(),
      ),
      headers: {
        'X-Client-Info': 'supabase-flutter/2.5.0',
      },
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint(
            'Main: Supabase.initialize TIMEOUT - throwing to catch block');
        throw TimeoutException('Supabase.initialize timeout after 15 seconds');
      },
    );
    debugPrint('Main: Supabase initialized correctly.');
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    debugPrint('Main: Supabase Session restored immediately: $hasSession');

    // Story 14.1 — init PostHog after Supabase so we can piggyback on the
    // auth state stream to identify/reset the distinct_id automatically.
    final posthog = PostHogService();
    await posthog.init();

    // Émettre l'état des notifs locales collecté au boot (capture après init
    // PostHog : avant, capture() est un no-op silencieux).
    if (bootNotifDiag != null) {
      final diagProps = <String, Object>{
        'push_enabled_hive': bootPushEnabledHive ?? false,
      };
      bootNotifDiag.forEach((k, v) {
        if (v != null) diagProps[k] = v as Object;
      });
      unawaited(posthog.capture(event: 'notif_diag', properties: diagProps));
    }

    if (hasSession) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await posthog.identify(
          userId: user.id,
          properties: _userIdentifyProperties(user),
        );
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
              properties: _userIdentifyProperties(user),
            );
          }
          break;
        case AuthChangeEvent.signedOut:
          posthog.reset();
          break;
        default:
          break;
      }
    });
  } catch (e) {
    debugPrint('ERROR: Failed to initialize Supabase: $e');
    _runErrorApp(
      'Erreur d\'initialisation Supabase. Vérifiez la validité de vos clés.',
    );
    return;
  }

  // Lancer l'app
  debugPrint('Main: Calling runApp...');
  runApp(const ProviderScope(child: FacteurApp()));
  debugPrint('Main: runApp called.');
}

/// User properties pushed à chaque `$identify` PostHog. Permet de filtrer
/// dashboard et insights par email/provider sans devoir matcher manuellement
/// les distinct_id Supabase.
Map<String, Object> _userIdentifyProperties(User user) {
  final props = <String, Object>{};
  if (user.email != null && user.email!.isNotEmpty) {
    props['email'] = user.email!;
  }
  final providers = user.appMetadata['providers'];
  if (providers is List) {
    props['auth_providers'] = providers.join(',');
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
        '[AUTH_TELEMETRY] event=hive_box_corrupted box_name=$name error=$e');
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
