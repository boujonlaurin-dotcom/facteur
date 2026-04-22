import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../models/content_model.dart';

class FeedRepository {
  final ApiClient _apiClient;

  FeedRepository(this._apiClient);

  /// R5.1 — single-flight + short-window dedupe for the *default* feed
  /// view (`page=1`, no filter, serein off). Two concurrent callers
  /// (typically: preload provider + cache hit silent revalidation) get
  /// the same in-flight `Future`, and a successful response is held for
  /// [_defaultViewDedupeWindow] so a follow-up `_fetchPage(1)` triggered
  /// within that window returns the same payload without a network call.
  ///
  /// Out of scope: filtered/themed/source-scoped fetches, pagination,
  /// and `forceFresh` calls. The pull-to-refresh gesture must always
  /// produce a real network call.
  ///
  /// Static so it survives the throwaway provider rebuilds; no per-user
  /// keying is needed because [ApiClient] is per-session and userId is
  /// implicit in the auth header. Cleared on logout via
  /// [clearDefaultViewCache].
  static Future<({FeedResponse feed, dynamic raw})>? _defaultViewInflight;
  static DateTime? _defaultViewLastFetchAt;
  static ({FeedResponse feed, dynamic raw})? _defaultViewLastResult;
  static const Duration _defaultViewDedupeWindow = Duration(seconds: 5);

  /// Reset the static dedupe state. Call on logout / user switch to avoid
  /// leaking another user's feed across sessions.
  static void clearDefaultViewCache() {
    _defaultViewInflight = null;
    _defaultViewLastFetchAt = null;
    _defaultViewLastResult = null;
  }

  /// Parse the `pagination` block from a `GET /feed` response.
  ///
  /// - Legacy shape (raw `List`): falls back to `hasNext = itemsCount > 0`
  ///   and `total = 0` (unknown).
  /// - New shape (`Map` with `pagination: { has_next, total }`): trusts the
  ///   backend-provided values. `has_next` is computed from
  ///   `total_candidates` (pool pre-diversification) so it remains reliable
  ///   even when clustering / regroupement shrinks the current page.
  ///
  /// Visible for unit testing. The provider layer combines the returned
  /// `hasNext` with `items.isNotEmpty` — see `feed_provider.dart`.
  static Pagination parsePagination({
    required dynamic data,
    required int page,
    required int limit,
    required int itemsCount,
  }) {
    int total = 0;
    bool hasNext = itemsCount > 0;
    if (data is Map<String, dynamic>) {
      final paginationRaw = data['pagination'];
      if (paginationRaw is Map<String, dynamic>) {
        final backendHasNext = paginationRaw['has_next'];
        if (backendHasNext is bool) {
          hasNext = backendHasNext;
        }
        final backendTotal = paginationRaw['total'];
        if (backendTotal is int) {
          total = backendTotal;
        }
      }
    }
    return Pagination(
      page: page,
      perPage: limit,
      total: total,
      hasNext: hasNext,
    );
  }

  Future<FeedResponse> getFeed({
    int page = 1,
    int limit = 20,
    String? contentType,
    bool savedOnly = false,
    String? mode,
    String? theme,
    String? topic,
    bool hasNote = false,
    String? sourceId,
    String? entity,
    String? keyword,
    bool includeUnfollowed = false,
    bool serein = false,
    bool forceFresh = false,
  }) async {
    final result = await getFeedWithRaw(
      page: page,
      limit: limit,
      contentType: contentType,
      savedOnly: savedOnly,
      mode: mode,
      theme: theme,
      topic: topic,
      hasNote: hasNote,
      sourceId: sourceId,
      entity: entity,
      keyword: keyword,
      includeUnfollowed: includeUnfollowed,
      serein: serein,
      forceFresh: forceFresh,
    );
    return result.feed;
  }

