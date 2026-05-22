/// Story 22.1 — système d'intérêts unifié 4-états.
///
/// Modèles Dart alignés sur `packages/api/app/schemas/user_interests.py`.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

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

/// Rendu visuel canonique d'un [InterestState] (label, icône, couleur d'accent,
/// description longue). Source de vérité unique pour le picker et les pills.
extension InterestStateVisuals on InterestState {
  String get label {
    switch (this) {
      case InterestState.favorite:
        return 'Favori';
      case InterestState.followed:
        return 'Suivi';
      case InterestState.unfollowed:
        return 'Neutre';
      case InterestState.hidden:
        return 'Masqué';
    }
  }

  String get description {
    switch (this) {
      case InterestState.favorite:
        return 'En haut de votre flux. Les 3 premiers sont dans la Tournée du jour.';
      case InterestState.followed:
        return 'Présent dans votre flux';
      case InterestState.unfollowed:
        return 'Apparaît seulement si très pertinent';
      case InterestState.hidden:
        return 'Ne plus voir dans le flux';
    }
  }

  IconData get iconData {
    switch (this) {
      case InterestState.favorite:
        return PhosphorIcons.star(PhosphorIconsStyle.fill);
      case InterestState.followed:
        return PhosphorIcons.check(PhosphorIconsStyle.bold);
      case InterestState.unfollowed:
        return PhosphorIcons.minus(PhosphorIconsStyle.bold);
      case InterestState.hidden:
        return PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular);
    }
  }

  Color accent(FacteurColors colors) {
    switch (this) {
      case InterestState.favorite:
        return colors.primary;
      case InterestState.followed:
        return colors.success;
      case InterestState.unfollowed:
        return colors.textSecondary;
      case InterestState.hidden:
        return colors.textTertiary;
    }
  }
}

/// Discrimine un favori : Thème (slug fermé), Sujet personnalisé (UUID), ou Veille (UUID).
///
/// La veille (Story 23.2 PR-4) devient le 3ᵉ type de favori, traitée
/// uniformément avec theme et custom_topic. Backend a ajouté
/// `veille_config_id` à `user_favorite_interests` (Story 23.1 PR-3, migration vf02).
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
      'veille' => VeilleFavoriteRef(id: targetId),
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

/// Favori veille — référence à `VeilleConfig.id`. Le label visuel et
/// l'accent (`sectionVeille1`) sont résolus à l'affichage via
/// `veilleActiveConfigProvider` — un user n'a qu'une seule veille à V1.
class VeilleFavoriteRef extends FavoriteRef {
  final String id;
  const VeilleFavoriteRef({required this.id});

  @override
  String get kind => 'veille';
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
  /// Une veille favorite est toujours considérée comme `favorite` (cf. PR-3) :
  /// son existence dans `favorites` implique l'état favori.
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
      VeilleFavoriteRef() => InterestState.favorite,
    };
  }

}
