import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../models/content_model.dart';

class FeedRepository {
  final ApiClient _apiClient;

  FeedRepository(this._apiClient);

  Future<FeedResponse> getFeed({
    int page = 1,
    int limit = 20,
    String? contentType,
    bool savedOnly = false,
    String? mode,
    String? theme,
    bool hasNote = false,
    String? sourceId,
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

      if (hasNote) {
        queryParams['has_note'] = true;
      }

      if (sourceId != null) {
        queryParams['source_id'] = sourceId;
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
        print('[PERF] feed_repository GET /feed/: ${sw.elapsedMilliseconds}ms, response ~${(responseSize / 1024).toStringAsFixed(1)}KB');

        List<Content> itemsList = [];

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
          final clustersRaw = data['clusters'];
          if (clustersRaw is List) {
            final clusters = <FeedCluster>[];
            for (final c in clustersRaw) {
              try {
                if (c is Map<String, dynamic>) {
                  clusters.add(FeedCluster.fromJson(c));
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
                  return item.copyWith(
                    clusterTopic: cluster.topicSlug,
                    clusterHiddenCount: cluster.hiddenCount,
                    clusterHiddenIds: cluster.hiddenIds,
                  );
                }
                return item;
              }).toList();
            }
          }

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
                if (item.clusterHiddenCount == 0) {
                  itemsList[idx] = item.copyWith(
                    sourceOverflowCount: overflowMap[entry.key]!,
                  );
                }
              }
            }
          }
        } else if (data == null) {
          // Empty response
          itemsList = [];
        }

        // On infère la pagination car le backend ne donne pas de métadonnées
        // Si on a reçu 'limit' items, on suppose qu'il y a une page suivante
        final hasNext = itemsList.length >= limit;

        return FeedResponse(
          items: itemsList,
          pagination: Pagination(
            page: page,
            perPage: limit,
            total: 0, // Inconnu
            hasNext: hasNext,
          ),
        );
      }
      throw Exception('Failed to load feed: ${response.statusCode}');
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] getFeed: $e');
      rethrow;
    }
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
  Future<void> refreshFeed(List<String> contentIds) async {
    try {
      await _apiClient.dio.post<void>(
        'feed/refresh',
        data: {'content_ids': contentIds},
      );
    } catch (e) {
      print('FeedRepository: [ERROR] refreshFeed: $e');
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

  PerspectivesResponse({
    required this.perspectives,
    required this.keywords,
    required this.biasDistribution,
    this.sourceBiasStance = 'unknown',
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
      sourceBiasStance:
          (json['source_bias_stance'] as String?) ?? 'unknown',
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
