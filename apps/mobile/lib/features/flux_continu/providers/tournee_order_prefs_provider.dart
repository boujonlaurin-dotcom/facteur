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

import 'package:facteur/config/constants.dart' show kFavoriteCap;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Réutilise le tri stable partagé — source unique de vérité (pas de copie).
export '../../feed/providers/tab_order_prefs_provider.dart' show applyOrder;

const _kTourneeOrderKey = 'tournee_order_v1';
const _kTourneeHiddenKeysKey = 'tournee_hidden_keys_v1';
const _kLegacyVeilleHiddenKey = 'tournee_veille_hidden_v1';
const _kTourneeCustomizedKey = 'tournee_customized_v1';

/// Cap d'affichage de la Tournée du jour, partagé provider + composer.
///
/// Couvre favoris + suggestions « Choisie pour vous » + cartes éditoriales
/// (Actus, Bonnes, Grille) — pas la carte hi-fi Essentiel du haut, rendue à
/// part.
///
/// **Ce n'est pas un knob libre : c'est une quantité dérivée.** Le cap réserve
/// [kTourneeSuggestQuota] slots de *marge* aux suggestions « Choisie pour vous »
/// au-dessus de `kTourneeEditorialCount + kFavoriteCap`, pour qu'un compte qui
/// n'est pas au plafond de favoris voie quand même des suggestions. Depuis le
/// bug « blocs favoris absents » (#1098) cette marge n'est plus une *réserve
/// mordante* : les suggestions ne se servent plus qu'en fin, sur les slots
/// laissés libres par les favoris et l'éditorial (cf. `_orderedTourneeKeys`), et
/// un bloc placé par l'utilisateur n'est **jamais** évincé à leur profit. La
/// marge borne juste le nombre de suggestions affichables ; elle ne coupe plus
/// rien.
///
/// Pour qu'un compte au plafond de favoris garde ses cartes éditoriales, il faut
/// `cap >= kTourneeEditorialCount + kFavoriteCap`. L'égalité ci-dessous ajoute la
/// marge de suggestions au-dessus de ce minimum.
///
/// Écrire la formule plutôt que sa valeur n'est pas cosmétique : la Story 22.8
/// avait d'abord posé 15 (en oubliant la marge de suggestions), ce qui coupait
/// **Bonnes Nouvelles** — dernière du bloc éditorial, donc première sacrifiée —
/// en silence. Verrouillé par le test « plafond de favoris + suggestions »
/// (`flux_continu_tournee_order_test.dart`).
///
/// Story 22.8 — la cible passe à [kFavoriteCap] favoris visibles : `kFavoriteCap`
/// monte à 10, et le cap suit par la formule.
///
/// Limite connue et **inchangée** : [kFavoriteCap] est un plafond *par nature*
/// (thèmes et sources comptés séparément), donc un compte qui cumule les deux
/// dépasse le cap et se fait quand même élaguer. L'égalité ci-dessous protège
/// l'éditorial du cas mono-nature, pas du cumul.
const int kTourneeVisibleCap =
    kTourneeSuggestQuota + kTourneeEditorialCount + kFavoriteCap;

/// Marge de slots laissée aux suggestions « Choisie pour vous » au-dessus du
/// minimum favoris + éditorial. **N'est plus une réserve mordante** (#1098) :
/// les suggestions prennent seulement les slots libres, sans jamais évincer un
/// favori — cette constante borne juste combien de suggestions peuvent tenir
/// sous [kTourneeVisibleCap].
const int kTourneeSuggestQuota = 3;

