/// Ordre unifié de la Tournée du jour — thèmes + sources + veille mélangés.
///
/// Distinct de `pinned_tabs_order_v1` (onglets Flâner, cf.
/// `feed/providers/tab_order_prefs_provider.dart`) : ici on ordonne les
/// **sections de la Tournée**. Les clés typées sont alignées sur `sectionKey()`
/// (`flux_continu_models.dart`) pour que [applyOrder] s'aligne avec le rendu et
/// la dédup inter-sections : `theme:<slug>` / `source:<id>` / `veille`. Pas de
/// clé `topic:` — les sujets personnalisés sont exclus de la Tournée
/// (Flâner-only).
///
/// `veilleHidden` mémorise un retrait explicite de la veille depuis « Composer
/// ma Tournée ». Tant qu'il est vrai, le provider Tournée ne ré-injecte pas la
/// veille même si une config est active (suppression du self-heal) ; la
/// ré-ajouter via la modal le repasse à `false`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Réutilise le tri stable partagé — source unique de vérité (pas de copie).
export '../../feed/providers/tab_order_prefs_provider.dart' show applyOrder;

const _kTourneeOrderKey = 'tournee_order_v1';
const _kVeilleHiddenKey = 'tournee_veille_hidden_v1';

/// Clé d'un thème favori dans l'ordre Tournée (= `sectionKey` d'une section thème).
String tourneeThemeKey(String slug) => 'theme:$slug';

/// Clé d'une source favorite dans l'ordre Tournée (= `sectionKey` d'une section source).
String tourneeSourceKey(String sourceId) => 'source:$sourceId';

/// Clé de la veille (singleton à V1) — alignée sur la branche `'veille'` de `sectionKey`.
const String kTourneeVeilleKey = 'veille';

/// État de l'ordre Tournée : la liste ordonnée de clés + le flag de masquage veille.
class TourneeOrderState {
  final List<String> order;
  final bool veilleHidden;

  const TourneeOrderState({required this.order, required this.veilleHidden});

  static const empty = TourneeOrderState(order: [], veilleHidden: false);

  TourneeOrderState copyWith({List<String>? order, bool? veilleHidden}) =>
      TourneeOrderState(
        order: order ?? this.order,
        veilleHidden: veilleHidden ?? this.veilleHidden,
      );
}

final tourneeOrderPrefsProvider =
    StateNotifierProvider<TourneeOrderPrefsNotifier, TourneeOrderState>((ref) {
  return TourneeOrderPrefsNotifier();
});

class TourneeOrderPrefsNotifier extends StateNotifier<TourneeOrderState> {
  TourneeOrderPrefsNotifier() : super(TourneeOrderState.empty) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = TourneeOrderState(
        order: prefs.getStringList(_kTourneeOrderKey) ?? const [],
        veilleHidden: prefs.getBool(_kVeilleHiddenKey) ?? false,
      );
    } catch (_) {
      // Pas de prefs (ex. tests sans mock) → état vide.
      state = TourneeOrderState.empty;
    }
  }

  /// Écrit le nouvel ordre global (clés `theme:`/`source:`/`veille`).
  Future<void> setOrder(List<String> keys) async {
    state = state.copyWith(order: List.unmodifiable(keys));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kTourneeOrderKey, keys);
    } catch (_) {
      // best-effort : l'ordre en mémoire reste appliqué pour la session.
    }
  }

  /// Masque (ou réaffiche) la veille dans la Tournée. `true` désactive le
  /// self-heal côté provider Tournée même si une config veille est active.
  Future<void> setVeilleHidden(bool hidden) async {
    state = state.copyWith(veilleHidden: hidden);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kVeilleHiddenKey, hidden);
    } catch (_) {
      // best-effort.
    }
  }
}
