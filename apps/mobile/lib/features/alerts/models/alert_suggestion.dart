import 'alert_item.dart';

/// Une cible qu'il vaudrait la peine de mettre sous cloche (story 30.6).
///
/// Modèle **à côté** d'[AlertItem], jamais dedans : l'inventaire dit ce qui est
/// posé, la suggestion dit ce qui pourrait l'être. Les mélanger ferait du bloc
/// un second inventaire, ce que le PO reproche déjà à cette zone.
///
/// [reason] n'est pas décorative : c'est elle qui rend la proposition
/// acceptable. Elle est écrite par le serveur, à partir du signal qui a fait
/// sortir la cible, et ne dit que ce que ce signal prouve.
class AlertSuggestion {
  final AlertKind kind;
  final String targetId;
  final String targetName;
  final String? targetLogoUrl;

  /// « Tu as ouvert 8 articles sur 10 de cette source ce mois-ci. »
  final String reason;

  /// Rang de preuve qui a fait sortir la cible (`source_read`,
  /// `topic_affinity`, `source_read_light`, `topic_weight`). Remonté tel quel
  /// dans les événements analytics : sans lui on saurait que le bloc convertit,
  /// mais pas quel rang, donc pas quoi couper.
  final String signal;

  final int articles30d;
  final double cadencePerWeek;

  /// Le devis de bruit, calculé par `alert_cadence.py` — le même module qui
  /// gouverne les envois, donc la phrase ne peut pas diverger de la réalité.
  final String cadencePhrase;

  final bool noisy;

  /// Mode filtré à poser d'emblée (règle 30.3 : une cible bruyante n'arrive
  /// jamais « nue », sinon la cloche devient un robinet au premier tap).
  final bool prefillFiltered;

  const AlertSuggestion({
    required this.kind,
    required this.targetId,
    required this.targetName,
    required this.reason,
    required this.signal,
    this.targetLogoUrl,
    this.articles30d = 0,
    this.cadencePerWeek = 0,
    this.cadencePhrase = '',
    this.noisy = false,
    this.prefillFiltered = false,
  });

  bool get isTopic => kind == AlertKind.topic;

  factory AlertSuggestion.fromJson(Map<String, dynamic> json) {
    return AlertSuggestion(
      kind: json['kind'] == 'topic' ? AlertKind.topic : AlertKind.source,
      targetId: json['target_id'] as String? ?? '',
      targetName: json['target_name'] as String? ?? '',
      targetLogoUrl: json['target_logo_url'] as String?,
      reason: json['reason'] as String? ?? '',
      signal: json['signal'] as String? ?? '',
      articles30d: (json['articles_30d'] as num?)?.toInt() ?? 0,
      cadencePerWeek: (json['cadence_per_week'] as num?)?.toDouble() ?? 0,
      cadencePhrase: json['cadence_phrase'] as String? ?? '',
      noisy: json['noisy'] == true,
      prefillFiltered: json['prefill_filtered'] == true,
    );
  }
}

/// Réponse de `GET /api/alerts/suggestions`.
///
/// [atCap] est la réponse honnête au plafond : le serveur ne propose rien **et
/// le dit**. Proposer un ajout impossible est pire que ne rien proposer.
class AlertSuggestionsState {
  final List<AlertSuggestion> suggestions;
  final int cap;
  final int activeCount;
  final bool atCap;

  const AlertSuggestionsState({
    this.suggestions = const [],
    this.cap = 5,
    this.activeCount = 0,
    this.atCap = false,
  });

  factory AlertSuggestionsState.fromJson(Map<String, dynamic> json) {
    final raw = json['suggestions'];
    return AlertSuggestionsState(
      suggestions: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(AlertSuggestion.fromJson)
              .where((s) => s.targetId.isNotEmpty)
              .toList()
          : const [],
      cap: (json['cap'] as num?)?.toInt() ?? 5,
      activeCount: (json['active_count'] as num?)?.toInt() ?? 0,
      atCap: json['at_cap'] == true,
    );
  }

  AlertSuggestionsState copyWith({
    List<AlertSuggestion>? suggestions,
    int? cap,
    int? activeCount,
    bool? atCap,
  }) {
    return AlertSuggestionsState(
      suggestions: suggestions ?? this.suggestions,
      cap: cap ?? this.cap,
      activeCount: activeCount ?? this.activeCount,
      atCap: atCap ?? this.atCap,
    );
  }

  /// Retrait local d'une ligne, sans aller-retour réseau : une suggestion
  /// acceptée ou refusée doit disparaître au frame suivant.
  ///
  /// Passe par [copyWith] plutôt que de recopier les champs : sinon tout champ
  /// ajouté plus tard à l'état serait silencieusement remis à son défaut ici.
  AlertSuggestionsState without(String targetId) {
    return copyWith(
      suggestions: suggestions.where((s) => s.targetId != targetId).toList(),
    );
  }
}
