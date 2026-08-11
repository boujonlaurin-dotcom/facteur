import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import '../../config/topic_labels.dart';
import '../../features/feed/models/content_model.dart';
import '../../features/gamification/models/streak_model.dart';

/// Outcome of [WidgetService.requestPinWidget]. The three failure modes used to
/// be indistinguishable (everything was swallowed into a `debugPrint`), which
/// is why the « Ajouter un Widget » button looked dead.
enum WidgetPinResult {
  /// Android accepted the request — the launcher shows its confirmation dialog.
  requested,

  /// Launcher / OS version does not support programmatic pinning (API < 26 or
  /// a launcher that opted out). The user has to add the widget manually.
  unsupported,

  /// The platform call threw. Genuine bug territory.
  failed,
}

/// Service qui pousse le flux **Flâner** vers les widgets d'écran d'accueil.
///
/// Chemin de données : Flutter → SharedPreferences (via home_widget) →
/// FacteurWidget.kt
///
/// **Le widget est un miroir de Flâner, et rien d'autre.** Il a longtemps
/// affiché « L'Essentiel du jour puis le Flux » : le bloc Essentiel venait de
/// `articles_json`, écrit par le seul `DigestNotifier`. Depuis que L'Essentiel
/// a fusionné dans la Tournée du jour, ce provider n'est plus construit dans
/// le parcours nominal — la clé gardait donc **indéfiniment** son dernier
/// snapshot, en tête du payload (jamais évincé par le cap), pendant que le
/// refresh de fond ne rafraîchissait que la partie Flux, sous ce bloc fossile.
/// C'est le « mon widget n'a pas bougé depuis 14 jours » de
/// docs/bugs/bug-widget-flaner-android.md (D1).
///
/// Schéma :
/// - `widget_articles_json` : payload rendu par le natif — Flâner dédupliqué,
///   **trié par date décroissante**, capé à [_maxTotal].
/// - `feed_articles_json` : cache de la source, relu par
///   [updateWidgetMergingFlux] pour fusionner sans perdre la profondeur.
/// - `articles_updated_at` : epoch millis du dernier push réussi — c'est
///   l'heure affichée dans le masthead (« Maj 7h02 »).
/// - `widget_last_push_count` : profondeur réelle du dernier payload
///   (diagnostic).
/// - `streak` : conservée, lue par personne côté natif aujourd'hui.
/// - `widget_flux_max_scroll_position` / `widget_flux_total_count` /
///   `widget_flux_max_scroll_at` : métrique de scroll écrite nativement,
///   remontée par l'app au prochain premier plan.
class WidgetService {
  // Two AppWidgetProvider classes are registered in AndroidManifest.xml:
  // FacteurWidgetLight (parchment) and FacteurWidgetDark (charcoal). Each is
  // pinned independently by the user — both must be updated on every push.
  static const _androidNameLight = 'FacteurWidgetLight';
  static const _androidNameDark = 'FacteurWidgetDark';

  /// Fully-qualified receiver names, derived from the Gradle **namespace**
  /// (`android/app/build.gradle.kts` → `namespace = "com.example.facteur"`),
  /// NOT from the applicationId.
  ///
  /// The trap: `HomeWidgetPlugin.kt` resolves a bare [androidName] as
  /// `"${context.packageName}.$className"`, and `context.packageName` is the
  /// **applicationId** — `com.example.facteur.staging` on the `beta` flavor,
  /// `facteur.app` on `playstore`. Neither matches the namespace the receivers
  /// actually live in, so every call threw `ClassNotFoundException` and no
  /// `ACTION_APPWIDGET_UPDATE` was ever broadcast. Passing
  /// `qualifiedAndroidName` bypasses that concatenation entirely.
  ///
  /// If the namespace ever changes, these must follow — guarded by
  /// `test/core/services/widget_service_test.dart`, which reads the namespace
  /// straight out of `build.gradle.kts`.
  static const androidNamespace = 'com.example.facteur';
  static const _qualifiedLight = '$androidNamespace.$_androidNameLight';
  static const _qualifiedDark = '$androidNamespace.$_androidNameDark';