/// Compromis d'affichage des blocs de la Tournée (V1 — base de test PO).
///
/// Deux régimes **distincts**, à ne jamais confondre : la pénurie masque, la
/// pauvreté déclasse. Un bloc n'est jamais retiré parce qu'il est *moins bon* —
/// seulement parce qu'il n'a rien à montrer.
///
/// * **Masquage** — un bloc qui n'a pas [kSectionMinItems] articles à afficher,
///   *après* réinjection de ceux que la dédup inter-sections lui a pris (cf.
///   `_backfillThinSections`), sort du flux : pas de bloc à moitié vide qui
///   pollue l'écran. Il reste listé dans « Mes favoris », signalé « Pas assez
///   d'articles » (cf. [FluxContinuState.starvedFavoriteKeys]) — masqué pour la
///   journée n'est pas retiré des favoris.
/// * **Déclassement** — un bloc qui a de quoi s'afficher mais dont la curation
///   du jour est pauvre (score de bloc < [kPoorBlockScoreRatio] × la médiane des
///   blocs favoris du jour) reste affiché : il descend simplement sous les
///   autres favoris, tout en gardant sa priorité sur les sections « Choisie pour
///   vous ». Un choix de l'utilisateur passe toujours avant une suggestion.
///
/// Le déclassement ne s'applique qu'à partir de [kPoorDemotionMinBlocks] blocs
/// favoris scorés : sous ce seuil la médiane ne veut rien dire, et déclasser
/// 1 bloc sur 2 n'aurait aucun sens.
const int kSectionMinItems = 3;
const double kPoorBlockScoreRatio = 0.5;
const int kPoorDemotionMinBlocks = 3;

/// Kill-switch du tri des blocs par score (`section_score_order.dart`, PR-4).
///
/// À `true` (défaut) : l'ordre des blocs est trié par la somme des 3 meilleurs
/// scores de leurs articles, gelé une fois par journée tournée. Le
/// **déclassement qualité** ([kPoorBlockScoreRatio]) est gelé au même instant,
/// à partir des mêmes scores, et persisté dans la même entrée de prefs.
///
/// À `false` : aucun ordre trié ni persisté — donc aucun déclassement non plus
/// (rien n'est gelé). Le **masquage** ([kSectionMinItems]), lui, ne dépend
/// d'aucun score : il reste actif dans les deux cas.
///
/// Le kill-switch désarme le **tri**, pas la **mesure** : `blockScores` reste
/// calculé et `block_score` reste renseigné sur `article_impression` (PR-1).
/// Couper le tri ne doit pas aveugler l'instrument qui sert à le juger.
const bool kTourneeScoreSortEnabled = true;

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

/// Cartes éditoriales de la Tournée : elles occupent des slots sous
/// [kTourneeVisibleCap] sans être des favoris ni des suggestions.
const List<String> kTourneeEditorialKeys = [
  kTourneeActusKey,
  kTourneeGrilleKey,
  kTourneeBonnesKey,
];

/// Cardinalité de [kTourneeEditorialKeys], en `const int` parce que
/// [kTourneeVisibleCap] en dépend et que Dart ne const-fold pas `List.length`.
/// L'accord entre les deux est vérifié par un test — ajouter une carte
/// éditoriale sans toucher ce nombre couperait une section en silence.
const int kTourneeEditorialCount = 3;

/// `true` ssi [key] désigne une section **réordonnable** de la Tournée, au sens
/// « l'utilisateur peut la déplacer ». Source unique de vérité partagée par la
/// sheet « Composer ma Tournée » et le drag des onglets du header sticky.
///
/// Sont exclus :
/// - `essentiel_v3` (carte hi-fi héros, toujours 1ʳᵉ),
/// - `grille` (Mot du jour, épinglé après les Actus par `grilleSlotIndex`),
/// - `alerts` et tout onglet virtuel (Citation, Fin de tournée, « Pour toi »),
/// - `topic:` (sujets personnalisés — Flâner uniquement, hors Tournée).
bool isTourneeReorderableKey(String key) =>
    key == kTourneeActusKey ||
    key == kTourneeBonnesKey ||
    key == kTourneeVeilleKey ||
    key.startsWith('theme:') ||
    key.startsWith('source:');

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
