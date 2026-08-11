import '../../feed/models/content_model.dart';
import '../../sources/models/source_model.dart';

/// La cible d'une cloche : une source, ou un sujet suivi.
enum AlertKind { source, topic }

/// Un contenu déclencheur embarqué dans la cloche (story 30.4).
///
/// Sans lui, la carte de la Tournée ne pouvait annoncer qu'un compteur : elle
/// cachait l'article derrière un rappel, puis le faisait recharger. Les champs
/// [sourceName] / [sourceLogoUrl] décrivent la **source réelle de l'article**,
/// pas la cible de la cloche : une alerte sujet ramène des articles de médias
/// variés, et c'est ce qui la rend lisible.
class AlertContent {
  final String contentId;
  final String title;
  final String? url;
  final String? thumbnailUrl;
  final DateTime? publishedAt;
  final String? contentType;
  final String? sourceId;
  final String sourceName;
  final String? sourceLogoUrl;

  const AlertContent({
    required this.contentId,
    required this.title,
    this.url,
    this.thumbnailUrl,
    this.publishedAt,
    this.contentType,
    this.sourceId,
    this.sourceName = '',
    this.sourceLogoUrl,
  });

  factory AlertContent.fromJson(Map<String, dynamic> json) {
    return AlertContent(
      contentId: json['content_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      url: json['url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      publishedAt: _parseDate(json['published_at']),
      contentType: json['content_type'] as String?,
      sourceId: json['source_id'] as String?,
      sourceName: json['source_name'] as String? ?? '',
      sourceLogoUrl: json['source_logo_url'] as String?,
    );
  }

  /// [Content] partiel passé en `extra` à `ContentDetailScreen`.
  ///
  /// Même contrat que `content_preview_mapper.dart` : le header (titre, source,
  /// image) est peint au 1ᵉʳ frame, le corps montre le shimmer pendant que
  /// `getContent()` complète. C'est ce qui supprime l'écran blanc de 3-4 s.
  Content toPreviewContent() {
    return Content(
      id: contentId,
      title: title,
      url: url ?? '',
      thumbnailUrl: thumbnailUrl,
      contentType: _contentTypeFromString(contentType),
      publishedAt: publishedAt ?? DateTime.now(),
      source: Source(
        id: sourceId ?? '',
        name: sourceName,
        type: SourceType.article,
        logoUrl: sourceLogoUrl,
      ),
    );
  }
}

ContentType _contentTypeFromString(String? value) {
  return ContentType.values.firstWhere(
    (e) => e.name == value?.toLowerCase(),
    orElse: () => ContentType.article,
  );
}

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

  /// Les contenus déclencheurs eux-mêmes (story 30.4), du plus frais au plus
  /// ancien. Vide face à un backend v1 : la carte retombe alors sur la ligne
  /// « nom + N nouveaux ».
  final List<AlertContent> contents;

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
    this.contents = const [],
  });

  bool get isTopic => kind == AlertKind.topic;

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    final rawContents = json['contents'];
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
      contents: rawContents is List
          ? rawContents
              .whereType<Map<String, dynamic>>()
              .map(AlertContent.fromJson)
              .where((c) => c.contentId.isNotEmpty)
              .toList()
          : const [],
    );
  }
}

DateTime? _parseDate(Object? raw) =>
    raw is String ? DateTime.tryParse(raw) : null;

/// Une ligne de la carte « Tes alertes » : la cloche qui a sonné, et le contenu
/// qu'elle annonce ([content] `null` = backend v1, ligne « nom + N nouveaux »).
class AlertRow {
  final AlertItem alert;
  final AlertContent? content;

  const AlertRow({required this.alert, this.content});
}

/// Répartit les contenus des cloches sur les [maxRows] lignes de la carte.
///
/// Tourniquet : 1 article par cloche au premier tour, puis on complète avec les
/// suivants. Diversité quand plusieurs cloches sonnent, profondeur quand une
/// seule sonne — pour une place à l'écran identique dans les deux cas.
///
/// Une cloche sans contenu n'occupe une ligne que si **aucune** n'en a : sinon
/// elle laisserait une ligne fantôme au milieu d'un mini-flux.
List<AlertRow> buildAlertRows(List<AlertItem> alerts, {required int maxRows}) {
  if (maxRows <= 0) return const [];
  final withContent = alerts.where((a) => a.contents.isNotEmpty).toList();
  if (withContent.isEmpty) {
    return alerts
        .take(maxRows)
        .map((a) => AlertRow(alert: a))
        .toList(growable: false);
  }

  final rows = <AlertRow>[];
  final deepest =
      withContent.map((a) => a.contents.length).reduce((a, b) => a > b ? a : b);
  for (var pass = 0; pass < deepest && rows.length < maxRows; pass++) {
    for (final alert in withContent) {
      if (rows.length >= maxRows) break;
      if (pass >= alert.contents.length) continue;
      rows.add(AlertRow(alert: alert, content: alert.contents[pass]));
    }
  }
  return rows;
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
      items.where((i) => i.newContent > 0 || i.contents.isNotEmpty).toList();

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
