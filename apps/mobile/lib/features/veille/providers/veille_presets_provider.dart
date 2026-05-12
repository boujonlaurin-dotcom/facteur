import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../models/veille_config.dart';

/// Charge les pré-sets V1 (`GET /api/veille/presets`) affichés en bas du
/// Step 1. Endpoint public (pas d'auth) : la liste est statique côté serveur
/// + sources curées hydratées depuis la table `sources`.
///
/// Fallback silencieux à `[]` en cas d'erreur réseau — la grille de thèmes
/// du Step 1 reste utilisable, on perd juste l'inspiration.
final veillePresetsProvider = FutureProvider<List<VeillePreset>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  try {
    final response = await apiClient.dio.get<dynamic>('veille/presets');
    final raw = response.data as List<dynamic>;
    return raw
        .whereType<Map<String, dynamic>>()
        .map(VeillePreset.fromJson)
        .toList();
  } on DioException {
    return const <VeillePreset>[];
  }
});
