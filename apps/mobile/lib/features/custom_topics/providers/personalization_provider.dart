import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';

/// User mute preferences: muted themes, topics, and content types.
class UserPersonalization {
  final Set<String> mutedThemes;
  final Set<String> mutedTopics;
  final Set<String> mutedContentTypes;

  const UserPersonalization({
    this.mutedThemes = const {},
    this.mutedTopics = const {},
    this.mutedContentTypes = const {},
  });

  factory UserPersonalization.fromJson(Map<String, dynamic> json) {
    return UserPersonalization(
      mutedThemes: _toStringSet(json['muted_themes']),
      mutedTopics: _toStringSet(json['muted_topics']),
      mutedContentTypes: _toStringSet(json['muted_content_types']),
    );
  }

  static Set<String> _toStringSet(dynamic raw) {
    if (raw == null) return {};
    return Set<String>.from(
      (raw as List).map((e) => e.toString().toLowerCase()),
    );
  }
}

/// Fetches the user's personalization (mute state) from the backend.
final personalizationProvider =
    FutureProvider<UserPersonalization>((ref) async {
  final client = ref.watch(apiClientProvider);
  final data = await client.get('users/personalization/');
  return UserPersonalization.fromJson(data as Map<String, dynamic>);
});