  /// Broadcast `ACTION_APPWIDGET_UPDATE` to both receivers. Always pass the
  /// qualified name; `androidName` is kept as a fallback for any plugin
  /// version that would not honour the qualified one.
  static Future<void> _pushUpdate() {
    return Future.wait([
      HomeWidget.updateWidget(
        androidName: _androidNameLight,
        qualifiedAndroidName: _qualifiedLight,
      ),
      HomeWidget.updateWidget(
        androidName: _androidNameDark,
        qualifiedAndroidName: _qualifiedDark,
      ),
    ]);
  }

  static const _maxFeedArticles = 80;

  /// Cap du payload rendu. 80 lignes tiennent largement sous le plafond IPC
  /// Binder (~1 Mo) puisque les lignes ne portent pas de vignette — seulement
  /// un logo de source (cf. widget.5).
  static const _maxTotal = 80;

  static final _dio = Dio();

  /// Pousse le flux Flâner (et/ou la série) vers les deux widgets.
  ///
  /// [feedItems] doit être le flux **non filtré** : le widget est un miroir de
  /// Flâner par défaut, pas de la vue filtrée en cours.
  static Future<void> updateWidget({
    List<Content>? feedItems,
    StreakModel? streak,
  }) async {
    try {
      if (feedItems != null) {
        final items = await _buildFeedArticleList(feedItems);
        await HomeWidget.saveWidgetData(
          'feed_articles_json',
          jsonEncode(items),
        );
      }

      if (streak != null) {
        await HomeWidget.saveWidgetData('streak', '${streak.currentStreak}');
      }

      if (feedItems != null) {
        await _rewriteRenderedPayload();
      }

      await _pushUpdate();
    } catch (e) {
      debugPrint('WidgetService: updateWidget failed: $e');
    }
  }

  /// Fusionne des lignes Flux fraîches **par-dessus** le cache existant, au
  /// lieu de le remplacer, puis pousse le widget.
  ///
  /// Réservé au rafraîchissement de fond, qui ne récupère qu'une page (20
  /// articles) : un `updateWidget(feedItems:)` classique ferait retomber le
  /// payload de 80 à 20 lignes, soit exactement le symptôme « 9 articles »
  /// qu'on vient de corriger. Union dédupliquée par `id`, frais en tête,
  /// capée à [_maxFeedArticles], rangs réindexés.
  static Future<void> updateWidgetMergingFlux(List<Content> freshItems) async {
    try {
      if (freshItems.isEmpty) return;
      final fresh = await _buildFeedArticleList(freshItems);
      final cachedJson =
          await HomeWidget.getWidgetData<String>('feed_articles_json') ?? '[]';
      final cached = _decodeList(cachedJson);

      final merged = buildWidgetPayload([...fresh, ...cached]);

      await HomeWidget.saveWidgetData(
        'feed_articles_json',
        jsonEncode(merged),
      );
      await _rewriteRenderedPayload();
      await _pushUpdate();
    } catch (e) {
      debugPrint('WidgetService: updateWidgetMergingFlux failed: $e');
    }
  }

  /// Purge le bloc « Essentiel » fossile laissé par les versions antérieures.
  ///
  /// Sans ça, une install existante garderait son `articles_json` vieux de
  /// plusieurs jours **en tête** du payload rendu jusqu'à la prochaine
  /// réécriture complète — soit exactement le bug qu'on corrige, mais après
  /// mise à jour de l'app. Idempotent : no-op dès que les clés sont vides.
  ///
  /// Appelée au boot, **avant** [initWidgetIfNeeded] (qui, lui, s'abstient dès
  /// qu'un payload non vide existe — y compris un payload fossile).
  static Future<void> purgeLegacyEssentielPayload() async {
    try {
      final legacy =
          await HomeWidget.getWidgetData<String>('articles_json') ?? '';
      if (legacy.isEmpty || legacy == '[]') return;
      await HomeWidget.saveWidgetData('articles_json', '[]');
      await HomeWidget.saveWidgetData('digest_status', 'none');
      await HomeWidget.saveWidgetData('digest_progress', '0/0');
      // Réécrit le payload rendu depuis le seul cache Flâner, sinon le bloc
      // fossile resterait affiché jusqu'au prochain push de feed.
      await _rewriteRenderedPayload();
      await _pushUpdate();
      debugPrint('WidgetService: purged legacy Essentiel payload');
    } catch (e) {
      debugPrint('WidgetService: purgeLegacyEssentielPayload failed: $e');
    }
  }