  /// Fetch the feed and return both the parsed [FeedResponse] AND the raw
  /// decoded JSON payload (Map/List) so callers that need to cache the
  /// response can persist the exact shape that [parseFeedData] expects.
  ///
  /// Regular UI code should prefer [getFeed] which throws away the raw data.
  ///
  /// `forceFresh` bypasses the R5.1 default-view dedupe (use for explicit
  /// pull-to-refresh).
  Future<({FeedResponse feed, dynamic raw})> getFeedWithRaw({
    int page = 1,
    int limit = 20,
    String? contentType,
    bool savedOnly = false,
    String? mode,
    String? theme,
    String? topic,
    bool hasNote = false,
    String? sourceId,
    String? entity,
    String? keyword,
    bool includeUnfollowed = false,
    bool serein = false,
    bool forceFresh = false,
  }) async {
    // R5.1 — single-flight + dedupe gate for the default view only.
    final bool isDefaultView = page == 1 &&
        limit == 20 &&
        !serein &&
        !savedOnly &&
        !hasNote &&
        contentType == null &&
        mode == null &&
        theme == null &&
        topic == null &&
        sourceId == null &&
        entity == null &&
        keyword == null;
    if (isDefaultView && !forceFresh) {
      final inflight = _defaultViewInflight;
      if (inflight != null) {
        return inflight;
      }
      final lastAt = _defaultViewLastFetchAt;
      final lastResult = _defaultViewLastResult;
      if (lastAt != null &&
          lastResult != null &&
          DateTime.now().difference(lastAt) < _defaultViewDedupeWindow) {
        return lastResult;
      }
      final future = _doFetch(
        page: page,
        limit: limit,
        contentType: contentType,
        savedOnly: savedOnly,
        mode: mode,
        theme: theme,
        topic: topic,
        hasNote: hasNote,
        sourceId: sourceId,
        entity: entity,
        keyword: keyword,
        includeUnfollowed: includeUnfollowed,
        serein: serein,
      );
      _defaultViewInflight = future;
      try {
        final result = await future;
        _defaultViewLastResult = result;
        _defaultViewLastFetchAt = DateTime.now();
        return result;
      } finally {
        // Always clear the in-flight Future, success or failure, so the
        // next call doesn't get stuck on a settled Future and a transient
        // failure doesn't poison subsequent retries.
        if (identical(_defaultViewInflight, future)) {
          _defaultViewInflight = null;
        }
      }
    }
    return _doFetch(
      page: page,
      limit: limit,
      contentType: contentType,
      savedOnly: savedOnly,
      mode: mode,
      theme: theme,
      topic: topic,
      hasNote: hasNote,
      sourceId: sourceId,
      entity: entity,
      keyword: keyword,
      includeUnfollowed: includeUnfollowed,
      serein: serein,
    );
  }

