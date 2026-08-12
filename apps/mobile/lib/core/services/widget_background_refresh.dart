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

  /// Tâche one-shot du bouton 🔄 du widget, distincte de la périodique pour ne
  /// pas annuler son cycle.
  static const String immediateName = 'facteur_widget_refresh_now';

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

  /// Enfile un rafraîchissement **immédiat**, déclenché par le bouton 🔄 du
  /// widget.
  ///
  /// Pourquoi passer par WorkManager plutôt que faire le travail sur place :
  /// l'isolate qui exécute cette méthode est celui de `home_widget`, porté par
  /// un `JobIntentService` dont le `onHandleWork` **poste** l'appel Dart puis
  /// retourne aussitôt, sans attendre sa fin. Android considère alors le
  /// travail terminé et peut tuer le process — ce qui coupait le
  /// rafraîchissement en plein vol et laissait le masthead figé sur « Mise à
  /// jour… », le repaint final n'arrivant jamais.
  /// `BackgroundWorker` de WorkManager, lui, rend un `ListenableFuture` qui ne
  /// se résout qu'à la fin de la tâche Dart : le process est maintenu en vie.
  /// Cf. docs/bugs/bug-widget-flaner-android.md (D4-bis).
  ///
  /// Ce que fait cette méthode est donc volontairement minuscule (un enqueue,
  /// quelques millisecondes) : elle tient largement dans la fenêtre incertaine
  /// de l'isolate `home_widget`.
  ///
  /// Volontairement **sans** `outOfQuotaPolicy` : demander une tâche
  /// *expedited* fait passer WorkManager par `setExpedited()`, qui lève si le
  /// quota ou la configuration ne s'y prêtent pas — et une exception ici ne
  /// coûte pas seulement la latence, elle prive le bouton de tout
  /// rafraîchissement. Le gain était marginal : l'utilisateur vient de taper
  /// son écran d'accueil, l'appareil est réveillé et une tâche one-shot sans
  /// contrainte autre que le réseau démarre de toute façon en quelques
  /// secondes.
  static Future<void> requestImmediateRefresh() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().initialize(widgetRefreshCallbackDispatcher);
      await Workmanager().registerOneOffTask(
        immediateName,
        taskName,
        constraints: Constraints(networkType: NetworkType.connected),
        // `replace` : deux appuis rapprochés ne doivent pas empiler deux
        // rafraîchissements réseau concurrents.
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } catch (e) {
      debugPrint('WidgetBackgroundRefresh: immediate enqueue failed: $e');
      // L'enqueue a échoué : on sort quand même le widget de « Mise à jour… »,
      // sinon il resterait figé sur un état transitoire sans issue.
      await WidgetService.finishRefresh();
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

  /// `Supabase.initialize` est **une fois par isolate**, pas une fois par run.
  ///
  /// L'isolate de fond de `home_widget` réutilise son `FlutterEngine` d'un
  /// réveil à l'autre (champ statique dans `HomeWidgetBackgroundService`) :
  /// depuis que le bouton 🔄 passe par ce chemin, [run] peut être appelée
  /// plusieurs fois dans la même vie d'isolate. Un second `initialize` lève —
  /// l'exception était avalée par le `catch` général de [run], et le refresh
  /// n'échouait qu'à partir du **deuxième** appui, ce qui donne exactement le
  /// symptôme « le bouton marche une fois sur deux ».
  static bool _supabaseReady = false;

  static Future<void> _ensureSupabase(SupabaseHiveStorage storage) async {
    if (_supabaseReady) return;
    try {
      await Supabase.initialize(
        url: SupabaseConstants.url,
        anonKey: SupabaseConstants.anonKey,
        authOptions: FlutterAuthClientOptions(localStorage: storage),
      );
    } catch (e) {
      // Déjà initialisé (deux réveils rapprochés dans le même isolate) : on
      // relit l'instance pour confirmer qu'elle répond — si elle ne répond pas,
      // l'exception remonte et [run] la traitera comme un échec franc plutôt
      // que de poursuivre sur un client mort.
      final client = Supabase.instance.client;
      debugPrint(
        'WidgetBackgroundRefresh: Supabase already initialized '
        '(${client.runtimeType}) — $e',
      );
    }
    _supabaseReady = true;
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

      await _ensureSupabase(storage);

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
    } finally {
      // Quoi qu'il arrive — pas de session, hors ligne, feed vide, exception —
      // le widget doit sortir de « Mise à jour… ». C'est le seul endroit qui
      // le garantit : tous les chemins de [run] passent ici.
      await WidgetService.finishRefresh();
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
