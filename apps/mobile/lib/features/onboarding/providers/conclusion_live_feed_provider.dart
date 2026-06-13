import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sources/models/source_recent_items.dart';
import '../../sources/providers/sources_providers.dart';
import 'onboarding_proof_cache_provider.dart';
import 'onboarding_provider.dart';

/// Derniers contenus des sources choisies, pour l'animation de conclusion.
/// Best-effort : erreur réseau → liste vide (fallback loader classique).
final conclusionRecentItemsProvider =
    FutureProvider.autoDispose<List<SourceRecentItems>>((ref) async {
  final ids =
      ref.read(onboardingProvider).answers.preferredSources ?? const [];
  if (ids.isEmpty) return const [];
  return ref
      .read(sourcesRepositoryProvider)
      .fetchRecentItems(ids.take(30).toList());
});

/// Entrées affichables par [ConclusionLiveFeed] : seeds instantanés du cache
/// de preuve (Wow #1) fusionnés avec la réponse de l'endpoint quand elle
/// arrive. Dédup par sourceId, l'endpoint (plus riche/frais) gagne ; les
/// seeds restent en tête pour ne pas réordonner ce qui est déjà affiché.
final conclusionLiveFeedEntriesProvider =
    Provider.autoDispose<List<SourceRecentItems>>((ref) {
  final seeds = ref.watch(onboardingProofCacheProvider);
  final fetched =
      ref.watch(conclusionRecentItemsProvider).valueOrNull ?? const [];
  final fetchedById = {for (final s in fetched) s.sourceId: s};

  final entries = <SourceRecentItems>[];
  final seen = <String>{};

  for (final seed in seeds.values) {
    final fromApi = fetchedById[seed.sourceId];
    entries.add(
      fromApi ??
          SourceRecentItems(
            sourceId: seed.sourceId,
            name: seed.name,
            logoUrl: seed.logoUrl,
            items: seed.items,
          ),
    );
    seen.add(seed.sourceId);
  }
  for (final s in fetched) {
    if (seen.add(s.sourceId)) entries.add(s);
  }
  return entries.where((e) => e.items.isNotEmpty).toList();
});