  /// Push a placeholder payload when no data is available yet (cold install,
  /// pre-first-fetch). Idempotent — checked via SharedPreferences.
  static Future<void> initWidgetIfNeeded() async {
    try {
      final existing = await HomeWidget.getWidgetData<String>(
        'widget_articles_json',
      );
      if (existing != null && existing.isNotEmpty && existing != '[]') {
        return;
      }
      await HomeWidget.saveWidgetData(
        'feed_articles_json',
        jsonEncode(<dynamic>[]),
      );
      await HomeWidget.saveWidgetData(
        'widget_articles_json',
        jsonEncode(<dynamic>[]),
      );
      await _pushUpdate();
    } catch (e) {
      debugPrint('WidgetService: initWidgetIfNeeded failed: $e');
    }
  }

  /// Re-diffuse `ACTION_APPWIDGET_UPDATE` sans toucher aux données.
  ///
  /// Sert à sortir le widget d'un état transitoire peint par le natif (« Mise
  /// à jour… ») quand le rafraîchissement n'a rien produit — pas de session,
  /// hors ligne, feed vide. Le natif relit alors SharedPreferences et repeint
  /// le payload courant.
  static Future<void> repaint() async {
    try {
      await _pushUpdate();
    } catch (e) {
      debugPrint('WidgetService: repaint failed: $e');
    }
  }

  /// Wipe widget data on logout so the next user never briefly sees the
  /// previous account's articles on their home screen.
  static Future<void> clear() async {
    try {
      await HomeWidget.saveWidgetData('articles_json', '[]');
      await HomeWidget.saveWidgetData('feed_articles_json', '[]');
      await HomeWidget.saveWidgetData('widget_articles_json', '[]');
      await HomeWidget.saveWidgetData('articles_updated_at', '0');
      await HomeWidget.saveWidgetData('streak', '0');
      await _pushUpdate();
    } catch (e) {
      debugPrint('WidgetService: clear failed: $e');
    }
  }

