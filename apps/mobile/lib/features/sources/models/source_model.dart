import 'package:flutter/material.dart';

enum SourceType {
  article,
  podcast,
  video,
  youtube,
}

class Source {
  final String id;
  final String name;
  final String? url;
  final SourceType type;
  final String? theme;
  final String? description;
  final String? logoUrl;
  final bool isCurated;
  final bool isCustom;
  final bool isTrusted;
  final bool isMuted;
  final String biasStance;
  final String reliabilityScore;
  final String biasOrigin;
  final double? scoreIndependence;
  final double? scoreRigor;
  final double? scoreUx;
  final int followerCount;

  Source({
    required this.id,
    required this.name,
    this.url,
    required this.type,
    this.theme,
    this.description,
    this.logoUrl,
    this.isCurated = false,
    this.isCustom = false,
    this.isTrusted = false,
    this.isMuted = false,
    this.biasStance = 'unknown',
    this.reliabilityScore = 'unknown',
    this.biasOrigin = 'unknown',
    this.scoreIndependence,
    this.scoreRigor,
    this.scoreUx,
    this.followerCount = 0,
  });

  Source copyWith({
    String? id,
    String? name,
    String? url,
    SourceType? type,
    String? theme,
    String? description,
    String? logoUrl,
    bool? isCurated,
    bool? isCustom,
    bool? isTrusted,
    bool? isMuted,
    String? biasStance,
    String? reliabilityScore,
    String? biasOrigin,
    double? scoreIndependence,
    double? scoreRigor,
    double? scoreUx,
    int? followerCount,
  }) {
    return Source(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      theme: theme ?? this.theme,
      description: description ?? this.description,
      logoUrl: logoUrl ?? this.logoUrl,
      isCurated: isCurated ?? this.isCurated,
      isCustom: isCustom ?? this.isCustom,
      isTrusted: isTrusted ?? this.isTrusted,
      isMuted: isMuted ?? this.isMuted,
      biasStance: biasStance ?? this.biasStance,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      biasOrigin: biasOrigin ?? this.biasOrigin,
      scoreIndependence: scoreIndependence ?? this.scoreIndependence,
      scoreRigor: scoreRigor ?? this.scoreRigor,
      scoreUx: scoreUx ?? this.scoreUx,
      followerCount: followerCount ?? this.followerCount,
    );
  }

  factory Source.fromJson(Map<String, dynamic> json) {
    try {
      return Source(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? 'Unknown Source',
        url: json['url'] as String?,
        type: SourceType.values.firstWhere(
          (e) => e.name == (json['type'] as String?)?.toLowerCase(),
          orElse: () => SourceType.article,
        ),
        theme: json['theme'] as String?,
        description: json['description'] as String?,
        logoUrl: json['logo_url'] as String?,
        isCurated: (json['is_curated'] as bool?) ?? false,
        isCustom: (json['is_custom'] as bool?) ?? false,
        isTrusted: (json['is_trusted'] as bool?) ?? false,
        isMuted: (json['is_muted'] as bool?) ?? false,
        biasStance:
            (json['bias_stance'] as String?)?.toLowerCase() ?? 'unknown',
        reliabilityScore:
            (json['reliability_score'] as String?)?.toLowerCase() ?? 'unknown',
        biasOrigin:
            (json['bias_origin'] as String?)?.toLowerCase() ?? 'unknown',
        scoreIndependence: (json['score_independence'] as num?)?.toDouble(),
        scoreRigor: (json['score_rigor'] as num?)?.toDouble(),
        scoreUx: (json['score_ux'] as num?)?.toDouble(),
        followerCount: (json['follower_count'] as int?) ?? 0,
      );
    } catch (e) {
      debugPrint('Source.fromJson: [ERROR] Failed to parse: $e');
      return Source.fallback();
    }
  }

  /// Factory for a safe fallback source to prevent UI crashes
  factory Source.fallback() {
    return Source(
      id: 'fallback',
      name: 'Source Inconnue',
      type: SourceType.article,
      theme: 'Autre',
    );
  }

  Color getBiasColor() {
    switch (biasStance) {
      case 'left':
        return const Color(0xFFEF5350); // Red 400
      case 'center-left':
        return const Color(0xFFEF9A9A); // Red 200
      case 'center':
        return const Color(0xFF9E9E9E); // Grey 500
      case 'center-right':
        return const Color(0xFF90CAF9); // Blue 200
      case 'right':
        return const Color(0xFF42A5F5); // Blue 400
      default:
        return const Color(0xFFBDBDBD); // Grey 400
    }
  }

  String getBiasLabel() {
    switch (biasStance) {
      case 'left':
        return 'Gauche';
      case 'center-left':
        return 'Centre-G';
      case 'center':
        return 'Centre';
      case 'center-right':
        return 'Centre-D';
      case 'right':
        return 'Droite';
      case 'specialized':
        return 'Spécialisé';
      case 'alternative':
        return 'Alternatif';
      default:
        return 'Neutre';
    }
  }

  Color getReliabilityColor() {
    switch (reliabilityScore) {
      case 'high':
        return const Color(0xFF4CAF50); // green.shade500
      case 'medium':
      case 'mixed':
        return const Color(0xFFFFB74D); // orange.shade300
      case 'low':
        return const Color(0xFFEF5350); // red.shade400
      default:
        return const Color(0xFFBDBDBD); // grey.shade400
    }
  }

  String getReliabilityLabel() {
    switch (reliabilityScore) {
      case 'high':
        return 'Fiabilité Élevée';
      case 'medium':
      case 'mixed':
        return 'Fiabilité Moyenne';
      case 'low':
        return 'Controversé';
      default:
        return 'Non évalué';
    }
  }

  IconData getReliabilityIcon() {
    // Requires phosphor_flutter import, but we can return dynamic or let UI handle it.
    // Ideally put UI logic in widgets, but for color/label helpers it's fine here.
    return Icons.shield_outlined; // Placeholder
  }

  String getThemeLabel() {
    switch (theme?.toLowerCase()) {
      case 'tech':
        return 'Tech & Futur';
      case 'society_climate':
        return 'Société & Climat';
      case 'economy':
        return 'Économie';
      case 'environment':
        return 'Environnement';
      case 'politics':
        return 'Politique';
      case 'culture_ideas':
        return 'Culture & Idées';
      case 'science':
        return 'Science';
      case 'geopolitics':
        return 'Géopolitique';
      default:
        // Capitalize first letter if not in mapping
        if (theme == null || theme!.isEmpty || theme == 'custom') {
          return 'Général';
        }
        return theme![0].toUpperCase() + theme!.substring(1);
    }
  }
}
