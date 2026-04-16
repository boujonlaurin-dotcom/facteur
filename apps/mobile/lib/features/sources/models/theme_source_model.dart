import 'source_model.dart';

class FollowedTheme {
  final String slug;
  final String name;

  const FollowedTheme({required this.slug, required this.name});

  factory FollowedTheme.fromJson(Map<String, dynamic> json) {
    return FollowedTheme(
      slug: json['slug'] as String,
      name: (json['label'] ?? json['name']) as String,
    );
  }
}

class ThemeSourcesResponse {
  final List<Source> curated;
  final List<Source> candidates;
  final List<Source> community;

  const ThemeSourcesResponse({
    required this.curated,
    required this.candidates,
    required this.community,
  });

  factory ThemeSourcesResponse.fromJson(Map<String, dynamic> json) {
    // Backend returns {"groups": [{"label": "Curées", "sources": [...]}, ...]}
    final groups = json['groups'];
    if (groups is List) {
      return ThemeSourcesResponse(
        curated: _extractGroupSources(groups, 'Curées'),
        candidates: _extractGroupSources(groups, 'Candidates'),
        community: _extractGroupSources(groups, 'Communauté'),
      );
    }
    // Fallback for flat format
    return ThemeSourcesResponse(
      curated: _parseSourceList(json['curated']),
      candidates: _parseSourceList(json['candidates']),
      community: _parseSourceList(json['community']),
    );
  }

  static List<Source> _extractGroupSources(List<dynamic> groups, String label) {
    for (final group in groups) {
      if (group is Map<String, dynamic> && group['label'] == label) {
        return _parseSourceList(group['sources']);
      }
    }
    return [];
  }

  static List<Source> _parseSourceList(dynamic data) {
    if (data == null) return [];
    return (data as List)
        .map((json) => Source.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  bool get isEmpty => curated.isEmpty && candidates.isEmpty && community.isEmpty;
}
