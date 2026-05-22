/// Story 22.1 — état 4-états appliqué aux Sources.
///
/// Aligné sur `packages/api/app/schemas/user_interests.py::UserSourcesStateResponse`.
library;

import 'user_interests_state.dart' show InterestState;

/// Une Source dans l'état utilisateur (état + multiplier ML).
class SourceInterest {
  final String sourceId;
  final InterestState state;
  final double priorityMultiplier;

  const SourceInterest({
    required this.sourceId,
    required this.state,
    required this.priorityMultiplier,
  });

  factory SourceInterest.fromJson(Map<String, dynamic> json) {
    return SourceInterest(
      sourceId: json['source_id'] as String,
      state: InterestState.fromJson(json['state'] as String),
      priorityMultiplier: (json['priority_multiplier'] as num).toDouble(),
    );
  }

  SourceInterest copyWith({
    InterestState? state,
    double? priorityMultiplier,
  }) =>
      SourceInterest(
        sourceId: sourceId,
        state: state ?? this.state,
        priorityMultiplier: priorityMultiplier ?? this.priorityMultiplier,
      );
}

/// Une source favorite : un UUID + sa position canonique (0..2).
class SourceFavoriteRef {
  final String sourceId;
  final int position;

  const SourceFavoriteRef({required this.sourceId, required this.position});

  factory SourceFavoriteRef.fromJson(Map<String, dynamic> json) {
    return SourceFavoriteRef(
      sourceId: json['source_id'] as String,
      position: json['position'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'position': position,
      };

  @override
  bool operator ==(Object other) =>
      other is SourceFavoriteRef && other.sourceId == sourceId;

  @override
  int get hashCode => sourceId.hashCode;
}

class UserSourcesState {
  final List<SourceInterest> sources;
  final List<SourceFavoriteRef> favorites;
  final int favoriteCount;
  final int favoriteCap;

  const UserSourcesState({
    required this.sources,
    required this.favorites,
    required this.favoriteCount,
    required this.favoriteCap,
  });

  factory UserSourcesState.fromJson(Map<String, dynamic> json) {
    return UserSourcesState(
      sources: (json['sources'] as List<dynamic>)
          .map((e) => SourceInterest.fromJson(e as Map<String, dynamic>))
          .toList(),
      favorites: (json['favorites'] as List<dynamic>)
          .map((e) => SourceFavoriteRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      favoriteCount: json['favorite_count'] as int,
      favoriteCap: json['favorite_cap'] as int,
    );
  }

  UserSourcesState copyWith({
    List<SourceInterest>? sources,
    List<SourceFavoriteRef>? favorites,
    int? favoriteCount,
  }) =>
      UserSourcesState(
        sources: sources ?? this.sources,
        favorites: favorites ?? this.favorites,
        favoriteCount: favoriteCount ?? this.favoriteCount,
        favoriteCap: favoriteCap,
      );

  InterestState stateOf(String sourceId) {
    return sources
            .where((s) => s.sourceId == sourceId)
            .map((s) => s.state)
            .firstOrNull ??
        InterestState.unfollowed;
  }

}
