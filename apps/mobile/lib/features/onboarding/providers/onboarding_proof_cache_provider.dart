import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sources/models/smart_search_result.dart';

/// Preuve capturée lors d'un ajout via le panneau smart-search (Wow #1) :
/// identité de la source + ses derniers articles.
class SourceProofSeed {
  final String sourceId;
  final String name;
  final String? logoUrl;
  final List<SmartSearchRecentItem> items;

  const SourceProofSeed({
    required this.sourceId,
    required this.name,
    this.logoUrl,
    this.items = const [],
  });
}

/// Cache éphémère sourceId → preuve, alimenté par la page sources de
/// l'onboarding à chaque ajout smart-search. Sert de seed instantané à
/// l'animation de conclusion (Wow #2) avant la réponse de l'endpoint
/// `/sources/recent-items`. Vidé à la sortie de l'onboarding.
final onboardingProofCacheProvider =
    StateProvider<Map<String, SourceProofSeed>>((ref) => {});
