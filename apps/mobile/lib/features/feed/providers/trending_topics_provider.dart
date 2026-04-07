import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';

class TrendingTopic {
  final String label;
  final int articleCount;
  final int sourceCount;
  final String? topicSlug;
  final String? theme;

  TrendingTopic({
    required this.label,
    required this.articleCount,
    required this.sourceCount,
    this.topicSlug,
    this.theme,
  });

  factory TrendingTopic.fromJson(Map<String, dynamic> json) {
    return TrendingTopic(
      label: json['label'] as String? ?? '',
      articleCount: json['article_count'] as int? ?? 0,
      sourceCount: json['source_count'] as int? ?? 0,
      topicSlug: json['topic_slug'] as String?,
      theme: json['theme'] as String?,
    );
  }
}

final trendingTopicsProvider =
    FutureProvider<List<TrendingTopic>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (!authState.isAuthenticated) return [];

  final apiClient = ref.watch(apiClientProvider);
  try {
    final response =
        await apiClient.dio.get<List<dynamic>>('feed/trending-topics');
    if (response.statusCode == 200 && response.data != null) {
      return response.data!
          .whereType<Map<String, dynamic>>()
          .map((e) => TrendingTopic.fromJson(e))
          .toList();
    }
  } catch (e) {
    // ignore: avoid_print
    print('TrendingTopicsProvider: [ERROR] $e');
  }
  return [];
});
