/// La cible d'une cloche : une source, ou un sujet suivi.
enum AlertKind { source, topic }

/// Une cloche active, telle que rendue par l'écran « Mes alertes » et par la
/// section Tournée.
///
/// [lastPublishedAt] porte le « silence comme preuve » : c'est lui qui permet
/// d'écrire « Rien de neuf depuis N semaines, et c'est vérifié » plutôt que de
/// laisser l'utilisateur se demander si la cloche marche.
///
/// Les champs restent nommés `source*` pour les deux familles : le serveur
/// expose une liste unique (`source_id`/`source_name` portent l'identité du
/// sujet quand [kind] vaut [AlertKind.topic]), et le client n'a qu'une liste à
/// afficher.
class AlertItem {
  final AlertKind kind;
  final String sourceId;
  final String sourceName;
  final String? sourceLogoUrl;

  /// Mode « seulement les plus marquantes » (1 alerte par jour au plus).
  final bool filtered;
  final int articles30d;
  final double cadencePerWeek;
  final DateTime? lastPublishedAt;
  final DateTime? lastAlertSentAt;

  /// Contenus publiés depuis moins de 24 h et non lus.
  final int newContent;

  const AlertItem({
    this.kind = AlertKind.source,
    required this.sourceId,
    required this.sourceName,
    this.sourceLogoUrl,
    this.filtered = false,
    this.articles30d = 0,
    this.cadencePerWeek = 0,
    this.lastPublishedAt,
    this.lastAlertSentAt,
    this.newContent = 0,
  });

  bool get isTopic => kind == AlertKind.topic;

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      kind: json['kind'] == 'topic' ? AlertKind.topic : AlertKind.source,
      sourceId: json['source_id'] as String,
      sourceName: json['source_name'] as String? ?? '',
      sourceLogoUrl: json['source_logo_url'] as String?,
      filtered: json['filtered'] == true,
      articles30d: (json['articles_30d'] as num?)?.toInt() ?? 0,
      cadencePerWeek: (json['cadence_per_week'] as num?)?.toDouble() ?? 0,
      lastPublishedAt: _parseDate(json['last_published_at']),
      lastAlertSentAt: _parseDate(json['last_alert_sent_at']),
      newContent: (json['new_content'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _parseDate(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}

/// État complet de l'écran « Mes alertes » : les cloches + le plafond, qui
/// vient du serveur pour que l'en-tête « x / 5 » ne puisse pas mentir.
class AlertsState {
  final List<AlertItem> items;
  final int activeCount;
  final int cap;

  const AlertsState({
    this.items = const [],
    this.activeCount = 0,
    this.cap = 5,
  });

  bool get isFull => activeCount >= cap;

  /// Cloches ayant du neuf non lu : ce qui justifie la section dans la Tournée.
  List<AlertItem> get withNewContent =>
      items.where((i) => i.newContent > 0).toList();

  factory AlertsState.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return AlertsState(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(AlertItem.fromJson)
              .toList()
          : const [],
      activeCount: (json['active_count'] as num?)?.toInt() ?? 0,
      cap: (json['cap'] as num?)?.toInt() ?? 5,
    );
  }
}

/// Levée quand le serveur refuse une 6ᵉ cloche (409 `alert_cap_reached`).
class AlertCapReachedException implements Exception {
  final int cap;
  const AlertCapReachedException(this.cap);
}
