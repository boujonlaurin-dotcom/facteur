import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../digest/providers/digest_provider.dart'
    show digestRepositoryProvider;
import 'flux_continu_provider.dart';

/// Clé de préférence serveur de l'arrangement intelligent (Story 22.3).
/// Absence = activé (default-ON sans migration) ; seul `"false"` désactive.
const String kTourneeSmartArrangementKey = 'tournee_smart_arrangement';

/// État du switch « Suggestions du facteur » (sections « Choisie pour vous »).
class TourneeSmartArrangementState {
  final bool enabled;
  final bool isLoading;

  const TourneeSmartArrangementState({
    this.enabled = true,
    this.isLoading = true,
  });

  TourneeSmartArrangementState copyWith({bool? enabled, bool? isLoading}) {
    return TourneeSmartArrangementState(
      enabled: enabled ?? this.enabled,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Switch global « Suggestions du facteur » exposé dans « Composer ma Tournée ».
///
/// Le backend lit la préférence serveur `tournee_smart_arrangement` pour
/// (dés)activer l'arrangement intelligent ; ce provider en est le miroir
/// mobile (lecture initiale + écriture). Rebuild propre quand l'utilisateur
/// authentifié change (logout → autre compte), comme `sereinToggleProvider`.
final tourneeSmartArrangementProvider = StateNotifierProvider<
    TourneeSmartArrangementNotifier, TourneeSmartArrangementState>((ref) {
  ref.watch(authStateProvider.select((s) => s.user?.id));
  return TourneeSmartArrangementNotifier(ref).._init();
});

class TourneeSmartArrangementNotifier
    extends StateNotifier<TourneeSmartArrangementState> {
  final Ref _ref;

  TourneeSmartArrangementNotifier(this._ref)
      : super(const TourneeSmartArrangementState());

  Future<void> _init() async {
    try {
      final prefs = await _ref.read(digestRepositoryProvider).getPreferences();
      final entry = prefs.firstWhere(
        (p) => p['preference_key'] == kTourneeSmartArrangementKey,
        orElse: () => const <String, String>{},
      );
      // Absence (clé jamais écrite) = activé ; seul "false" désactive.
      final enabled = entry['preference_value'] != 'false';
      state = TourneeSmartArrangementState(enabled: enabled, isLoading: false);
    } catch (_) {
      // Échec réseau → on assume le défaut (activé) sans bloquer l'UI.
      state =
          const TourneeSmartArrangementState(enabled: true, isLoading: false);
    }
  }

  /// Bascule instantanée : l'UI flippe tout de suite, la préférence est
  /// persistée en arrière-plan, puis la Tournée est recalculée pour faire
  /// (dis)paraître les sections « Choisie pour vous ».
  Future<void> toggle() async {
    final next = !state.enabled;
    state = state.copyWith(enabled: next);
    unawaited(HapticFeedback.lightImpact());
    try {
      await _ref.read(digestRepositoryProvider).updatePreference(
            key: kTourneeSmartArrangementKey,
            value: next.toString(),
          );
    } catch (_) {
      // Silencieux : retenté à la prochaine session.
    }
    _ref.invalidate(fluxContinuProvider);
  }
}
