/// Ordre unifié de la Tournée du jour — éditorial + thèmes + sources + veille.
///
/// Distinct de `pinned_tabs_order_v1` (onglets Flâner, cf.
/// `feed/providers/tab_order_prefs_provider.dart`) : ici on ordonne les
/// **sections de la Tournée**. Les clés typées sont alignées sur `sectionKey()`
/// (`flux_continu_models.dart`) pour que [applyOrder] s'aligne avec le rendu et
/// la dédup inter-sections : `essentiel` / `bonnes` / `grille` /
/// `theme:<slug>` / `source:<id>` / `veille`. Pas de clé `topic:` — les sujets
/// personnalisés sont exclus de la Tournée (Flâner-only).
///
/// `hiddenKeys` mémorise les retraits explicites depuis « Composer ma Tournée ».
/// Tant qu'une clé y figure, le provider Tournée ne ré-injecte pas l'élément
/// correspondant. Le getter compat `veilleHidden` couvre l'ancien usage veille.
///
/// `customized` mémorise que l'utilisateur a personnalisé sa Tournée au moins
/// une fois (ajout/retrait d'un thème, d'une source ou de la veille). Tant
/// qu'il est faux, le provider Tournée ré-injecte les thèmes canoniques de
/// fallback quand la liste de favoris est vide (comptes neufs). Dès la 1ʳᵉ
/// mutation il passe à `true` → un retrait volontaire est respecté et les
/// thèmes canoniques ne réapparaissent plus au prochain reload.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Réutilise le tri stable partagé — source unique de vérité (pas de copie).
export '../../feed/providers/tab_order_prefs_provider.dart' show applyOrder;

const _kTourneeOrderKey = 'tournee_order_v1';
const _kTourneeHiddenKeysKey = 'tournee_hidden_keys_v1';
const _kLegacyVeilleHiddenKey = 'tournee_veille_hidden_v1';
const _kTourneeCustomizedKey = 'tournee_customized_v1';

/// Cap d'affichage de la Tournée du jour, partagé provider + composer.
const int kTourneeVisibleCap = 7;

/// Clé d'un thème favori dans l'ordre Tournée (= `sectionKey` d'une section thème).
String tourneeThemeKey(String slug) => 'theme:$slug';

/// Clé d'une source favorite dans l'ordre Tournée (= `sectionKey` d'une section source).
String tourneeSourceKey(String sourceId) => 'source:$sourceId';

/// Clé des Actus du jour (DigestTopicSection `SectionKind.essentiel`).
const String kTourneeActusKey = 'essentiel';

/// Clé des Bonnes Nouvelles (DigestTopicSection `SectionKind.bonnes`).
const String kTourneeBonnesKey = 'bonnes';

/// Clé de La Grille du jour (slot autonome, pas une `FluxSection`).
const String kTourneeGrilleKey = 'grille';

/// Clé de la veille (singleton à V1) — alignée sur la branche `'veille'` de `sectionKey`.
const String kTourneeVeilleKey = 'veille';

/// État de l'ordre Tournée : la liste ordonnée de clés + les clés masquées +
/// le flag « Tournée customisée » (cf. doc de la library).
class TourneeOrderState {
  final List<String> order;
  final Set<String> hiddenKeys;
  final bool customized;

  const TourneeOrderState({
    required this.order,
    this.hiddenKeys = const {},
    this.customized = false,
  });

  static const empty = TourneeOrderState(
    order: [],
    hiddenKeys: {},
    customized: false,
  );

  /// Compat lecture legacy : la veille est masquée si sa clé est dans
  /// [hiddenKeys]. Les écritures doivent passer par [setHidden].
  bool get veilleHidden => hiddenKeys.contains(kTourneeVeilleKey);

  /// Story 10.2 — clés `source:` présentes dans l'ordre. Une source y figure
  /// ⇒ mode « Chaque jour dans l'Essentiel » (sinon mode « Flâner »). Source
  /// unique de la règle d'appartenance, partagée par le provider Tournée, les
  /// onglets Flâner et la sheet de gestion (évite la dérive entre chemins).
  Set<String> get essentielSourceKeys => {
        for (final key in order)
          if (key.startsWith('source:')) key,
      };

  /// `true` ssi la source [sourceId] est livrée en mode « Essentiel » (sa clé
  /// `source:<id>` est dans [order]). Voir [essentielSourceKeys].
  bool sourceIsEssentiel(String sourceId) =>
      order.contains(tourneeSourceKey(sourceId));

  TourneeOrderState copyWith({
    List<String>? order,
    Set<String>? hiddenKeys,
    bool? customized,
  }) => TourneeOrderState(
    order: order ?? this.order,
    hiddenKeys: hiddenKeys ?? this.hiddenKeys,
    customized: customized ?? this.customized,
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
      final hiddenList = prefs.getStringList(_kTourneeHiddenKeysKey);
      final hiddenKeys = hiddenList != null
          ? hiddenList.toSet()
          : <String>{
              if (prefs.getBool(_kLegacyVeilleHiddenKey) == true)
                kTourneeVeilleKey,
            };
      state = TourneeOrderState(
        order: prefs.getStringList(_kTourneeOrderKey) ?? const [],
        hiddenKeys: Set.unmodifiable(hiddenKeys),
        customized: prefs.getBool(_kTourneeCustomizedKey) ?? false,
      );
    } catch (_) {
      // Pas de prefs (ex. tests sans mock) → état vide.
      state = TourneeOrderState.empty;
    }
  }

  /// Écrit le nouvel ordre global (`essentiel`/`bonnes`/`grille`/`theme:`/
  /// `source:`/`veille`).
  Future<void> setOrder(List<String> keys) async {
    state = state.copyWith(order: List.unmodifiable(keys));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kTourneeOrderKey, keys);
    } catch (_) {
      // best-effort : l'ordre en mémoire reste appliqué pour la session.
    }
  }

  /// Masque (ou réaffiche) une clé dans la Tournée.
  Future<void> setHidden(String key, bool hidden) async {
    final next = Set<String>.from(state.hiddenKeys);
    if (hidden) {
      next.add(key);
    } else {
      next.remove(key);
    }
    final persisted = next.toList()..sort();
    state = state.copyWith(hiddenKeys: Set.unmodifiable(persisted));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kTourneeHiddenKeysKey, persisted);
    } catch (_) {
      // best-effort.
    }
  }

  /// Shim compat écriture veille-only.
  Future<void> setVeilleHidden(bool hidden) =>
      setHidden(kTourneeVeilleKey, hidden);

  /// Marque la Tournée comme personnalisée (1ʳᵉ mutation utilisateur). Idempotent
  /// — no-op si déjà vrai. Désactive le fallback canonique côté provider Tournée
  /// pour que les retraits volontaires soient respectés au prochain reload.
  Future<void> markCustomized() async {
    if (state.customized) return;
    state = state.copyWith(customized: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kTourneeCustomizedKey, true);
    } catch (_) {
      // best-effort.
    }
  }
}