  Future<({FeedResponse feed, dynamic raw})> _doFetch({
    required int page,
    required int limit,
    String? contentType,
    bool savedOnly = false,
    String? mode,
    String? theme,
    String? topic,
    bool hasNote = false,
    String? sourceId,
    String? entity,
    String? keyword,
    bool includeUnfollowed = false,
    bool serein = false,
  }) async {
    try {
      // Le backend renvoie directement une List<dynamic> pour le moment
      // et non une enveloppe { items: [], pagination: {} }
      final offset = (page - 1) * limit;

      final queryParams = <String, dynamic>{
        'limit': limit,
        'offset': offset,
      };

      if (contentType != null) {
        queryParams['type'] = contentType;
      }

      if (savedOnly) {
        queryParams['saved'] = true;
      }

      if (mode != null) {
        queryParams['mode'] = mode;
      }

      if (theme != null) {
        queryParams['theme'] = theme;
      }

      if (topic != null) {
        queryParams['topic'] = topic;
      }

      if (hasNote) {
        queryParams['has_note'] = true;
      }

      if (sourceId != null) {
        queryParams['source_id'] = sourceId;
      }

      if (entity != null) {
        queryParams['entity'] = entity;
      }

      if (keyword != null) {
        queryParams['keyword'] = keyword;
      }

      if (includeUnfollowed) {
        queryParams['include_unfollowed'] = true;
      }

      if (serein) {
        queryParams['serein'] = true;
      }

      final sw = Stopwatch()..start();
      final response = await _apiClient.dio.get<dynamic>(
        'feed/', // Trailing slash to avoid 307 redirect which strips auth header
        queryParameters: queryParams,
      );
      sw.stop();

      if (response.statusCode == 200) {
        final data = response.data;
        final responseSize = response.data.toString().length;
        print(
            '[PERF] feed_repository GET /feed/: ${sw.elapsedMilliseconds}ms, response ~${(responseSize / 1024).toStringAsFixed(1)}KB');

        final parsed = parseFeedData(data: data, page: page, limit: limit);
        return (feed: parsed, raw: data);
      }
      throw Exception('Failed to load feed: ${response.statusCode}');
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] getFeed: $e');
      rethrow;
    }
  }

  /// Parse a raw `/feed/` response payload into a [FeedResponse].
  ///
  /// Extracted from [getFeed] so the same parsing path can be reused for
  /// cached payloads restored from [FeedCacheService]. Visible for testing.
  static FeedResponse parseFeedData({
    required dynamic data,
    required int page,
    required int limit,
  }) {
    List<Content> itemsList = [];
    final List<FeedCarouselData> carousels = [];

    // Robustness: Handle both List (Legacy/Prod) and Map (New Backend) responses
    if (data is List) {
          // Legacy format (List returned directly)
          for (final e in data) {
            try {
              if (e is Map<String, dynamic>) {
                itemsList.add(Content.fromJson(e));
              }
            } catch (err) {
              print('FeedRepository: Skipping corrupt item in List: $err');
            }
          }
        } else if (data is Map<String, dynamic>) {
          // New format (FeedResponse object)
          final itemsRaw = data['items'];
          if (itemsRaw is List) {
            for (final e in itemsRaw) {
              try {
                if (e is Map<String, dynamic>) {
                  itemsList.add(Content.fromJson(e));
                }
              } catch (err) {
                print('FeedRepository: Skipping corrupt item in items: $err');
              }
            }
          }

          // Note: briefing is no longer parsed - digest moved to dedicated tab
          // The briefing field in response is ignored

          // Epic 11: Parse clusters if present
          // DEADCODE: Feature "X autres articles" masquée.
          /*
          final clustersRaw = data['clusters'];
          if (clustersRaw is List) {
            final clusters = <FeedCluster>[];
            for (final c in clustersRaw) {
              try {
                if (c is Map<String, dynamic>) {
                  final cluster = FeedCluster.fromJson(c);
                  print(
                      '[DEBUG] Cluster "${cluster.topicSlug}": sources=${cluster.sources.length}, raw_sources=${(c['sources'] as List?)?.length ?? 0}');
                  clusters.add(cluster);
                }
              } catch (err) {
                print('FeedRepository: Skipping corrupt cluster: $err');
              }
            }

            // Annotate representative items with cluster metadata
            if (clusters.isNotEmpty) {
              final clusterMap = <String, FeedCluster>{};
              for (final cluster in clusters) {
                clusterMap[cluster.representativeId] = cluster;
              }

              itemsList = itemsList.map((item) {
                final cluster = clusterMap[item.id];
                if (cluster != null) {
                  // Fallback: if backend sends empty sources, use article's own source
                  final sources = cluster.sources.isNotEmpty
                      ? cluster.sources
                      : [
                          KeywordOverflowSource(
                            sourceId: item.source.id,
                            sourceName: item.source.name,
                            sourceLogoUrl: item.source.logoUrl,
                            articleCount: 1,
                          )
                        ];
                  return item.copyWith(
                    clusterTopic: cluster.topicSlug,
                    clusterHiddenCount: cluster.hiddenCount,
                    clusterHiddenIds: cluster.hiddenIds,
                    clusterSources: sources,
                  );
                }
                return item;
              }).toList();
            }
          }
          */

          // Epic 12: Parse source_overflow and annotate last card per source
          final overflowRaw = data['source_overflow'];
          if (overflowRaw is List) {
            final overflowMap = <String, int>{};
            for (final o in overflowRaw) {
              if (o is Map<String, dynamic>) {
                final sid = o['source_id'] as String?;
                final count = o['hidden_count'] as int?;
                if (sid != null && count != null && count > 0) {
                  overflowMap[sid] = count;
                }
              }
            }

            if (overflowMap.isNotEmpty) {
              // Find the LAST card per source and annotate with overflow count
              // (only if no cluster chip already present — cluster takes priority)
              final lastIndexBySource = <String, int>{};
              for (var i = 0; i < itemsList.length; i++) {
                final sid = itemsList[i].source.id;
                if (overflowMap.containsKey(sid)) {
                  lastIndexBySource[sid] = i;
                }
              }

              for (final entry in lastIndexBySource.entries) {
                final idx = entry.value;
                final item = itemsList[idx];
                // Don't annotate if cluster chip already present
                // if (item.clusterHiddenCount == 0) {
                  itemsList[idx] = item.copyWith(
                    sourceOverflowCount: overflowMap[entry.key]!,
                  );
                // }
              }
            }
          }
          // Topic overflow from topic-aware regroupement (Phase 2)
          final topicOverflowRaw = data['topic_overflow'];
          if (topicOverflowRaw is List) {
            final topicOverflows = <TopicOverflow>[];
            for (final t in topicOverflowRaw) {
              try {
                if (t is Map<String, dynamic>) {
                  final tof = TopicOverflow.fromJson(t);
                  print(
                      '[DEBUG] TopicOverflow "${tof.groupLabel}": sources=${tof.sources.length}, raw_sources=${(t['sources'] as List?)?.length ?? 0}');
                  topicOverflows.add(tof);
                }
              } catch (err) {
                print('FeedRepository: Skipping corrupt topic_overflow: $err');
              }
            }

            if (topicOverflows.isNotEmpty) {
              // For each topic overflow group, find the last article matching
              // that group and annotate it with overflow metadata.
              // Priority: cluster > topic_overflow > source_overflow
              for (final overflow in topicOverflows) {
                int? lastMatchIdx;
                for (var i = 0; i < itemsList.length; i++) {
                  final item = itemsList[i];
                  bool matches = false;
                  if (overflow.groupType == 'topic') {
                    matches = item.topics
                        .any((t) => t.toLowerCase() == overflow.groupKey);
                  } else {
                    // theme match via source.theme
                    matches = (item.source.theme?.toLowerCase() ?? '') ==
                        overflow.groupKey;
                  }
                  if (matches) {
                    lastMatchIdx = i;
                  }
                }

                if (lastMatchIdx != null) {
                  final item = itemsList[lastMatchIdx];
                  // Don't overwrite cluster chip (highest priority)
                  // if (item.clusterHiddenCount == 0) {
                    // Fallback: if backend sends empty sources, use article's own source
                    final sources = overflow.sources.isNotEmpty
                        ? overflow.sources
                        : [
                            KeywordOverflowSource(
                              sourceId: item.source.id,
                              sourceName: item.source.name,
                              sourceLogoUrl: item.source.logoUrl,
                              articleCount: 1,
                            )
                          ];
                    itemsList[lastMatchIdx] = item.copyWith(
                      topicOverflowCount: overflow.hiddenCount,
                      topicOverflowLabel: overflow.groupLabel,
                      topicOverflowKey: overflow.groupKey,
                      topicOverflowType: overflow.groupType,
                      topicOverflowHiddenIds: overflow.hiddenIds,
                      topicOverflowSources: sources,
                    );
                  // }
                }
              }
            }
          }
          // Entity overflow from entity regroupement
          final entityOverflowRaw = data['entity_overflow'];
          if (entityOverflowRaw is List) {
            final entityOverflows = <EntityOverflow>[];
            for (final e in entityOverflowRaw) {
              try {
                if (e is Map<String, dynamic>) {
                  entityOverflows.add(EntityOverflow.fromJson(e));
                }
              } catch (err) {
                print('FeedRepository: Skipping corrupt entity_overflow: $err');
              }
            }

            if (entityOverflows.isNotEmpty) {
              // For each entity overflow group, find the last article whose
              // entities contain the entity name and annotate it.
              // Priority: cluster > entity_overflow > keyword_overflow > topic_overflow > source_overflow
              for (final overflow in entityOverflows) {
                final entityLower = overflow.entityName.toLowerCase();
                int? lastMatchIdx;
                for (var i = 0; i < itemsList.length; i++) {
                  final item = itemsList[i];
                  final matches = item.entities.any(
                    (e) => e.text.toLowerCase() == entityLower,
                  );
                  if (matches) {
                    lastMatchIdx = i;
                  }
                }

                if (lastMatchIdx != null) {
                  final item = itemsList[lastMatchIdx];
                  // Don't overwrite cluster chip (highest priority)
                  // if (item.clusterHiddenCount == 0) {
                    final sources = overflow.sources.isNotEmpty
                        ? overflow.sources
                        : [
                            KeywordOverflowSource(
                              sourceId: item.source.id,
                              sourceName: item.source.name,
                              sourceLogoUrl: item.source.logoUrl,
                              articleCount: 1,
                            )
                          ];
                    itemsList[lastMatchIdx] = item.copyWith(
                      entityOverflowCount: overflow.hiddenCount,
                      entityOverflowLabel: overflow.displayLabel,
                      entityOverflowKey: overflow.entityName,
                      entityOverflowHiddenIds: overflow.hiddenIds,
                      entityOverflowSources: sources,
                    );
                  // }
                }
              }
            }
          }
          // Keyword overflow from keyword mining regroupement
          final keywordOverflowRaw = data['keyword_overflow'];
          if (keywordOverflowRaw is List) {
            final keywordOverflows = <KeywordOverflow>[];
            for (final k in keywordOverflowRaw) {
              try {
                if (k is Map<String, dynamic>) {
                  keywordOverflows.add(KeywordOverflow.fromJson(k));
                }
              } catch (err) {
                print(
                    'FeedRepository: Skipping corrupt keyword_overflow: $err');
              }
            }

            if (keywordOverflows.isNotEmpty) {
              // For each keyword overflow group, find the last article whose
              // title contains the keyword and annotate it.
              // Priority: cluster > keyword_overflow > topic_overflow > source_overflow
              for (final overflow in keywordOverflows) {
                int? lastMatchIdx;
                final kwLower = overflow.filterKeyword.toLowerCase();
                for (var i = 0; i < itemsList.length; i++) {
                  if (itemsList[i].title.toLowerCase().contains(kwLower)) {
                    lastMatchIdx = i;
                  }
                }

                if (lastMatchIdx != null) {
                  final item = itemsList[lastMatchIdx];
                  // Don't overwrite cluster chip (highest priority)
                  // if (item.clusterHiddenCount == 0) {
                    final sources = overflow.sources.isNotEmpty
                        ? overflow.sources
                        : [
                            KeywordOverflowSource(
                              sourceId: item.source.id,
                              sourceName: item.source.name,
                              sourceLogoUrl: item.source.logoUrl,
                              articleCount: 1,
                            )
                          ];
                    itemsList[lastMatchIdx] = item.copyWith(
                      keywordOverflowCount: overflow.hiddenCount,
                      keywordOverflowLabel: overflow.displayLabel,
                      keywordOverflowKey: overflow.filterKeyword,
                      keywordOverflowHiddenIds: overflow.hiddenIds,
                      keywordOverflowSources: sources,
                      keywordOverflowIsCustomTopic: overflow.isCustomTopic,
                    );
                  // }
                }
              }
            }
          }
          // Carousels from overflow group promotion
          final carouselsRaw = data['carousels'];
          if (carouselsRaw is List) {
            for (final c in carouselsRaw) {
              try {
                if (c is Map<String, dynamic>) {
                  carousels.add(FeedCarouselData.fromJson(c));
                }
              } catch (err) {
                print('FeedRepository: Skipping corrupt carousel: $err');
              }
            }
            if (carousels.isNotEmpty) {
              print(
                  '[DEBUG] FeedRepository: ${carousels.length} carousels parsed');
            }
          }
        } else if (data == null) {
          // Empty response
          itemsList = [];
        }

        // Pagination: parsePagination handles both the legacy List shape
        // (fallback: hasNext = itemsCount > 0) and the new Map shape with a
        // `pagination` block emitted by the backend. The provider combines
        // this with `items.isNotEmpty` via a hybrid check — see
        // feed_provider.dart.
        final pagination = FeedRepository.parsePagination(
          data: data,
          page: page,
          limit: limit,
          itemsCount: itemsList.length,
        );

    return FeedResponse(
      items: itemsList,
      pagination: pagination,
      carousels: carousels,
    );
  }

  /// @deprecated Briefing has moved to the dedicated Digest tab.
  /// Use digest repository's applyAction with read status instead.
  @Deprecated('Briefing moved to Digest tab. Use digest repository instead.')
  Future<void> markBriefingAsRead(String contentId) async {
    await _apiClient.dio.post('feed/briefing/$contentId/read');
  }

  Future<Content?> getContent(String contentId) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'contents/$contentId',
      );

      if (response.statusCode == 200 && response.data != null) {
        return Content.fromJson(response.data!);
      }
      return null;
    } catch (e) {
      print('FeedRepository: [ERROR] getContent: $e');
      return null;
    }
  }

  Future<void> toggleSave(String contentId, bool isSaved) async {
    try {
      if (isSaved) {
        await _apiClient.dio.post<void>('contents/$contentId/save');
      } else {
        await _apiClient.dio.delete<void>('contents/$contentId/save');
      }
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] toggleSave: $e');
      rethrow;
    }
  }

  Future<void> toggleLike(String contentId, bool isLiked) async {
    try {
      if (isLiked) {
        await _apiClient.dio.post<void>('contents/$contentId/like');
      } else {
        await _apiClient.dio.delete<void>('contents/$contentId/like');
      }
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] toggleLike: $e');
      rethrow;
    }
  }

  Future<void> upsertNote(String contentId, String noteText) async {
    try {
      await _apiClient.dio.put<void>(
        'contents/$contentId/note',
        data: {'note_text': noteText},
      );
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] upsertNote: $e');
      rethrow;
    }
  }

  Future<void> deleteNote(String contentId) async {
    try {
      await _apiClient.dio.delete<void>('contents/$contentId/note');
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] deleteNote: $e');
      rethrow;
    }
  }

  Future<void> hideContent(String contentId, [HiddenReason? reason]) async {
    try {
      await _apiClient.dio.post<void>(
        'contents/$contentId/hide',
        data: reason != null ? {'reason': reason.name} : <String, dynamic>{},
      );
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] hideContent: $e');
      rethrow;
    }
  }

  Future<void> unhideContent(String contentId) async {
    try {
      await _apiClient.dio.delete<void>('contents/$contentId/hide');
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] unhideContent: $e');
      rethrow;
    }
  }

  /// Refresh feed: mark visible articles as "already shown" for scoring penalty.
  ///
  /// Retourne la liste des backups `PreviousImpression` (valeurs précédentes
  /// de `last_impressed_at`) pour permettre un undo via [undoRefresh].
  Future<List<PreviousImpression>> refreshFeed(List<String> contentIds) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        'feed/refresh',
        data: {'content_ids': contentIds},
      );
      final data = response.data;
      if (data == null) return const [];
      final rawList = data['previous_impressions'] as List<dynamic>? ?? [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(PreviousImpression.fromJson)
          .toList();
    } catch (e) {
      print('FeedRepository: [ERROR] refreshFeed: $e');
      rethrow;
    }
  }

  /// Undo un refresh précédent : restaure les `last_impressed_at` stockés
  /// dans le backup retourné par [refreshFeed].
  Future<void> undoRefresh(List<PreviousImpression> backups) async {
    if (backups.isEmpty) return;
    try {
      await _apiClient.dio.post<void>(
        'feed/refresh/undo',
        data: {
          'previous_impressions': backups.map((b) => b.toJson()).toList(),
        },
      );
    } catch (e) {
      print('FeedRepository: [ERROR] undoRefresh: $e');
      rethrow;
    }
  }

  /// Mark a single article as "already seen" — permanent strong penalty.
  Future<void> impressContent(String contentId) async {
    try {
      await _apiClient.dio.post<void>('contents/$contentId/impress');
    } catch (e) {
      print('FeedRepository: [ERROR] impressContent: $e');
      rethrow;
    }
  }

  /// Analyze perspectives divergences via LLM
  Future<String?> analyzePerspectives(String contentId) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        'contents/$contentId/perspectives/analyze',
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data!['analysis'] as String?;
      }
      return null;
    } catch (e) {
      print('FeedRepository: [ERROR] analyzePerspectives: $e');
      return null;
    }
  }

  /// Report an article as not serene (misclassified)
  Future<void> reportNotSerene(String contentId) async {
    await _apiClient.dio.post<void>('contents/$contentId/report-not-serene');
  }

  /// Fire-and-forget: persist reading progress on article close.
  Future<void> updateContentStatusWithProgress(
      String contentId, int readingProgress) async {
    try {
      await _apiClient.dio.post<void>(
        'contents/$contentId/status',
        data: {'reading_progress': readingProgress},
      );
    } catch (e) {
      print('FeedRepository: [ERROR] updateContentStatusWithProgress: $e');
    }
  }

  Future<void> updateContentStatus(
      String contentId, ContentStatus status) async {
    try {
      await _apiClient.dio.post<void>(
        'contents/$contentId/status',
        data: {'status': status.name},
      );
    } catch (e) {
      // ignore: avoid_print
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔴 FEED REPOSITORY ERROR: updateContentStatus');
      print('ID: $contentId');
      if (e is DioException) {
        print('STATUS: ${e.response?.statusCode}');
        print('DATA: ${e.response?.data}');
        print('MESSAGE: ${e.message}');
      } else {
        print('EXCEPTION: $e');
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      // No rethrow for tracking calls to avoid disrupting UX
    }
  }

  /// Fetch perspectives for a content via Google News search
  Future<PerspectivesResponse> getPerspectives(String contentId) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'contents/$contentId/perspectives',
      );

      if (response.statusCode == 200 && response.data != null) {
        return PerspectivesResponse.fromJson(response.data!);
      }
      throw Exception('Failed to load perspectives: ${response.statusCode}');
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] getPerspectives: $e');
      // Return empty response instead of throwing to not break UX
      return PerspectivesResponse(
          perspectives: [], keywords: [], biasDistribution: {});
    }
  }
}

