import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../custom_topics/widgets/entity_add_sheet.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../feed/providers/tab_order_prefs_provider.dart';
import '../../feed/widgets/favorite_topic_tabs.dart' show kMaxFavoriteTabs;
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/models/user_sources_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../../tour/tour_anchors.dart';
import '../../veille/providers/veille_active_config_provider.dart';
import '../../veille/providers/veille_themes_provider.dart';
import '../providers/flux_continu_provider.dart' show fluxContinuProvider;
import '../providers/tournee_order_prefs_provider.dart' hide applyOrder;
import '../providers/tournee_smart_arrangement_provider.dart';
import '../utils/theme_color_mapping.dart';
import 'choice_tile.dart';

/// Story 10.2 — sheet unifiée « Mes favoris », deux modes de livraison :
/// « Chaque matin dans ton Essentiel » (Tournée, cap 7) et « Tes onglets pour
/// explorer » (Flâner, cap 10). L'ajout n'est jamais bloqué : le surplus
/// au-delà du cap de section apparaît grisé sous un trait. Une seule sheet, deux
/// portes : [entry] présélectionne le segment « Ajouter » et, côté Flâner,
/// scrolle vers la section Flâner à l'ouverture — le contenu est identique.
enum ManageFavoritesEntry { essentiel, flaner }

/// Accent des Actus du jour (aligné provider Tournée). Sert aussi d'**identité
/// « Essentiel »** dans cette sheet (en-tête + puces « → Essentiel »).
const Color _kEssentielAccent = Color(0xFFB0470A);

/// Identité visuelle **« Flâner »** dans cette sheet : le brun du bandeau de la
/// page Flâner (déjà reconnaissable). Colore l'en-tête « Onglets de ta page
/// Flâner » et les puces « → Flâner », pour que la destination d'un déplacement
/// soit lisible par sa couleur (et plus par celle, arbitraire, de la carte).
const Color _kFlanerAccent = Color(0xFF5D4037);

/// Accent des Bonnes Nouvelles (aligné provider Tournée).
const Color _kBonnesAccent = Color(0xFF2E7D32);

/// Accent de la veille (aligné `FacteurColors.sectionVeille1`).
const Color _kVeilleAccent = Color(0xFF2C3E50);

/// Ouvre la sheet unifiée de gestion des favoris. [entry] présélectionne le
/// segment d'ajout (sources/thèmes côté Essentiel, sources/sujets côté Flâner).
Future<void> showManageFavoritesSheet(
  BuildContext context, {
  ManageFavoritesEntry entry = ManageFavoritesEntry.essentiel,
}) {
  // NB z-order : on N'utilise PAS `useRootNavigator: true` à dessein. La feuille
  // vit ainsi dans le navigator de **branche**, ce qui laisse l'overlay racine
  // du tour guidé ([tourFavorisSheetKey]) se rendre au-dessus pour la cerner
  // (cf. plan tour guidé, étape 2). Repasser en root navigator casserait le
  // spotlight de l'étape « Compose ta Tournée ».
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    enableDrag: true,
    isDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => KeyedSubtree(
      key: tourFavorisSheetKey,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: _ManageFavoritesContent(entry: entry),
        ),
      ),
    ),
  );
}

enum _FavKind { actus, bonnes, grille, theme, veille, source, subject }

/// Un élément de favori dans l'une des deux sections. La [key] est alignée sur
/// `sectionKey()` côté Essentiel (`essentiel`/`bonnes`/`grille`/`theme:`/
/// `source:`/`veille`) et sur la clé d'ordre Flâner côté Flâner
/// (`topic:`/`source:`). La clé `source:<id>` est commune aux deux systèmes.
class _FavItem {
  final String key;
  final _FavKind kind;
  final String id; // slug | sourceId | topicId | configId | clé éditoriale
  final String label;
  final String emoji;
  final Color accent;
  final Source? source;

  const _FavItem({
    required this.key,
    required this.kind,
    required this.id,
    required this.label,
    required this.accent,
    this.emoji = '',
    this.source,
  });
}

String _themeEmoji(String slug) {
  for (final t in kVeilleFacteurThemes) {
    if (t.slug == slug) return t.emoji;
  }
  return '📰';
}

class _ManageFavoritesContent extends ConsumerStatefulWidget {
  const _ManageFavoritesContent({required this.entry});

  final ManageFavoritesEntry entry;

  @override
  ConsumerState<_ManageFavoritesContent> createState() =>
      _ManageFavoritesContentState();
}

