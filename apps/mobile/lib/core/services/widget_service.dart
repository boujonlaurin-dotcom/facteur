import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import '../../config/topic_labels.dart';
import '../../features/digest/models/digest_models.dart';
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

/// Service to push the unified Facteur feed (Essentiel + Flux) to the home
/// screen widgets.
///
/// Data flow: Flutter → SharedPreferences (via home_widget) → FacteurWidget.kt
///
/// Schema:
/// - `widget_articles_json` : merged Essentiel-then-Flux payload (deduped by
///   id, capped at [_maxTotal]). Each entry carries `source_kind` so the
///   native side can pick the right deeplink target.
/// - `articles_json` / `feed_articles_json` : per-source caches still written
///   so that a later call with only one side (`updateWidget(digest:)` or
///   `updateWidget(feedItems:)`) can reconstruct the merge without losing the
///   other side after a cold start.
/// - `articles_updated_at` : epoch millis of last successful refresh.
/// - `digest_status` / `digest_progress` / `streak` : legacy keys kept stable.
/// - `widget_flux_max_scroll_position` / `widget_flux_total_count` /
///   `widget_flux_max_scroll_at` : scroll metric written natively, flushed by
///   the app on next foreground.
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

  static const _maxEssentiel = 5;
  static const _maxFeedArticles = 80;

  /// Total cap for the merged payload. Stays at 80 because Flux items are
  /// image-less (cf. widget.5) — Essentiel adds at most 5 thumbnails on top,
  /// still well under the ~1 MB Binder IPC ceiling.
  static const _maxTotal = 80;

  // Mirror of WidgetRendering.SOURCE_KIND_* on the Kotlin side — both must
  // agree for the deeplink router to pick the right reader per row.
  static const _sourceKindEssentiel = 'essentiel';
  static const _sourceKindFlux = 'flux';

  static final _dio = Dio();

  /// Update the home screen widget with the latest digest, feed and/or streak.
  /// Each parameter is independent — passing only one rebuilds that side and
  /// re-merges with the cached other side, then pushes both Light and Dark
  /// widgets.
  static Future<void> updateWidget({
    DigestResponse? digest,
    List<Content>? feedItems,
    StreakModel? streak,
  }) async {
    try {
      if (digest != null) {
        final articles = await _buildEssentielList(digest);
        await HomeWidget.saveWidgetData(
          'articles_json',
          jsonEncode(articles),
        );
        await HomeWidget.saveWidgetData(
          'articles_updated_at',
          '${DateTime.now().millisecondsSinceEpoch}',
        );
        await HomeWidget.saveWidgetData(
          'digest_status',
          _computeStatus(digest),
        );
        await HomeWidget.saveWidgetData(
          'digest_progress',
          _computeProgress(digest),
        );
      }

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

      // Always rebuild the merged payload from whichever per-source caches
      // are currently in SharedPreferences — robust to cold starts where
      // only one of digest/feed is delivered before the widget update.
      if (digest != null || feedItems != null) {
        await _rewriteMergedPayload();
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

      final merged = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final entry in [...fresh, ...cached]) {
        if (merged.length >= _maxFeedArticles) break;
        final id = (entry['id'] as String?) ?? '';
        if (id.isEmpty || !seen.add(id)) continue;
        merged.add({...entry, 'rank': merged.length + 1});
      }

      await HomeWidget.saveWidgetData(
        'feed_articles_json',
        jsonEncode(merged),
      );
      await HomeWidget.saveWidgetData(
        'articles_updated_at',
        '${DateTime.now().millisecondsSinceEpoch}',
      );
      await _rewriteMergedPayload();
      await _pushUpdate();
    } catch (e) {
      debugPrint('WidgetService: updateWidgetMergingFlux failed: $e');
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
      await HomeWidget.saveWidgetData('articles_json', jsonEncode(<dynamic>[]));
      await HomeWidget.saveWidgetData(
        'feed_articles_json',
        jsonEncode(<dynamic>[]),
      );
      await HomeWidget.saveWidgetData(
        'widget_articles_json',
        jsonEncode(<dynamic>[]),
      );
      await HomeWidget.saveWidgetData('digest_status', 'none');
      await _pushUpdate();
    } catch (e) {
      debugPrint('WidgetService: initWidgetIfNeeded failed: $e');
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
      await HomeWidget.saveWidgetData('digest_status', 'none');
      await HomeWidget.saveWidgetData('digest_progress', '0/0');
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
  // Merge — Essentiel-then-Flux, deduped, capped.
  // ──────────────────────────────────────────────────────────────

  /// Combine Essentiel and Flux entries in order, dedup by `id`, cap at the
  /// total ceiling and tag every entry with its `source_kind`. Pure function —
  /// exposed for unit tests.
  @visibleForTesting
  static List<Map<String, dynamic>> mergeForWidget(
    List<Map<String, dynamic>> essentiel,
    List<Map<String, dynamic>> flux,
  ) {
    final result = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (final e in essentiel) {
      final id = (e['id'] as String?) ?? '';
      if (id.isEmpty || seenIds.contains(id)) continue;
      seenIds.add(id);
      result.add({...e, 'source_kind': _sourceKindEssentiel});
      if (result.length >= _maxTotal) return result;
    }
    for (final f in flux) {
      final id = (f['id'] as String?) ?? '';
      if (id.isEmpty || seenIds.contains(id)) continue;
      seenIds.add(id);
      result.add({...f, 'source_kind': _sourceKindFlux});
      if (result.length >= _maxTotal) return result;
    }
    return result;
  }

  static Future<void> _rewriteMergedPayload() async {
    final essentielJson =
        await HomeWidget.getWidgetData<String>('articles_json') ?? '[]';
    final fluxJson =
        await HomeWidget.getWidgetData<String>('feed_articles_json') ?? '[]';
    final essentiel = _decodeList(essentielJson);
    final flux = _decodeList(fluxJson);
    final merged = mergeForWidget(essentiel, flux);
    await HomeWidget.saveWidgetData(
      'widget_articles_json',
      jsonEncode(merged),
    );
    // Diagnostic « le widget n'affiche que 9 articles » : on persiste la
    // profondeur réelle du payload plutôt que de la déduire de l'écran.
    await HomeWidget.saveWidgetData<int>(
      'widget_last_push_count',
      merged.length,
    );
    debugPrint('WidgetService: pushed ${merged.length} rows to widget');
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
  // Essentiel serialization
  // ──────────────────────────────────────────────────────────────

  /// Build the list of widget articles (max 5) from a digest response.
  ///
  /// Strategy mirrors `topic_section.dart` `_pickSingleton`:
  ///  - Iterate topics in rank order, take 1 article per topic
  ///  - Prefer a followed-source article when available
  ///  - Topic 1 article gets `is_main = true` (drives "À la Une" badge)
  static Future<List<Map<String, dynamic>>> _buildEssentielList(
    DigestResponse? digest,
  ) async {
    if (digest == null || digest.topics.isEmpty) return const [];

    final picks = <({DigestItem article, DigestTopic topic, int rank})>[];
    var rank = 1;
    for (final topic in digest.topics) {
      if (picks.length >= _maxEssentiel) break;
      if (topic.articles.isEmpty) continue;
      final article = _pickSingleton(topic);
      if (article.isDismissed) continue;
      picks.add((article: article, topic: topic, rank: rank));
      rank++;
    }
    return Future.wait([
      for (final p in picks)
        _serializeArticle(
          article: p.article,
          topic: p.topic,
          rank: p.rank,
          isMain: p.rank == 1,
        ),
    ]);
  }

  static DigestItem _pickSingleton(DigestTopic topic) {
    for (final a in topic.articles) {
      if (a.isFollowedSource) return a;
    }
    return topic.articles.first;
  }

  static Future<Map<String, dynamic>> _serializeArticle({
    required DigestItem article,
    required DigestTopic topic,
    required int rank,
    required bool isMain,
  }) async {
    final thumbPath = await _downloadIfPresent(
      article.thumbnailUrl,
      'widget_thumbnail_$rank.jpg',
    );
    final logoPath = await _cachedLogo(article.source?.logoUrl);

    return {
      'id': article.contentId,
      'rank': rank,
      'topic_id': topic.topicId,
      'topic_label': topic.label,
      'is_main': isMain,
      'title': article.title,
      'source_name': article.source?.name ?? '',
      'source_logo_path': logoPath ?? '',
      'thumbnail_path': thumbPath ?? '',
      'perspective_count': topic.perspectiveCount,
      'published_at_iso': article.publishedAt?.toUtc().toIso8601String() ?? '',
    };
  }

  // ──────────────────────────────────────────────────────────────
  // Flux serialization
  // ──────────────────────────────────────────────────────────────

  /// Build the Flux article list (max 80) from the current feed state.
  /// Thumbnails are off in Flux (cf. widget.5) — only the source logo (much
  /// smaller) is still inlined.
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
      'is_main': false,
      'title': item.title,
      'source_name': item.source.name,
      'source_logo_path': logoPath ?? '',
      'thumbnail_path': '',
      'perspective_count': 0,
      'published_at_iso': item.publishedAt.toUtc().toIso8601String(),
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

  // ──────────────────────────────────────────────────────────────
  // Status helpers (kept stable for backward-compat header)
  // ──────────────────────────────────────────────────────────────

  static String _computeStatus(DigestResponse? digest) {
    if (digest == null) return 'none';
    if (digest.isCompleted) return 'completed';
    final processed = _processedArticleCount(digest);
    if (processed > 0) return 'in_progress';
    return 'available';
  }

  static String _computeProgress(DigestResponse? digest) {
    if (digest == null) return '0/0';
    final total = _totalArticleCount(digest);
    final processed = _processedArticleCount(digest);
    return '$processed/$total';
  }

  static int _totalArticleCount(DigestResponse digest) {
    if (digest.usesTopics) {
      var count = digest.topics.length;
      if (digest.usesEditorial) {
        if (digest.pepite != null) count++;
        if (digest.coupDeCoeur != null) count++;
      }
      return count;
    }
    return digest.items.length;
  }

  static int _processedArticleCount(DigestResponse digest) {
    if (digest.usesTopics) {
      var count = digest.topics.where((t) => t.isCovered).length;
      if (digest.usesEditorial) {
        final p = digest.pepite;
        if (p != null && (p.isRead || p.isSaved || p.isDismissed)) count++;
        final c = digest.coupDeCoeur;
        if (c != null && (c.isRead || c.isSaved || c.isDismissed)) count++;
      }
      return count;
    }
    return digest.items
        .where((i) => i.isRead || i.isDismissed || i.isSaved)
        .length;
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
