import 'package:freezed_annotation/freezed_annotation.dart';

part 'grille_models.freezed.dart';
part 'grille_models.g.dart';

/// Modèles de « La Grille du jour » (mobile, Story 24.2).
///
/// ⚠️ Contrat **byte-exact** avec `packages/api/app/schemas/grille.py` : les
/// noms de champs portent **directement** les clés JSON camelCase FR — aucun
/// `@JsonKey(name:)` de renommage, aucun `field_rename` dans `build.yaml`.
/// `numero` est une **String** (`"N°143"`). Les champs `score`/`monScore`
/// peuvent valoir un entier OU la chaîne `"X"` (raté) côté serveur : on
/// normalise en `String` + getter `int? scoreInt`.

/// Convertit une valeur d'union `int | "X"` en `String` stable.
String _scoreToString(Object? value) => value?.toString() ?? 'X';

/// Une proposition jouée et ses états par case (`place|present|absent`).
@freezed
class GrilleEssai with _$GrilleEssai {
  const factory GrilleEssai({
    required String mot,
    required List<String> etats,
  }) = _GrilleEssai;

  factory GrilleEssai.fromJson(Map<String, dynamic> json) =>
      _$GrilleEssaiFromJson(json);
}

/// Réponse de `GET grille/today`.
///
/// `mot`/`pourquoi` restent `null` tant que `statut == in_progress` (le mot
/// n'est jamais exposé avant la fin de partie).
@freezed
class GrilleTodayResponse with _$GrilleTodayResponse {
  const GrilleTodayResponse._();

  const factory GrilleTodayResponse({
    required String date,
    required String dateAffichee,
    required String dateCourt,
    required String numero,
    required int longueur,
    required int essaisMax,
    required String premiereLettre,
    required String indice,
    required String theme,
    required String statut,
    required List<GrilleEssai> essais,
    required int nbEssais,
    String? mot,
    String? pourquoi,
    required int streak,
    required int prochainMotDansSec,
  }) = _GrilleTodayResponse;

  factory GrilleTodayResponse.fromJson(Map<String, dynamic> json) =>
      _$GrilleTodayResponseFromJson(json);

  bool get isInProgress => statut == 'in_progress';
  bool get isSolved => statut == 'solved';
  bool get isFailed => statut == 'failed';
  bool get isFinished => isSolved || isFailed;
}

/// Réponse de `POST grille/today/guess`.
///
/// En cas de refus (`valide == false`), seul `raison` est renseigné et l'essai
/// **n'est pas consommé**. En cas d'acceptation, `etats`/`statut`/`nbEssais`
/// sont renseignés ; `mot`/`pourquoi` uniquement sur `solved`/`failed`.
@freezed
class GrilleGuessResponse with _$GrilleGuessResponse {
  const GrilleGuessResponse._();

  const factory GrilleGuessResponse({
    required bool valide,
    String? raison,
    List<String>? etats,
    String? statut,
    int? nbEssais,
    String? mot,
    String? pourquoi,
  }) = _GrilleGuessResponse;

  factory GrilleGuessResponse.fromJson(Map<String, dynamic> json) =>
      _$GrilleGuessResponseFromJson(json);

  bool get isSolved => statut == 'solved';
  bool get isFailed => statut == 'failed';
  bool get isFinished => isSolved || isFailed;
}

/// Part (%) des joueurs pour un nombre d'essais donné (`score` ou `"X"`).
@freezed
class GrilleDistributionItem with _$GrilleDistributionItem {
  const GrilleDistributionItem._();

  const factory GrilleDistributionItem({
    @JsonKey(fromJson: _scoreToString) required String score,
    required int pct,
  }) = _GrilleDistributionItem;

  factory GrilleDistributionItem.fromJson(Map<String, dynamic> json) =>
      _$GrilleDistributionItemFromJson(json);

  /// `null` si raté (`"X"`), sinon le nombre d'essais.
  int? get scoreInt => int.tryParse(score);
}

/// Une ligne du podium anonymisé (`moi == true` pour le joueur courant).
@freezed
class GrilleQuartierItem with _$GrilleQuartierItem {
  const GrilleQuartierItem._();

  const factory GrilleQuartierItem({
    required String initiales,
    @JsonKey(fromJson: _scoreToString) required String score,
    required int rang,
    @Default(false) bool moi,
  }) = _GrilleQuartierItem;

  factory GrilleQuartierItem.fromJson(Map<String, dynamic> json) =>
      _$GrilleQuartierItemFromJson(json);

  int? get scoreInt => int.tryParse(score);
}

/// Réponse de `GET grille/today/leaderboard` (partie terminée requise).
@freezed
class GrilleLeaderboardResponse with _$GrilleLeaderboardResponse {
  const GrilleLeaderboardResponse._();

  const factory GrilleLeaderboardResponse({
    required int percentile,
    required int joueurs,
    @JsonKey(fromJson: _scoreToString) required String monScore,
    required List<GrilleDistributionItem> distribution,
    required List<GrilleQuartierItem> quartier,
    required int streak,
  }) = _GrilleLeaderboardResponse;

  factory GrilleLeaderboardResponse.fromJson(Map<String, dynamic> json) =>
      _$GrilleLeaderboardResponseFromJson(json);

  int? get monScoreInt => int.tryParse(monScore);
}
