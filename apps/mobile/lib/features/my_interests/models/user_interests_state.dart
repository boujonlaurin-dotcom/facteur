/// Story 22.1 — système d'intérêts unifié 4-états.
///
/// Modèles Dart alignés sur `packages/api/app/schemas/user_interests.py`.
library;

/// État sémantique unique appliqué à Thèmes, Sujets et Sources.
/// Aligné sur `app.models.enums.InterestState`.
enum InterestState {
  hidden,
  unfollowed,
  followed,
  favorite;

  static InterestState fromJson(String raw) {
    return InterestState.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => InterestState.followed,
    );
  }

  String toJson() => name;
}

/// Discrimine un favori : soit un Thème (slug fermé), soit un Sujet personnalisé (UUID).
sealed class FavoriteRef {
  const FavoriteRef();

  String get kind;
  String get targetId;

  factory FavoriteRef.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String;
    final targetId = json['target_id'] as String;
    return switch (kind) {
      'theme' => ThemeFavoriteRef(slug: targetId),
      'custom_topic' => CustomTopicFavoriteRef(id: targetId),
      _ => throw FormatException('Unknown favorite kind: $kind'),
    };
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'target_id': targetId,
      };

  @override
  bool operator ==(Object other) =>
      other is FavoriteRef && other.kind == kind && other.targetId == targetId;

  @override
  int get hashCode => Object.hash(kind, targetId);
}

class ThemeFavoriteRef extends FavoriteRef {
  final String slug;
  const ThemeFavoriteRef({required this.slug});

  @override
  String get kind => 'theme';
  @override
  String get targetId => slug;
}

class CustomTopicFavoriteRef extends FavoriteRef {
  final String id;
  const CustomTopicFavoriteRef({required this.id});

  @override
  String get kind => 'custom_topic';
  @override
  String get targetId => id;
}

/// Un Thème suivi (slug fermé ~9 valeurs).
class ThemeInterest {
  final String interestSlug;
  final double weight;
  final InterestState state;

  const ThemeInterest({
    required this.interestSlug,
    required this.weight,
    required this.state,
  });

  factory ThemeInterest.fromJson(Map<String, dynamic> json) {
    return ThemeInterest(
      interestSlug: json['interest_slug'] as String,
      weight: (json['weight'] as num).toDouble(),
      state: InterestState.fromJson(json['state'] as String),
    );
  }

  ThemeInterest copyWith({
    double? weight,
    InterestState? state,
  }) =>
      ThemeInterest(
        interestSlug: interestSlug,
        weight: weight ?? this.weight,
        state: state ?? this.state,
      );
}

/// Un Sujet personnalisé (custom topic), rattaché à un Thème parent.
class CustomTopicInterest {
  final String id;
  final String topicName;
  final String slugParent;
  final InterestState state;
  final double priorityMultiplier;

  const CustomTopicInterest({
    required this.id,
    required this.topicName,
    required this.slugParent,
    required this.state,
    required this.priorityMultiplier,
  });

  factory CustomTopicInterest.fromJson(Map<String, dynamic> json) {
    return CustomTopicInterest(
      id: json['id'] as String,
      topicName: json['topic_name'] as String,
      slugParent: json['slug_parent'] as String,
      state: InterestState.fromJson(json['state'] as String),
      priorityMultiplier: (json['priority_multiplier'] as num).toDouble(),
    );
  }

  CustomTopicInterest copyWith({
    InterestState? state,
    double? priorityMultiplier,
  }) =>
      CustomTopicInterest(
        id: id,
        topicName: topicName,
        slugParent: slugParent,
        state: state ?? this.state,
        priorityMultiplier: priorityMultiplier ?? this.priorityMultiplier,
      );
}

/// État complet renvoyé par `GET /api/user/interests`.
class UserInterestsState {
  final List<ThemeInterest> themes;
  final List<CustomTopicInterest> customTopics;
  final List<FavoriteRef> favorites;
  final int favoriteCount;
  final int favoriteCap;

  const UserInterestsState({
    required this.themes,
    required this.customTopics,
    required this.favorites,
    required this.favoriteCount,
    required this.favoriteCap,
  });

  factory UserInterestsState.fromJson(Map<String, dynamic> json) {
    return UserInterestsState(
      themes: (json['themes'] as List<dynamic>)
          .map((e) => ThemeInterest.fromJson(e as Map<String, dynamic>))
          .toList(),
      customTopics: (json['custom_topics'] as List<dynamic>)
          .map((e) => CustomTopicInterest.fromJson(e as Map<String, dynamic>))
          .toList(),
      favorites: (json['favorites'] as List<dynamic>)
          .map((e) => FavoriteRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      favoriteCount: json['favorite_count'] as int,
      favoriteCap: json['favorite_cap'] as int,
    );
  }

  UserInterestsState copyWith({
    List<ThemeInterest>? themes,
    List<CustomTopicInterest>? customTopics,
    List<FavoriteRef>? favorites,
    int? favoriteCount,
    int? favoriteCap,
  }) =>
      UserInterestsState(
        themes: themes ?? this.themes,
        customTopics: customTopics ?? this.customTopics,
        favorites: favorites ?? this.favorites,
        favoriteCount: favoriteCount ?? this.favoriteCount,
        favoriteCap: favoriteCap ?? this.favoriteCap,
      );

  /// Etat courant pour une ref donnée — lit themes/customTopics selon le kind.
  InterestState stateOf(FavoriteRef ref) {
    return switch (ref) {
      ThemeFavoriteRef(:final slug) => themes
              .where((t) => t.interestSlug == slug)
              .map((t) => t.state)
              .firstOrNull ??
          InterestState.unfollowed,
      CustomTopicFavoriteRef(:final id) => customTopics
              .where((t) => t.id == id)
              .map((t) => t.state)
              .firstOrNull ??
          InterestState.unfollowed,
    };
  }

}