/// Response from perspectives API
class PerspectivesResponse {
  final List<PerspectiveData> perspectives;
  final List<String> keywords;
  final Map<String, int> biasDistribution;
  final String sourceBiasStance;
  final String comparisonQuality;
  // Backend gate: false → masquer le CTA Comparaison (pas assez d'angles
  // distincts pour comparer). Voir docs/bugs/bug-comparison-clustering-too-loose.md
  final bool shouldDisplay;
  final String? analysis;
  final bool analysisCached;

  PerspectivesResponse({
    required this.perspectives,
    required this.keywords,
    required this.biasDistribution,
    this.sourceBiasStance = 'unknown',
    this.comparisonQuality = 'low',
    this.shouldDisplay = false,
    this.analysis,
    this.analysisCached = false,
  });

  factory PerspectivesResponse.fromJson(Map<String, dynamic> json) {
    final perspectivesList = (json['perspectives'] as List<dynamic>?)
            ?.map((e) => PerspectiveData.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final keywordsList = (json['keywords'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final biasMap = <String, int>{};
    final rawBias = json['bias_distribution'] as Map<String, dynamic>?;
    if (rawBias != null) {
      rawBias.forEach((key, value) {
        biasMap[key] = (value as num?)?.toInt() ?? 0;
      });
    }

    return PerspectivesResponse(
      perspectives: perspectivesList,
      keywords: keywordsList,
      biasDistribution: biasMap,
      sourceBiasStance: (json['source_bias_stance'] as String?) ?? 'unknown',
      comparisonQuality: (json['comparison_quality'] as String?) ?? 'low',
      shouldDisplay: (json['should_display'] as bool?) ?? false,
      analysis: json['analysis'] as String?,
      analysisCached: (json['analysis_cached'] as bool?) ?? false,
    );
  }
}

/// Individual perspective data
class PerspectiveData {
  final String title;
  final String url;
  final String sourceName;
  final String sourceDomain;
  final String biasStance;
  final String? publishedAt;

  PerspectiveData({
    required this.title,
    required this.url,
    required this.sourceName,
    required this.sourceDomain,
    required this.biasStance,
    this.publishedAt,
  });

  factory PerspectiveData.fromJson(Map<String, dynamic> json) {
    return PerspectiveData(
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      sourceName: (json['source_name'] as String?) ?? 'Unknown',
      sourceDomain: (json['source_domain'] as String?) ?? '',
      biasStance: (json['bias_stance'] as String?) ?? 'unknown',
      publishedAt: json['published_at'] as String?,
    );
  }
}
