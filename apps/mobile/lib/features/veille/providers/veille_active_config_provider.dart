import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/veille_config_dto.dart';
import 'veille_repository_provider.dart';

/// AsyncNotifier load-on-enter pour la config veille active de l'utilisateur.
///
/// `null` → pas de veille configurée (404). Un DTO → veille active. Une erreur
/// → propagée à l'UI (pas de retry agressif, anti-cascade pool DB).
///
/// Pas de cache disque : refresh = invalidation provider via `ref.invalidate`.
class VeilleActiveConfigNotifier extends AsyncNotifier<VeilleConfigDto?> {
  @override
  Future<VeilleConfigDto?> build() async {
    final repo = ref.read(veilleRepositoryProvider);
    return repo.getConfig();
  }

  /// Met à jour la config locale après un PATCH/POST réussi pour éviter un
  /// round-trip réseau supplémentaire. Le caller passe le DTO frais renvoyé
  /// par le backend.
  void hydrateFromServer(VeilleConfigDto? cfg) {
    state = AsyncData(cfg);
  }
}

final veilleActiveConfigProvider = AsyncNotifierProvider<
    VeilleActiveConfigNotifier, VeilleConfigDto?>(
  VeilleActiveConfigNotifier.new,
);
