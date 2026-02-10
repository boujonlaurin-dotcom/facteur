import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/digest_mode.dart';
import '../providers/digest_provider.dart';

/// State pour le mode digest actif.
class DigestModeState {
  final DigestMode mode;
  final String? focusTheme;

  /// True pendant le changement de mode (régénération en cours)
  final bool isRegenerating;

  /// True si le mode a été changé (pour afficher le message inline)
  final bool showModeChangedMessage;

  const DigestModeState({
    this.mode = DigestMode.pourVous,
    this.focusTheme,
    this.isRegenerating = false,
    this.showModeChangedMessage = false,
  });

  DigestModeState copyWith({
    DigestMode? mode,
    String? focusTheme,
    bool? isRegenerating,
    bool? showModeChangedMessage,
  }) {
    return DigestModeState(
      mode: mode ?? this.mode,
      focusTheme: focusTheme ?? this.focusTheme,
      isRegenerating: isRegenerating ?? this.isRegenerating,
      showModeChangedMessage:
          showModeChangedMessage ?? this.showModeChangedMessage,
    );
  }
}

/// Provider pour le mode digest actif.
///
/// Gère :
/// - Le mode sélectionné (Pour vous, Serein, Changer, Focus)
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
  /// 1. Met à jour l'UI immédiatement (couleur, gradient, emoji)
  /// 2. Sauvegarde la préférence pour demain
  /// 3. Régénère le digest avec le nouveau mode
  Future<void> setMode(DigestMode newMode, {String? focusTheme}) async {
    if (newMode == state.mode && focusTheme == state.focusTheme) return;

    // 1. UI immédiate
    state = state.copyWith(
      mode: newMode,
      focusTheme: focusTheme ?? state.focusTheme,
      isRegenerating: true,
      showModeChangedMessage: true,
    );

    try {
      final repository = _ref.read(digestRepositoryProvider);

      // 2. Sauvegarder la préférence pour demain (fire & forget)
      repository.updatePreference(key: 'digest_mode', value: newMode.key);
      if (newMode == DigestMode.themeFocus && focusTheme != null) {
        repository.updatePreference(
            key: 'digest_focus_theme', value: focusTheme);
      }

      // 3. Régénérer le digest avec le nouveau mode
      final newDigest = await repository.regenerateWithMode(
        mode: newMode.key,
        focusTheme:
            newMode == DigestMode.themeFocus ? focusTheme : null,
      );

      // Mettre à jour le digestProvider avec la nouvelle réponse
      _ref.read(digestProvider.notifier).updateFromResponse(newDigest);

      state = state.copyWith(isRegenerating: false);

      // Masquer le message après 5 secondes
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          state = state.copyWith(showModeChangedMessage: false);
        }
      });
    } catch (e) {
      // Rollback en cas d'erreur
      state = state.copyWith(isRegenerating: false);
    }
  }
}
