/// Modèles Dart pour la feature « Construire ton flux » (Epic 13).
///
/// Convention : parsing manuel via `fromJson`, aligné avec `content_model.dart`.
/// Les champs snake_case de l'API sont convertis en camelCase.

enum ProposalType {
  sourcePriority,
  followEntity,
  muteEntity,
  unknown;

  static ProposalType fromWire(String? raw) {
    switch (raw) {
      case 'source_priority':
        return ProposalType.sourcePriority;
      case 'follow_entity':
        return ProposalType.followEntity;
      case 'mute_entity':
        return ProposalType.muteEntity;
      default:
        return ProposalType.unknown;
    }
  }

  String toWire() {
    switch (this) {
      case ProposalType.sourcePriority:
        return 'source_priority';
      case ProposalType.followEntity:
        return 'follow_entity';
      case ProposalType.muteEntity:
        return 'mute_entity';
      case ProposalType.unknown:
        return 'unknown';
    }
  }
}

enum EntityType {
  source,
  topic,
  unknown;

  static EntityType fromWire(String? raw) {
    switch (raw) {
      case 'source':
        return EntityType.source;
      case 'topic':
        return EntityType.topic;
      default:
        return EntityType.unknown;
    }
  }

  String toWire() {
    switch (this) {
      case EntityType.source:
        return 'source';
      case EntityType.topic:
        return 'topic';
      case EntityType.unknown:
        return 'unknown';
    }
  }
}

enum ProposalStatus {
  pending,
  applied,
  dismissed,
  snoozed,
  unknown;

  static ProposalStatus fromWire(String? raw) {
    switch (raw) {
      case 'pending':
        return ProposalStatus.pending;
      case 'applied':
        return ProposalStatus.applied;
      case 'dismissed':
        return ProposalStatus.dismissed;
      case 'snoozed':
        return ProposalStatus.snoozed;
      default:
        return ProposalStatus.unknown;
    }
  }
}

enum ApplyActionType {
  accept,
  modify,
  dismiss;

  String toWire() {
    switch (this) {
      case ApplyActionType.accept:
        return 'accept';
      case ApplyActionType.modify:
        return 'modify';
      case ApplyActionType.dismiss:
        return 'dismiss';
    }
  }
}

/// Contexte factuel de la proposition — nourrit le panneau stats déplié (ℹ︎).
class SignalContext {
  final int? articlesShown;
  final int? articlesClicked;
  final int? articlesSaved;
  final int? periodDays;

  const SignalContext({
    this.articlesShown,
    this.articlesClicked,
    this.articlesSaved,
    this.periodDays,
  });

  factory SignalContext.fromJson(Map<String, dynamic> json) {
    return SignalContext(
      articlesShown: (json['articles_shown'] as num?)?.toInt(),
      articlesClicked: (json['articles_clicked'] as num?)?.toInt(),
      articlesSaved: (json['articles_saved'] as num?)?.toInt(),
      periodDays: (json['period_days'] as num?)?.toInt(),
    );
  }
}

/// Une proposition d'ajustement du flux.
class LearningProposal {
  final String id;
  final ProposalType proposalType;
  final EntityType entityType;
  final String entityId;
  final String entityLabel;
  final num? currentValue;
  final num? proposedValue;
  final double signalStrength;
  final SignalContext signalContext;
  final int shownCount;
  final ProposalStatus status;

  const LearningProposal({
    required this.id,
    required this.proposalType,
    required this.entityType,
    required this.entityId,
    required this.entityLabel,
    required this.currentValue,
    required this.proposedValue,
    required this.signalStrength,
    required this.signalContext,
    required this.shownCount,
    required this.status,
  });

  factory LearningProposal.fromJson(Map<String, dynamic> json) {
    final signalContextRaw = json['signal_context'];
    return LearningProposal(
      id: (json['id'] as String?) ?? '',
      proposalType: ProposalType.fromWire(json['proposal_type'] as String?),
      entityType: EntityType.fromWire(json['entity_type'] as String?),
      entityId: (json['entity_id'] as String?) ?? '',
      entityLabel: (json['entity_label'] as String?) ?? '',
      currentValue: json['current_value'] as num?,
      proposedValue: json['proposed_value'] as num?,
      signalStrength: (json['signal_strength'] as num?)?.toDouble() ?? 0.0,
      signalContext: signalContextRaw is Map<String, dynamic>
          ? SignalContext.fromJson(signalContextRaw)
          : const SignalContext(),
      shownCount: (json['shown_count'] as num?)?.toInt() ?? 0,
      status: ProposalStatus.fromWire(json['status'] as String?),
    );
  }

  /// Phrase factuelle pour la ligne (cf. spec `13.5-13.6.format-visuel.md`).
  String justificationPhrase() {
    switch (proposalType) {
      case ProposalType.sourcePriority:
        final current = currentValue ?? 0;
        final proposed = proposedValue ?? 0;
        return proposed < current ? 'rarement ouvert' : 'souvent ouvert';
      case ProposalType.muteEntity:
        return 'vue mais ignorée';
      case ProposalType.followEntity:
        return 'suivie de près';
      case ProposalType.unknown:
        return '';
    }
  }
}

/// Une action utilisateur à poster vers `/apply-proposals`.
class ApplyAction {
  final String proposalId;
  final ApplyActionType action;
  final num? value;

  const ApplyAction({
    required this.proposalId,
    required this.action,
    this.value,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'proposal_id': proposalId,
      'action': action.toWire(),
    };
    if (action == ApplyActionType.modify && value != null) {
      m['value'] = value;
    }
    return m;
  }
}

/// Réponse serveur à `/apply-proposals`.
class ApplyProposalsResponse {
  final List<dynamic> updatedPreferences;

  const ApplyProposalsResponse({required this.updatedPreferences});

  factory ApplyProposalsResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['updated_preferences'];
    return ApplyProposalsResponse(
      updatedPreferences: raw is List ? raw : const [],
    );
  }
}
