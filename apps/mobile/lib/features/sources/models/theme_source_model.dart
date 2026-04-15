import 'source_model.dart';

class FollowedTheme {
  final String slug;
  final String name;

  const FollowedTheme({required this.slug, required this.name});

  factory FollowedTheme.fromJson(Map<String, dynamic> json) {
    return FollowedTheme(
      slug: json['slug'] as String,
      name: json['name'] as String,
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
    return ThemeSourcesResponse(
      curated: _parseSourceList(json['curated']),
      candidates: _parseSourceList(json['candidates']),
      community: _parseSourceList(json['community']),
    );
  }

  static List<Source> _parseSourceList(dynamic data) {
    if (data == null) return [];
    return (data as List)
        .map((json) => Source.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  bool get isEmpty => curated.isEmpty && candidates.isEmpty && community.isEmpty;
}
