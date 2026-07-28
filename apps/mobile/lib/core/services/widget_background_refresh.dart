import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../config/constants.dart';
import '../../features/feed/repositories/feed_repository.dart';
import '../auth/supabase_storage.dart';
import 'widget_service.dart';

/// Rafraîchissement du widget d'accueil **app fermée**.
///
/// Sans ça, rien ne rafraîchissait le widget hors app vivante :
/// `homeWidgetBackgroundCallback` est un no-op assumé, le handler FCM de fond
/// ne touche pas [WidgetService], et l'alarme système `updatePeriodMillis`
/// (30 min) se contente de **repeindre les mêmes octets** — `onUpdate` relit
/// SharedPreferences sans jamais toucher au réseau. Cf.
/// docs/bugs/bug-widget-fiabilite.md (C6).
///
/// Contraintes de conception, toutes issues des autres causes racines :
///  - **Dio nu**, sans les interceptors d'`ApiClient` : un 401 en tâche de fond
///    ne doit jamais pouvoir armer `onAuthError` → `signOut` (leçon de C3) ;
///  - pas de session restaurable → **abandon silencieux**, jamais de purge ;
///  - fusion et non remplacement du payload (une page = 20 articles, le widget
///    en garde 80) via [WidgetService.updateWidgetMergingFlux].
class WidgetBackgroundRefresh {
  const WidgetBackgroundRefresh._();

  static const String taskName = 'facteur_widget_refresh';
  static const String uniqueName = 'facteur_widget_refresh_periodic';

  /// WorkManager applique un plancher de 15 min ; 1 h est un compromis entre
  /// fraîcheur perçue et budget batterie/quota.
  static const Duration frequency = Duration(hours: 1);

  /// Une seule page suffit : le buffer widget est alimenté en union.
  static const int _pageSize = 20;

  /// Enregistre la tâche périodique. Android uniquement (pas de widget iOS —
  /// ni extension ni app group). Idempotent : `keep` laisse la tâche déjà
  /// planifiée poursuivre son cycle.
  static Future<void> register() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().initialize(widgetRefreshCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        uniqueName,
        taskName,
        frequency: frequency,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('WidgetBackgroundRefresh: register failed (non-critical): $e');
    }
  }

  /// Annule la tâche. Appelé au logout, à côté de `WidgetService.clear()` :
  /// sans ça, le job continuerait à réécrire le widget avec le flux de
  /// l'utilisateur précédent.
  static Future<void> cancel() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(uniqueName);
    } catch (e) {
      debugPrint('WidgetBackgroundRefresh: cancel failed (non-critical): $e');
    }
  }

  /// Le travail réel, exécuté dans l'isolate de fond.
  ///
  /// Retourne `true` même en cas d'échec « normal » (pas de session, réseau
  /// coupé) : ce n'est pas une erreur à retenter agressivement, le prochain
  /// cycle réessaiera de toute façon.
  static Future<bool> run() async {
    try {
      await Hive.initFlutter();
      final storage = SupabaseHiveStorage();
      await storage.initialize();
      if (!await storage.hasAccessToken()) {
        debugPrint('WidgetBackgroundRefresh: no persisted session, skipping.');
        return true;
      }

      await Supabase.initialize(
        url: SupabaseConstants.url,
        anonKey: SupabaseConstants.anonKey,
        authOptions: FlutterAuthClientOptions(localStorage: storage),
      );

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        debugPrint('WidgetBackgroundRefresh: session not recovered, skipping.');
        return true;
      }
      final token = session.isExpired
          ? (await Supabase.instance.client.auth.refreshSession())
              .session
              ?.accessToken
          : session.accessToken;
      if (token == null) {
        debugPrint('WidgetBackgroundRefresh: refresh yielded no token.');
        return true;
      }

      // Dio nu, délibérément : aucun interceptor auth, aucun chemin vers
      // `handleSessionExpired`.
      final dio = Dio(
        BaseOptions(
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      final response = await dio.get<dynamic>(
        'feed/',
        queryParameters: {'page': 1, 'limit': _pageSize},
      );
      // Même parseur que le chemin nominal : `parseFeedData` est statique et
      // sans `ApiClient`, donc utilisable tel quel depuis l'isolate. Deux
      // parseurs pour le même endpoint, c'est la garantie qu'un changement de
      // schéma ferait silencieusement retomber le widget à vide.
      final items = FeedRepository.parseFeedData(
        data: response.data,
        page: 1,
        limit: _pageSize,
      ).items;
      if (items.isEmpty) {
        debugPrint('WidgetBackgroundRefresh: empty feed, nothing to push.');
        return true;
      }

      await WidgetService.updateWidgetMergingFlux(items);
      debugPrint('WidgetBackgroundRefresh: pushed ${items.length} fresh rows.');
      return true;
    } catch (e) {
      // Best-effort de bout en bout : un widget en retard vaut mieux qu'un
      // job qui boucle en retry.
      debugPrint('WidgetBackgroundRefresh: run failed: $e');
      return true;
    }
  }
}

/// Point d'entrée de l'isolate WorkManager. Doit rester une fonction top-level
/// annotée `vm:entry-point` (l'AOT la supprimerait sinon).
@pragma('vm:entry-point')
void widgetRefreshCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != WidgetBackgroundRefresh.taskName) return true;
    return WidgetBackgroundRefresh.run();
  });
}
