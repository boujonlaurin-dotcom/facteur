import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/digest_mode.dart';
import '../providers/digest_provider.dart';

/// State pour le mode digest actif.
class DigestModeState {
  final DigestMode mode;

  /// True pendant le changement de mode (régénération en cours)
  final bool isRegenerating;

  const DigestModeState({
    this.mode = DigestMode.pourVous,
    this.isRegenerating = false,
  });

  DigestModeState copyWith({
    DigestMode? mode,
    bool? isRegenerating,
  }) {
    return DigestModeState(
      mode: mode ?? this.mode,
      isRegenerating: isRegenerating ?? this.isRegenerating,
    );
  }
}

/// Provider pour le mode digest actif.
///
/// Gère :
/// - Le mode sélectionné (Pour vous, Serein, Changer de bord)
/// - La sauvegarde de la préférence pour demain
/// - La régénération immédiate du digest avec le nouveau mode
final digestModeProvider =
    StateNotifierProvider<DigestModeNotifier, DigestModeState>((ref) {
  return DigestModeNotifier(ref);
});

class DigestModeNotifier extends StateNotifier<DigestModeState> {
  final Ref _ref;

  DigestModeNotifier(this._ref) : super(const DigestModeState());

  /// Initialise le mode depuis la réponse API du digest
  void initFromDigestResponse(String modeKey) {
    final mode = DigestMode.fromKey(modeKey);
    if (mode != state.mode) {
      state = DigestModeState(mode: mode);
    }
  }

  /// Change le mode du digest.
  ///
  /// 1. Met à jour l'UI immédiatement (couleur, gradient, sous-titre)
  /// 2. Sauvegarde la préférence pour demain
  /// 3. Régénère le digest avec le nouveau mode
  Future<void> setMode(DigestMode newMode) async {
    if (newMode == state.mode) return;

    // 1. UI immédiate
    state = state.copyWith(
      mode: newMode,
      isRegenerating: true,
    );

    try {
      final repository = _ref.read(digestRepositoryProvider);

      // 2. Sauvegarder la préférence pour demain (fire & forget)
      repository.updatePreference(key: 'digest_mode', value: newMode.key);

      // 3. Régénérer le digest avec le nouveau mode
      final newDigest = await repository.regenerateWithMode(
        mode: newMode.key,
      );

      // Mettre à jour le digestProvider avec la nouvelle réponse
      _ref.read(digestProvider.notifier).updateFromResponse(newDigest);

      state = state.copyWith(isRegenerating: false);
    } catch (e) {
      // Rollback en cas d'erreur
      state = state.copyWith(isRegenerating: false);
    }
  }
}