  /// Request Android to pin one of the two widgets to the home screen. We pin
  /// the Clair variant by default — the user can later swap it with Sombre
  /// from the launcher if they prefer.
  ///
  /// Returns a typed outcome so the caller can tell the user what happened:
  /// a silent failure here is exactly what made the CTA look broken.
  static Future<WidgetPinResult> requestPinWidget() async {
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (supported != true) return WidgetPinResult.unsupported;
      await HomeWidget.requestPinWidget(
        androidName: _androidNameLight,
        qualifiedAndroidName: _qualifiedLight,
      );
      return WidgetPinResult.requested;
    } catch (e) {
      debugPrint('WidgetService: requestPinWidget failed: $e');
      return WidgetPinResult.failed;
    }
  }

  /// `true` when at least one Facteur widget is currently pinned on the home
  /// screen. Drives the « Ajouter le widget » banner (hidden once pinned).
  ///
  /// Unlike [updateWidget], this path is NOT affected by the applicationId ≠
  /// namespace trap: the plugin enumerates providers via
  /// `getInstalledProvidersForPackage(context.packageName)` instead of
  /// resolving a class name. Returns `null` when the platform call fails, so
  /// callers can distinguish « not pinned » from « unknown ».
  static Future<bool?> isWidgetPinned() async {
    try {
      final installed = await HomeWidget.getInstalledWidgets();
      return installed.any((w) {
        final name = w.androidClassName ?? '';
        return name.endsWith(_androidNameLight) ||
            name.endsWith(_androidNameDark);
      });
    } catch (e) {
      debugPrint('WidgetService: isWidgetPinned failed: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Payload — dédup, tri chronologique, cap.
  // ──────────────────────────────────────────────────────────────

  /// Dédup par `id`, **tri par `published_at_iso` décroissant**, cap à
  /// [_maxTotal], puis réindexation des `rank`. Fonction pure — c'est la seule
  /// définition de « l'ordre du widget », exposée pour les tests.
  ///
  /// Le tri est explicite parce qu'aucun des appelants ne le garantit :
  /// [updateWidgetMergingFlux] concatène une page fraîche devant un buffer de
  /// 80, et `FeedNotifier` fusionne dans son ordre d'arrivée réseau. Sans tri,
  /// le widget affichait un ordre d'arrivée qui ne ressemblait plus à Flâner
  /// dès la première fusion de fond.
  ///
  /// Une entrée sans date reconnaissable est **conservée** mais reléguée en
  /// fin de liste : on ne jette pas un article parce que le serveur a omis sa
  /// date, mais on ne le hisse pas non plus en tête.
  @visibleForTesting
  static List<Map<String, dynamic>> buildWidgetPayload(
    List<Map<String, dynamic>> entries,
  ) {
    final deduped = <({Map<String, dynamic> entry, int index})>[];
    final seenIds = <String>{};
    for (final e in entries) {
      final id = (e['id'] as String?) ?? '';
      if (id.isEmpty || !seenIds.add(id)) continue;
      deduped.add((entry: e, index: deduped.length));
    }

    // Le rang d'entrée départage les ex æquo. `List.sort` n'est **pas** stable
    // en Dart (quicksort au-delà de ~32 éléments) : sans ce départage, deux
    // articles de même date — ou tout un lot sans date — se réordonnaient d'un
    // push à l'autre, ce qui fait clignoter le widget et invalide le garde de
    // signature de `_scheduleWidgetPush`.
    deduped.sort((a, b) {
      final da = _publishedAtOf(a.entry);
      final db = _publishedAtOf(b.entry);
      if (da != null && db != null) {
        final byDate = db.compareTo(da);
        if (byDate != 0) return byDate;
      } else if (da == null && db != null) {
        return 1;
      } else if (da != null && db == null) {
        return -1;
      }
      return a.index.compareTo(b.index);
    });

    final capped =
        deduped.take(_maxTotal).map((e) => e.entry).toList(growable: false);
    return [
      for (var i = 0; i < capped.length; i++) {...capped[i], 'rank': i + 1},
    ];
  }

  static DateTime? _publishedAtOf(Map<String, dynamic> entry) {
    final raw = entry['published_at_iso'];
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> _rewriteRenderedPayload() async {
    final fluxJson =
        await HomeWidget.getWidgetData<String>('feed_articles_json') ?? '[]';
    final rendered = buildWidgetPayload(_decodeList(fluxJson));
    await HomeWidget.saveWidgetData(
      'widget_articles_json',
      jsonEncode(rendered),
    );
    // L'heure lue par le masthead. Écrite ici — donc sur **tous** les chemins
    // de push, et pas seulement sur la fusion de fond comme avant : sinon le
    // widget affichait « Maj » d'un refresh de fond vieux de plusieurs heures
    // juste après un push d'app tout frais.
    await HomeWidget.saveWidgetData(
      'articles_updated_at',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    // Diagnostic « le widget n'affiche que 9 articles » : on persiste la
    // profondeur réelle du payload plutôt que de la déduire de l'écran.
    await HomeWidget.saveWidgetData<int>(
      'widget_last_push_count',
      rendered.length,
    );
    debugPrint('WidgetService: pushed ${rendered.length} rows to widget');
  }

  static List<Map<String, dynamic>> _decodeList(String raw) {
    if (raw.isEmpty || raw == '[]') return const [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const [];
      return parsed
          .whereType<Map<String, dynamic>>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false);
    } catch (e) {
      debugPrint('WidgetService: _decodeList failed: $e');
      return const [];
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Sérialisation Flâner
  // ──────────────────────────────────────────────────────────────

  /// Sérialise le flux Flâner (max 80). Pas de vignette (cf. widget.5) — seul
  /// le logo de source, bien plus léger, est inliné.
  static Future<List<Map<String, dynamic>>> _buildFeedArticleList(
    List<Content> items,
  ) async {
    if (items.isEmpty) return const [];
    final capped = items.take(_maxFeedArticles).toList(growable: false);
    return Future.wait([
      for (var i = 0; i < capped.length; i++)
        _serializeFeedItem(item: capped[i], rank: i + 1),
    ]);
  }

  static Future<Map<String, dynamic>> _serializeFeedItem({
    required Content item,
    required int rank,
  }) async {
    final logoPath = await _cachedLogo(item.source.logoUrl);

    final topicSlug = item.topics.isNotEmpty ? item.topics.first : '';
    final topicLabel = topicSlugToLabel[topicSlug] ?? '';

    return {
      'id': item.id,
      'rank': rank,
      'topic_id': topicSlug,
      'topic_label': topicLabel,
      'title': item.title,
      'source_name': item.source.name,
      'source_logo_path': logoPath ?? '',
      // `publishedAtRaw`, pas `publishedAt` : ce dernier retombe sur
      // `DateTime.now()` quand le serveur n'envoie pas de date, ce qui fige un
      // « à l'instant » perpétuel dans un payload relu des jours plus tard.
      // Chaîne vide ⇒ le natif n'affiche aucune date (cf. bug D2).
      'published_at_iso': item.publishedAtRaw?.toUtc().toIso8601String() ?? '',
    };
  }

  // ──────────────────────────────────────────────────────────────
  // Flux scroll metric (widget → app, flushed on foreground)
  // ──────────────────────────────────────────────────────────────

  /// Read the scroll metric written by the native RemoteViewsFactory and
  /// clear it. Returns `null` when no session is pending (`-1` sentinel).
  ///
  /// Called by the app on cold start + each `AppLifecycleState.resumed` so the
  /// scroll session that ended while the app was in background is logged
  /// exactly once. The clear-on-read makes it idempotent. The PostHog event
  /// keeps its `widget_flux_*` keys for funnel continuity, even though the
  /// session now spans the unified feed (Essentiel + Flux).
  static Future<({int maxPosition, int totalCount, DateTime? at})?>
      readAndClearFluxScrollMetric() async {
    try {
      final position = await HomeWidget.getWidgetData<int>(
            'widget_flux_max_scroll_position',
            defaultValue: -1,
          ) ??
          -1;
      if (position < 0) return null;
      final total = await HomeWidget.getWidgetData<int>(
            'widget_flux_total_count',
            defaultValue: 0,
          ) ??
          0;
      final atMs = await HomeWidget.getWidgetData<int>(
            'widget_flux_max_scroll_at',
            defaultValue: 0,
          ) ??
          0;

      // Reset so the next foreground doesn't re-fire the event.
      await HomeWidget.saveWidgetData<int>(
        'widget_flux_max_scroll_position',
        -1,
      );
      await HomeWidget.saveWidgetData<int>('widget_flux_total_count', 0);
      await HomeWidget.saveWidgetData<int>('widget_flux_max_scroll_at', 0);

      return (
        maxPosition: position,
        totalCount: total,
        at: atMs > 0 ? DateTime.fromMillisecondsSinceEpoch(atMs) : null,
      );
    } catch (e) {
      debugPrint('WidgetService: readAndClearFluxScrollMetric failed: $e');
      return null;
    }
  }

  /// Logo de source, mis en cache **par URL** et non par rang.
  ///
  /// Deux raisons de ne plus indexer par rang (`widget_feed_logo_$rank.png`) :
  ///  - le fichier du rang N était réécrit à chaque push, donc une entrée de
  ///    payload conservée d'un push précédent pointait vers les octets d'une
  ///    *autre* source (visible dès qu'on fusionne au lieu de remplacer) ;
  ///  - chaque push re-téléchargeait jusqu'à 80 logos identiques. Un logo ne
  ///    change pas : s'il est déjà sur le disque, on le réutilise.
  ///
  /// Single-flight par URL : [_buildFeedArticleList] sérialise les 80 lignes
  /// via `Future.wait`, donc les N articles d'une même source arrivaient ici
  /// en parallèle et lançaient N sondes — voire N téléchargements concurrents
  /// écrivant *le même* fichier. On partage la première future par URL.
  static final Map<String, Future<String?>> _logoInflight = {};

  static Future<String?> _cachedLogo(String? url) {
    if (url == null || url.isEmpty) return Future.value(null);
    return _logoInflight[url] ??= _resolveLogo(url).then((path) {
      // Une URL qui n'a rien donné doit pouvoir être retentée au push suivant ;
      // un chemin résolu, lui, reste valable pour la durée du process.
      if (path == null) _logoInflight.remove(url);
      return path;
    }).catchError((Object e) {
      _logoInflight.remove(url);
      debugPrint('WidgetService: logo resolve failed ($url): $e');
      return null;
    });
  }

  static Future<String?> _resolveLogo(String url) async {
    final name = 'widget_logo_${url.hashCode.toRadixString(16)}.png';
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$name');
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
    } catch (e) {
      debugPrint('WidgetService: logo cache probe failed ($url): $e');
    }
    return _downloadIfPresent(url, name);
  }

  /// Download an image to local storage and return the file path.
  static Future<String?> _downloadIfPresent(
    String? url,
    String filename,
  ) async {
    if (url == null || url.isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data != null) {
        await file.writeAsBytes(response.data!);
        return file.path;
      }
    } catch (e) {
      debugPrint('WidgetService: download failed ($url): $e');
    }
    return null;
  }
}