class _ManageFavoritesContentState
    extends ConsumerState<_ManageFavoritesContent> {
  /// Onglet actif de la zone « AJOUTER » : 0 = Sources, 1 = Thèmes, 2 = Sujets.
  late int _addTab = widget.entry == ManageFavoritesEntry.flaner ? 2 : 1;

  /// Ancre l'en-tête de la section Flâner pour le scroll auto à l'ouverture.
  final GlobalKey _flanerSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Bonus UX : ouverture depuis un onglet Flâner → on amène la section
    // « ONGLETS DE TA PAGE FLÂNER » à l'écran (l'Essentiel est déjà en tête).
    if (widget.entry == ManageFavoritesEntry.flaner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _flanerSectionKey.currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0,
        );
      });
    }
  }

  // ── Helpers d'ordre (prefs) ──────────────────────────────────────────────

  Future<void> _appendTournee(String key) async {
    final cur = ref.read(tourneeOrderPrefsProvider).order;
    if (cur.contains(key)) return;
    await ref.read(tourneeOrderPrefsProvider.notifier).setOrder([...cur, key]);
  }

  Future<void> _removeTournee(String key) async {
    final next = ref
        .read(tourneeOrderPrefsProvider)
        .order
        .where((k) => k != key)
        .toList();
    await ref.read(tourneeOrderPrefsProvider.notifier).setOrder(next);
  }

  Future<void> _appendTab(String key) async {
    final cur = ref.read(tabOrderPrefsProvider);
    if (cur.contains(key)) return;
    await ref.read(tabOrderPrefsProvider.notifier).setOrder([...cur, key]);
  }

  Future<void> _removeTab(String key) async {
    final next = ref
        .read(tabOrderPrefsProvider)
        .where((k) => k != key)
        .toList();
    await ref.read(tabOrderPrefsProvider.notifier).setOrder(next);
  }

  // ── Ajouts ────────────────────────────────────────────────────────────────

  Future<void> _onAddTheme(String slug) async {
    await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
    try {
      await ref
          .read(userInterestsProvider.notifier)
          .setInterestState(
            ThemeFavoriteRef(slug: slug),
            InterestState.favorite,
          );
      await _appendTournee(tourneeThemeKey(slug));
    } catch (e) {
      NotificationService.showError('Erreur : $e');
    }
  }

  /// Ajoute une source dans le mode de la porte d'entrée : Essentiel (clé dans
  /// `tournee_order_v1`) ou Flâner (clé dans `pinned_tabs_order_v1`).
  Future<void> _onAddSource(String sourceId) async {
    final toEssentiel = widget.entry == ManageFavoritesEntry.essentiel;
    if (toEssentiel) {
      await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
    }
    try {
      await ref
          .read(userSourcesStateProvider.notifier)
          .setSourceState(sourceId, InterestState.favorite);
      if (toEssentiel) {
        await _appendTournee(tourneeSourceKey(sourceId));
      } else {
        await _appendTab(tabOrderSourceKey(sourceId));
      }
    } catch (e) {
      NotificationService.showError('Erreur : $e');
    }
  }

  Future<void> _onAddVeille() async {
    await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
    await ref
        .read(tourneeOrderPrefsProvider.notifier)
        .setHidden(kTourneeVeilleKey, false);
    await _appendTournee(kTourneeVeilleKey);
  }

  Future<void> _onRestoreEditorial(String key) async {
    await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
    await ref.read(tourneeOrderPrefsProvider.notifier).setHidden(key, false);
    await _appendTournee(key);
  }

  // ── Déplacement de mode (sources uniquement) ───────────────────────────────

  Future<void> _moveSourceToFlaner(String sourceId) async {
    await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
    await _removeTournee(tourneeSourceKey(sourceId));
    await _appendTab(tabOrderSourceKey(sourceId));
    NotificationService.showSuccess('Déplacé vers Flâner');
  }

  Future<void> _moveSourceToEssentiel(String sourceId) async {
    await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
    await _removeTab(tabOrderSourceKey(sourceId));
    await _appendTournee(tourneeSourceKey(sourceId));
    NotificationService.showSuccess('Déplacé vers l\'Essentiel');
  }

  // Thèmes : même modèle exclusif que les sources. La clé `theme:<slug>` est
  // partagée entre `tournee_order_v1` (Essentiel) et `pinned_tabs_order_v1`
  // (Flâner) ; la favorite reste un `ThemeFavoriteRef` (on ne touche pas à
  // `setInterestState`).
  Future<void> _moveThemeToFlaner(String slug) async {
    await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
    await _removeTournee(tourneeThemeKey(slug));
    await _appendTab(tabOrderThemeKey(slug));
    NotificationService.showSuccess('Déplacé vers Flâner');
  }

  Future<void> _moveThemeToEssentiel(String slug) async {
    await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
    await _removeTab(tabOrderThemeKey(slug));
    await _appendTournee(tourneeThemeKey(slug));
    NotificationService.showSuccess('Déplacé vers l\'Essentiel');
  }

  // ── Retraits ────────────────────────────────────────────────────────────

  Future<void> _onRemove(_FavItem item) async {
    switch (item.kind) {
      case _FavKind.theme:
        await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
        await _removeTournee(item.key);
        // Modèle exclusif : la clé `theme:<slug>` peut être côté Flâner.
        await _removeTab(item.key);
        try {
          await ref
              .read(userInterestsProvider.notifier)
              .setInterestState(
                ThemeFavoriteRef(slug: item.id),
                InterestState.followed,
              );
        } catch (e) {
          NotificationService.showError('Erreur : $e');
        }
      case _FavKind.source:
        final wasEssentiel = ref
            .read(tourneeOrderPrefsProvider)
            .sourceIsEssentiel(item.id);
        if (wasEssentiel) {
          await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
        }
        await _removeTournee(tourneeSourceKey(item.id));
        await _removeTab(tabOrderSourceKey(item.id));
        try {
          await ref
              .read(userSourcesStateProvider.notifier)
              .setSourceState(item.id, InterestState.followed);
        } catch (e) {
          NotificationService.showError('Erreur : $e');
        }
      case _FavKind.subject:
        await _removeTab(item.key);
        try {
          await ref
              .read(userInterestsProvider.notifier)
              .setInterestState(
                CustomTopicFavoriteRef(id: item.id),
                InterestState.unfollowed,
              );
        } catch (e) {
          NotificationService.showError('Erreur : $e');
        }
      case _FavKind.veille:
        await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
        await ref
            .read(tourneeOrderPrefsProvider.notifier)
            .setHidden(kTourneeVeilleKey, true);
      case _FavKind.actus:
      case _FavKind.bonnes:
      case _FavKind.grille:
        await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
        await ref
            .read(tourneeOrderPrefsProvider.notifier)
            .setHidden(item.key, true);
    }
  }

  // ── Réordres ──────────────────────────────────────────────────────────────

  Future<void> _persistEssentielReorder(List<_FavItem> ordered) async {
    await ref
        .read(tourneeOrderPrefsProvider.notifier)
        .setOrder(ordered.map((e) => e.key).toList());
    final themeRefs = <FavoriteRef>[
      for (final e in ordered)
        if (e.kind == _FavKind.theme) ThemeFavoriteRef(slug: e.id),
    ];
    final sourceIds = [
      for (final e in ordered)
        if (e.kind == _FavKind.source) e.id,
    ];
    await Future.wait([
      _syncThemePositions(themeRefs),
      _syncSourcePositionsMerged(sourceIds, essentiel: true),
    ]);
  }

  Future<void> _persistFlanerReorder(List<_FavItem> ordered) async {
    await ref
        .read(tabOrderPrefsProvider.notifier)
        .setOrder(ordered.map((e) => e.key).toList());
    final topicIds = [
      for (final e in ordered)
        if (e.kind == _FavKind.subject) e.id,
    ];
    final sourceIds = [
      for (final e in ordered)
        if (e.kind == _FavKind.source) e.id,
    ];
    await Future.wait([
      _syncTopicPositions(topicIds),
      _syncSourcePositionsMerged(sourceIds, essentiel: false),
    ]);
  }

  /// Réordonne les `ThemeFavoriteRef` serveur en préservant veille/custom-topics.
  Future<void> _syncThemePositions(List<FavoriteRef> themeRefs) async {
    final interests = ref.read(userInterestsProvider).valueOrNull;
    if (interests == null) return;
    final themeSlots = interests.favorites.whereType<ThemeFavoriteRef>().length;
    if (themeRefs.length != themeSlots) return;
    var i = 0;
    final merged = [
      for (final f in interests.favorites)
        f is ThemeFavoriteRef ? themeRefs[i++] : f,
    ];
    try {
      await ref.read(userInterestsProvider.notifier).reorderFavorites(merged);
    } catch (_) {
      // best-effort.
    }
  }

  /// Réordonne les `CustomTopicFavoriteRef` serveur en préservant thèmes/veille.
  Future<void> _syncTopicPositions(List<String> topicIds) async {
    final interests = ref.read(userInterestsProvider).valueOrNull;
    if (interests == null) return;
    final queue = [for (final id in topicIds) CustomTopicFavoriteRef(id: id)];
    final slots = interests.favorites
        .whereType<CustomTopicFavoriteRef>()
        .length;
    if (queue.length != slots) return;
    var i = 0;
    final merged = [
      for (final f in interests.favorites)
        f is CustomTopicFavoriteRef ? queue[i++] : f,
    ];
    try {
      await ref.read(userInterestsProvider.notifier).reorderFavorites(merged);
    } catch (_) {
      // best-effort.
    }
  }

  /// Réassigne les positions serveur des sources favorites **sans jamais
  /// perdre** celles de l'autre section : `reorderFavorites` remplace toute la
  /// liste, donc on fusionne le sous-ensemble réordonné avec l'autre mode.
  Future<void> _syncSourcePositionsMerged(
    List<String> reorderedIds, {
    required bool essentiel,
  }) async {
    final sourcesState = ref.read(userSourcesStateProvider).valueOrNull;
    if (sourcesState == null) return;
    final tournee = ref.read(tourneeOrderPrefsProvider);
    bool isEssentiel(String id) => tournee.sourceIsEssentiel(id);
    final reorderedSet = reorderedIds.toSet();
    final others = [
      for (final f in [
        ...sourcesState.favorites,
      ]..sort((a, b) => a.position.compareTo(b.position)))
        if ((essentiel ? !isEssentiel(f.sourceId) : isEssentiel(f.sourceId)) &&
            !reorderedSet.contains(f.sourceId))
          f.sourceId,
    ];
    final fullIds = essentiel
        ? [...reorderedIds, ...others]
        : [...others, ...reorderedIds];
    final refs = [
      for (var i = 0; i < fullIds.length; i++)
        SourceFavoriteRef(sourceId: fullIds[i], position: i),
    ];
    try {
      await ref.read(userSourcesStateProvider.notifier).reorderFavorites(refs);
    } catch (_) {
      // best-effort : l'ordre prefs reste appliqué.
    }
  }

  void _openVeilleConfig() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.pushNamed(RouteNames.veilleConfig);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final interests = ref.watch(userInterestsProvider).valueOrNull;
    final sourcesState = ref.watch(userSourcesStateProvider).valueOrNull;
    final catalog =
        ref.watch(userSourcesProvider).valueOrNull ?? const <Source>[];
    final sourceById = {for (final s in catalog) s.id: s};
    final veilleCfg = ref.watch(veilleActiveConfigProvider).valueOrNull;
    final tournee = ref.watch(tourneeOrderPrefsProvider);
    final tabOrder = ref.watch(tabOrderPrefsProvider);
    final isSerene = ref.watch(sereinToggleProvider).enabled;
    // Cohérence Tournée — clés favorites maigres (peu d'articles aujourd'hui).
    // Set vide si la Tournée n'est pas (encore) chargée → aucun indicateur
    // (dégradation propre).
    final thinKeys = ref.watch(fluxContinuProvider).valueOrNull?.thinFavoriteKeys ??
        const <String>{};

    // ── Membership ────────────────────────────────────────────────────────
    final favoriteThemeSlugs = <String>[
      for (final f in interests?.favorites ?? const <FavoriteRef>[])
        if (f is ThemeFavoriteRef) f.slug,
    ];
    final favoriteTopicIds = <String>{
      for (final f in interests?.favorites ?? const <FavoriteRef>[])
        if (f is CustomTopicFavoriteRef) f.id,
    };
    final customTopics =
        interests?.customTopics ?? const <CustomTopicInterest>[];
    final sourceFavorites = [...(sourcesState?.favorites ?? const [])]
      ..sort((a, b) => a.position.compareTo(b.position));

    // ── Items éditoriaux (Essentiel) ───────────────────────────────────────
    const actusItem = _FavItem(
      key: kTourneeActusKey,
      kind: _FavKind.actus,
      id: kTourneeActusKey,
      // « Mot du jour » = la Grille, désormais implicitement rattachée aux Actus
      // (plus un bloc drag&drop autonome).
      label: 'Actus & Mot du jour',
      emoji: '🗞️',
      accent: _kEssentielAccent,
    );
    const bonnesItem = _FavItem(
      key: kTourneeBonnesKey,
      kind: _FavKind.bonnes,
      id: kTourneeBonnesKey,
      label: 'Bonnes Nouvelles',
      emoji: '🌱',
      accent: _kBonnesAccent,
    );
    // Story Essentiel UX — thèmes en modèle exclusif (miroir des sources) : un
    // thème dont la clé `theme:<slug>` est dans `pinned_tabs_order_v1` vit en
    // **onglet Flâner** ; sinon dans l'**Essentiel** (défaut).
    final essentielThemeItems = <_FavItem>[];
    final flanerThemeItems = <_FavItem>[];
    for (final slug in favoriteThemeSlugs) {
      final item = _FavItem(
        key: tourneeThemeKey(slug),
        kind: _FavKind.theme,
        id: slug,
        label: visualFor(slug).label,
        emoji: _themeEmoji(slug),
        accent: visualFor(slug).accent,
      );
      if (tabOrder.contains(tourneeThemeKey(slug))) {
        flanerThemeItems.add(item);
      } else {
        essentielThemeItems.add(item);
      }
    }
    final essentielSourceItems = <_FavItem>[];
    final flanerSourceItems = <_FavItem>[];
    for (final f in sourceFavorites) {
      final source = sourceById[f.sourceId];
      if (source == null) continue;
      final item = _FavItem(
        key: tourneeSourceKey(f.sourceId),
        kind: _FavKind.source,
        id: f.sourceId,
        label: source.name,
        accent: sourceAccentFor(f.sourceId),
        source: source,
      );
      if (tournee.sourceIsEssentiel(f.sourceId)) {
        essentielSourceItems.add(item);
      } else {
        flanerSourceItems.add(item);
      }
    }
    final veilleItem = veilleCfg == null
        ? null
        : _FavItem(
            key: kTourneeVeilleKey,
            kind: _FavKind.veille,
            id: veilleCfg.id,
            label: 'Ma veille — ${veilleCfg.sectionLabel}',
            emoji: '🔭',
            accent: _kVeilleAccent,
          );

    final useSereneDefault = isSerene && !tournee.customized;
    // La Grille n'est plus un bloc drag&drop autonome : elle reste collée aux
    // Actus (cf. `_orderedTourneeKeys` côté provider), donc absente d'ici.
    final essentielDefault = useSereneDefault
        ? <_FavItem>[
            bonnesItem,
            ...essentielThemeItems,
            ...essentielSourceItems,
            if (veilleItem != null) veilleItem,
            actusItem,
          ]
        : <_FavItem>[
            actusItem,
            ...essentielThemeItems,
            ...essentielSourceItems,
            if (veilleItem != null) veilleItem,
            bonnesItem,
          ];
    final essentielVisible = [
      for (final item in essentielDefault)
        if (!tournee.hiddenKeys.contains(item.key)) item,
    ];
    final essentielOrdered = applyOrder(
      essentielVisible,
      tournee.order,
      (e) => e.key,
    );

    // ── Items Flâner (sujets + sources mode-Flâner) ────────────────────────
    final subjectItems = <_FavItem>[
      for (final t in customTopics)
        if (favoriteTopicIds.contains(t.id))
          _FavItem(
            key: tabOrderTopicKey(t.id),
            kind: _FavKind.subject,
            id: t.id,
            label: t.topicName,
            emoji: _themeEmoji(t.slugParent),
            accent: colors.primary,
          ),
    ];
    final flanerItems = [
      ...subjectItems,
      ...flanerThemeItems,
      ...flanerSourceItems,
    ];
    final flanerOrdered = applyOrder(flanerItems, tabOrder, (e) => e.key);

    // ── AJOUTER : candidats ────────────────────────────────────────────────
    final favSourceIds = sourceFavorites.map((f) => f.sourceId).toSet();
    final followedSources = [
      for (final s in catalog)
        if (sourcesState != null &&
            sourcesState.stateOf(s.id) == InterestState.followed &&
            !favSourceIds.contains(s.id))
          s,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final favThemeSlugs = favoriteThemeSlugs.toSet();
    final addableThemes = [
      for (final t in kVeilleFacteurThemes)
        if (!favThemeSlugs.contains(t.slug)) t,
    ];
    final pinnableTopics =
        [
          for (final t in customTopics)
            if (!favoriteTopicIds.contains(t.id)) t,
        ]..sort(
          (a, b) =>
              a.topicName.toLowerCase().compareTo(b.topicName.toLowerCase()),
        );

    final hiddenEditorialItems = <_FavItem>[
      if (tournee.hiddenKeys.contains(kTourneeActusKey)) actusItem,
      if (tournee.hiddenKeys.contains(kTourneeBonnesKey)) bonnesItem,
    ];
    final canAddVeille =
        veilleCfg != null && tournee.hiddenKeys.contains(kTourneeVeilleKey);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header fixe : handle cosmétique centré + bouton de fermeture
              // explicite (chemin garanti 1 tap, le SingleChildScrollView
              // interne capturant sinon le drag-to-dismiss natif).
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: colors.textTertiary),
                      tooltip: 'Fermer',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FacteurSpacing.space2),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                Text(
                  'Mes favoris',
                  style: textTheme.displaySmall?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Range chaque favori dans un mode : chaque matin dans ton '
                  'Essentiel, ou en continu dans tes onglets Flâner.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space4),

                // ── Section ESSENTIEL ───────────────────────────────────────
                _SectionLabel(
                  label: 'BLOCS DE TA PAGE L\'ESSENTIEL',
                  counter:
                      '${essentielOrdered.length.clamp(0, kTourneeVisibleCap)}'
                      '/$kTourneeVisibleCap',
                  accent: _kEssentielAccent,
                  colors: colors,
                ),
                const SizedBox(height: 8),
                if (essentielOrdered.isEmpty)
                  _EmptyHint(
                    label: 'Vide. Ajoute des thèmes ou des sources ci-dessous.',
                    colors: colors,
                  )
                else
                  _FavList(
                    items: essentielOrdered,
                    colors: colors,
                    cap: kTourneeVisibleCap,
                    capLabel: 'Hors Tournée du jour ($kTourneeVisibleCap)',
                    thinKeys: thinKeys,
                    // Destination du déplacement = Flâner ⇒ puces brun Flâner.
                    moveAccent: _kFlanerAccent,
                    onReorder: (oldIndex, newIndex) {
                      final reordered = [...essentielOrdered];
                      if (newIndex > oldIndex) newIndex -= 1;
                      reordered.insert(newIndex, reordered.removeAt(oldIndex));
                      _persistEssentielReorder(reordered);
                    },
                    onRemove: _onRemove,
                    moveIcon: PhosphorIcons.arrowLineDown(
                      PhosphorIconsStyle.bold,
                    ),
                    moveTooltip: 'Déplacer vers Flâner',
                    moveLabel: 'Flâner',
                    onMove: (item) => item.kind == _FavKind.theme
                        ? _moveThemeToFlaner(item.id)
                        : _moveSourceToFlaner(item.id),
                  ),
                const SizedBox(height: FacteurSpacing.space4),

                // ── Section FLÂNER ──────────────────────────────────────────
                _SectionLabel(
                  key: _flanerSectionKey,
                  label: 'ONGLETS DE TA PAGE FLÂNER',
                  counter:
                      '${flanerOrdered.length.clamp(0, kMaxFavoriteTabs)}'
                      '/$kMaxFavoriteTabs',
                  accent: _kFlanerAccent,
                  colors: colors,
                ),
                const SizedBox(height: 8),
                if (flanerOrdered.isEmpty)
                  _EmptyHint(
                    label:
                        'Vide. Épingle des sujets ou des sources ci-dessous.',
                    colors: colors,
                  )
                else
                  _FavList(
                    items: flanerOrdered,
                    colors: colors,
                    cap: kMaxFavoriteTabs,
                    capLabel: 'Hors onglets ($kMaxFavoriteTabs)',
                    // Les favoris Flâner ne sont pas dans la Tournée → aucune clé
                    // ne matche, mais on garde le câblage uniforme.
                    thinKeys: thinKeys,
                    // Destination du déplacement = Essentiel ⇒ puces ocre.
                    moveAccent: _kEssentielAccent,
                    onReorder: (oldIndex, newIndex) {
                      final reordered = [...flanerOrdered];
                      if (newIndex > oldIndex) newIndex -= 1;
                      reordered.insert(newIndex, reordered.removeAt(oldIndex));
                      _persistFlanerReorder(reordered);
                    },
                    onRemove: _onRemove,
                    moveIcon: PhosphorIcons.arrowLineUp(
                      PhosphorIconsStyle.bold,
                    ),
                    moveTooltip: 'Déplacer vers l\'Essentiel',
                    moveLabel: 'Essentiel',
                    onMove: (item) => item.kind == _FavKind.theme
                        ? _moveThemeToEssentiel(item.id)
                        : _moveSourceToEssentiel(item.id),
                    onSubjectVeille: (item) => _openVeilleConfig(),
                  ),
                const SizedBox(height: FacteurSpacing.space4),

                // ── AJOUTER ─────────────────────────────────────────────────
                _SectionLabel(label: 'AJOUTER', colors: colors),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Sources')),
                      ButtonSegment(value: 1, label: Text('Thèmes')),
                      ButtonSegment(value: 2, label: Text('Sujets')),
                    ],
                    selected: {_addTab},
                    onSelectionChanged: (s) =>
                        setState(() => _addTab = s.first),
                  ),
                ),
                const SizedBox(height: 10),
                if (_addTab == 0)
                  _SourcesAddList(
                    sources: followedSources,
                    colors: colors,
                    onAdd: _onAddSource,
                  )
                else if (_addTab == 1)
                  _ThemesAddList(
                    themes: addableThemes,
                    colors: colors,
                    onAdd: _onAddTheme,
                  )
                else
                  _SubjectsAddList(
                    topics: pinnableTopics,
                    colors: colors,
                    onAdd: (id) async {
                      try {
                        await ref
                            .read(userInterestsProvider.notifier)
                            .setInterestState(
                              CustomTopicFavoriteRef(id: id),
                              InterestState.favorite,
                            );
                        await _appendTab(tabOrderTopicKey(id));
                      } catch (e) {
                        NotificationService.showError('Erreur : $e');
                      }
                    },
                    onCreate: () =>
                        EntityAddSheet.show(context, pinOnFollow: true),
                  ),

                if (hiddenEditorialItems.isNotEmpty) ...[
                  const SizedBox(height: FacteurSpacing.space3),
                  for (final item in hiddenEditorialItems)
                    _AddRow(
                      key: ValueKey('restore_${item.key}'),
                      leading: Text(
                        item.emoji,
                        style: const TextStyle(fontSize: 14),
                      ),
                      label: 'Réafficher ${item.label}',
                      colors: colors,
                      onTap: () => _onRestoreEditorial(item.key),
                    ),
                ],
                const SizedBox(height: FacteurSpacing.space3),
                if (canAddVeille)
                  _VeilleTile(
                    label: 'Ajouter ma veille — ${veilleCfg.sectionLabel}',
                    colors: colors,
                    onTap: _onAddVeille,
                  )
                else if (veilleCfg == null)
                  _VeilleTile(
                    label: 'Créer ta veille',
                    icon: PhosphorIcons.binoculars(PhosphorIconsStyle.regular),
                    colors: colors,
                    onTap: _openVeilleConfig,
                  ),

                // ── GÉRER ───────────────────────────────────────────────────
                const SizedBox(height: FacteurSpacing.space4),
                _SectionLabel(label: 'GÉRER', colors: colors),
                const SizedBox(height: 4),
                // Story 22.3 — switch discret « Suggestions du facteur » : active
                // ou non les sections « Choisie pour vous » de la Tournée.
                const _SmartArrangementSwitch(),
                ChoiceTile(
                  icon: Icons.rss_feed,
                  accent: colors.sectionVeille1,
                  title: 'Gérer ses sources',
                  subtitle: 'Suis ou masque les médias qui te parlent.',
                  onTap: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.pushNamed(RouteNames.sources);
                  },
                ),
                ChoiceTile(
                  icon: Icons.favorite_outline,
                  accent: colors.sectionEssentiel,
                  title: 'Gérer ses intérêts',
                  subtitle: 'Choisis les thèmes qui guident ta Tournée.',
                  onTap: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.pushNamed(RouteNames.myInterests);
                  },
                ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Liste réordonnable d'une section, avec trait de cap après [cap] éléments.
class _FavList extends StatelessWidget {
  final List<_FavItem> items;
  final FacteurColors colors;
  final int cap;
  final String capLabel;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(_FavItem item) onRemove;
  final IconData moveIcon;
  final String moveTooltip;
  final String moveLabel;

  /// Couleur de la puce de déplacement = identité du **mode de destination**
  /// (brun Flâner / ocre Essentiel), pas la couleur de la carte (cf. [_MoveChip]).
  final Color moveAccent;
  final void Function(_FavItem item) onMove;
  final void Function(_FavItem item)? onSubjectVeille;

  /// Clés favorites maigres (Tournée) → micro-indicateur « Peu d'articles ».
  final Set<String> thinKeys;

  const _FavList({
    required this.items,
    required this.colors,
    required this.cap,
    required this.capLabel,
    required this.onReorder,
    required this.onRemove,
    required this.moveIcon,
    required this.moveTooltip,
    required this.moveLabel,
    required this.moveAccent,
    required this.onMove,
    this.thinKeys = const {},
    this.onSubjectVeille,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) =>
          _DragProxy(animation: animation, child: child),
      // Vibration au « soulèvement » (cohérent cartes) + dépôt discret.
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderEnd: (_) => HapticFeedback.selectionClick(),
      itemCount: items.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final item = items[index];
        final dimmed = index >= cap;
        return Column(
          key: ValueKey('${item.kind.name}_${item.key}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index == cap) _CapDivider(colors: colors, label: capLabel),
            _FavRow(
              item: item,
              index: index,
              dimmed: dimmed,
              colors: colors,
              thin: thinKeys.contains(item.key),
              moveIcon: moveIcon,
              moveTooltip: moveTooltip,
              moveLabel: moveLabel,
              moveAccent: moveAccent,
              onRemove: () => onRemove(item),
              onMove: () => onMove(item),
              onSubjectVeille: onSubjectVeille == null
                  ? null
                  : () => onSubjectVeille!(item),
            ),
          ],
        );
      },
    );
  }
}

/// Décorateur de drag : « soulève » l'élément (léger scale + ombre douce qui
/// apparaît progressivement) pour un feedback visuel subtil et élégant.
class _DragProxy extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _DragProxy({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(animation.value.clamp(0.0, 1.0));
        return Transform.scale(
          scale: 1 + 0.03 * t,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              // L'ombre épouse le radius de la tuile _FavRow (12) ; le padding
              // bas (8) déjà présent dans _FavRow reste transparent.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18 * t),
                    blurRadius: 16 * t,
                    offset: Offset(0, 4 * t),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _FavRow extends StatelessWidget {
  final _FavItem item;
  final int index;
  final bool dimmed;
  final FacteurColors colors;

  /// Cohérence Tournée — ce favori a peu d'articles aujourd'hui (≤1 survivant
  /// post-dédup) → micro-indicateur ambre près du libellé.
  final bool thin;
  final IconData moveIcon;
  final String moveTooltip;
  final String moveLabel;
  final Color moveAccent;
  final VoidCallback onRemove;
  final VoidCallback onMove;
  final VoidCallback? onSubjectVeille;

  const _FavRow({
    required this.item,
    required this.index,
    required this.dimmed,
    required this.colors,
    required this.moveIcon,
    required this.moveTooltip,
    required this.moveLabel,
    required this.moveAccent,
    required this.onRemove,
    required this.onMove,
    this.thin = false,
    this.onSubjectVeille,
  });

  @override
  Widget build(BuildContext context) {
    final isSource = item.kind == _FavKind.source;
    final isSubject = item.kind == _FavKind.subject;
    final isTheme = item.kind == _FavKind.theme;
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: item.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: item.accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              // Hit zone : toute la zone logo + label initie le drag (en plus
              // de la poignée), ce qui agrandit nettement la cible tactile.
              Expanded(
                child: ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    // color transparent → la ligne entière (gaps inclus) reste
                    // hit-testable pour démarrer le drag.
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        if (isSource && item.source != null)
                          SourceLogoAvatar(
                            source: item.source!,
                            size: 28,
                            radius: 6,
                          )
                        else
                          Text(
                            item.emoji,
                            style: const TextStyle(fontSize: 16),
                          ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (thin) ...[
                          const SizedBox(width: 6),
                          const _ThinBadge(),
                        ],
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Sujet : funnel veille (« chaque jour ? » → flow Veille).
              if (isSubject && onSubjectVeille != null)
                _RowIconButton(
                  icon: PhosphorIcons.binoculars(PhosphorIconsStyle.regular),
                  tooltip: 'Le suivre chaque jour ?',
                  color: _kVeilleAccent,
                  onTap: onSubjectVeille!,
                ),
              // Source ou thème : déplacement de mode (Essentiel ⇄ Flâner).
              // Puce lisible (icône directionnelle + destination) — bien plus
              // découvrable que l'ancienne flèche seule.
              if (isSource || isTheme)
                _MoveChip(
                  icon: moveIcon,
                  label: moveLabel,
                  tooltip: moveTooltip,
                  // Couleur du mode de destination (Flâner brun / Essentiel
                  // ocre), pas celle de la carte : « Flâner » devient
                  // reconnaissable à sa teinte.
                  accent: moveAccent,
                  onTap: onMove,
                ),
              _RowIconButton(
                icon: PhosphorIcons.minusCircle(PhosphorIconsStyle.fill),
                tooltip: 'Retirer',
                color: colors.textTertiary,
                onTap: onRemove,
              ),
              const SizedBox(width: 2),
              // Poignée explicite — affordance visuelle ; cible tactile ≥44px.
              // Container(color) = ColoredBox (hit opaque) → toute la zone 44px
              // démarre le drag, pas seulement le glyphe 18px.
              ReorderableDragStartListener(
                index: index,
                child: Container(
                  width: 44,
                  height: 44,
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: Icon(
                    PhosphorIcons.dotsSixVertical(PhosphorIconsStyle.bold),
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Micro-indicateur « Peu d'articles » d'un favori maigre (≤1 survivant
/// post-dédup ce jour). Pilule ambre discrète réutilisant le style des badges
/// existants (cf. `_SuggestedBadge`/`_MoveChip`). Signale dans la modal les
/// favoris peu fournis — surtout visibles dans la zone « Hors Tournée du jour ».
class _ThinBadge extends StatelessWidget {
  const _ThinBadge();

  // Ambre : aligné sur les tons d'avertissement doux de l'app.
  static const Color _amber = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Peu d\'articles aujourd\'hui',
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
        decoration: BoxDecoration(
          color: _amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _amber.withValues(alpha: 0.30), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.warningCircle(PhosphorIconsStyle.fill),
              size: 11,
              color: _amber,
            ),
            const SizedBox(width: 4),
            const Text(
              'Peu d\'articles',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color: _amber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Puce de passage de mode (Essentiel ⇄ Flâner) pour sources et thèmes :
/// icône directionnelle + libellé de destination, accentuée et lisible. Cible
/// tactile ≥ 44px, haptique conservée. Remplace l'ancienne flèche seule peu
/// découvrable.
class _MoveChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color accent;
  final VoidCallback onTap;

  const _MoveChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Trait de cap séparant les éléments visibles du surplus grisé.
class _CapDivider extends StatelessWidget {
  final FacteurColors colors;
  final String label;

  const _CapDivider({required this.colors, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Row(
        children: [
          Expanded(child: Divider(color: colors.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: colors.textTertiary,
              ),
            ),
          ),
          Expanded(child: Divider(color: colors.border, height: 1)),
        ],
      ),
    );
  }
}

class _SourcesAddList extends StatelessWidget {
  final List<Source> sources;
  final FacteurColors colors;
  final ValueChanged<String> onAdd;

  const _SourcesAddList({
    required this.sources,
    required this.colors,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return _EmptyHint(
        label: 'Aucune source suivie à ajouter.',
        colors: colors,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in sources)
          _AddRow(
            key: ValueKey('add_source_${s.id}'),
            leading: SourceLogoAvatar(source: s, size: 28, radius: 6),
            label: s.name,
            colors: colors,
            onTap: () => onAdd(s.id),
          ),
      ],
    );
  }
}

class _ThemesAddList extends StatelessWidget {
  final List<({String slug, String label, String emoji})> themes;
  final FacteurColors colors;
  final ValueChanged<String> onAdd;

  const _ThemesAddList({
    required this.themes,
    required this.colors,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    if (themes.isEmpty) {
      return _EmptyHint(
        label: 'Tous les thèmes sont déjà dans ton Essentiel.',
        colors: colors,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in themes)
          _AddRow(
            key: ValueKey('add_theme_${t.slug}'),
            leading: Text(t.emoji, style: const TextStyle(fontSize: 14)),
            label: t.label,
            colors: colors,
            onTap: () => onAdd(t.slug),
          ),
      ],
    );
  }
}

class _SubjectsAddList extends StatelessWidget {
  final List<CustomTopicInterest> topics;
  final FacteurColors colors;
  final ValueChanged<String> onAdd;
  final VoidCallback onCreate;

  const _SubjectsAddList({
    required this.topics,
    required this.colors,
    required this.onAdd,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (topics.isEmpty)
          _EmptyHint(
            label: 'Aucun sujet suivi à épingler. Crée-en un ci-dessous.',
            colors: colors,
          )
        else
          for (final t in topics)
            _AddRow(
              key: ValueKey('add_topic_${t.id}'),
              leading: Text(
                _themeEmoji(t.slugParent),
                style: const TextStyle(fontSize: 14),
              ),
              label: t.topicName,
              colors: colors,
              onTap: () => onAdd(t.id),
            ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onCreate,
            icon: Icon(
              PhosphorIcons.plus(PhosphorIconsStyle.bold),
              size: 14,
              color: colors.primary,
            ),
            label: Text(
              'Créer un sujet',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _AddRow({
    super.key,
    required this.leading,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  PhosphorIcons.plus(PhosphorIconsStyle.bold),
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VeilleTile extends StatelessWidget {
  final String label;
  final IconData? icon;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _VeilleTile({
    required this.label,
    required this.colors,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _kVeilleAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kVeilleAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                icon ?? PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 16,
                color: _kVeilleAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  /// Compteur discret affiché en suffixe (ex. « · 5/10 ») rappelant le cap de
  /// la section. `null` → pas de compteur (ex. en-têtes AJOUTER / GÉRER).
  final String? counter;

  /// Teinte d'identité de la section (ocre Essentiel / brun Flâner). `null` →
  /// gris tertiaire neutre (en-têtes AJOUTER / GÉRER). Renforce le code couleur
  /// des puces de déplacement (cf. [_MoveChip]).
  final Color? accent;
  final FacteurColors colors;

  const _SectionLabel({
    super.key,
    required this.label,
    required this.colors,
    this.counter,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: accent ?? colors.textTertiary,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
    if (counter == null) return Text(label, style: labelStyle);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: Text(label, style: labelStyle)),
        const SizedBox(width: 6),
        Text(
          '· $counter',
          style: labelStyle?.copyWith(
            letterSpacing: 0.2,
            color: accent?.withValues(alpha: 0.7) ?? colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Story 22.3 — switch discret « Suggestions du facteur » : active/désactive
/// les sections « Choisie pour vous » de la Tournée (préférence serveur
/// `tournee_smart_arrangement`, default-ON). Calqué sur [ChoiceTile].
class _SmartArrangementSwitch extends ConsumerWidget {
  const _SmartArrangementSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(tourneeSmartArrangementProvider);
    final accent = colors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: Icon(
              PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggestions du facteur',
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Complète ta Tournée avec des thèmes et sources que tu suis.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: state.enabled,
            onChanged: state.isLoading
                ? null
                : (_) => ref
                    .read(tourneeSmartArrangementProvider.notifier)
                    .toggle(),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String label;
  final FacteurColors colors;

  const _EmptyHint({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: TextStyle(color: colors.textTertiary, fontSize: 13, height: 1.4),
      ),
    );
  }
}
