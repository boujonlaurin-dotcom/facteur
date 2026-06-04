import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/models/user_sources_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../my_interests/repositories/user_interests_repository.dart'
    show FavoriteCapReachedException;
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../../veille/providers/veille_active_config_provider.dart';
import '../../veille/providers/veille_themes_provider.dart';
import '../providers/tournee_order_prefs_provider.dart';
import '../utils/theme_color_mapping.dart';

/// Plafond d'affichage de la Tournée. Au-delà, les sections passent sous le
/// trait « Hors Tournée du jour » (décision PO — cap d'affichage, pas cap
/// serveur : on garde 3 thèmes + 3 sources possibles).
const int kTourneeVisibleCap = 5;

/// Accent de la veille dans la composition (aligné sur `_kVeilleAccent` du
/// provider Tournée / `FacteurColors.sectionVeille1`).
const Color _kVeilleAccent = Color(0xFF2C3E50);

/// Ouvre « Composer ma Tournée » — la modale unifiée d'ordre & de gestion des
/// sections de la Tournée du jour (thèmes + sources + veille, cap 5, ordre
/// libre). Remplace les anciennes sections « Favoris » de Mes intérêts / Mes
/// sources et l'ancienne sheet décorative des intérêts.
Future<void> showTourneeComposerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: const _TourneeComposerContent(),
      ),
    ),
  );
}

/// Bouton « Composer ma Tournée » — point d'entrée vers
/// [showTourneeComposerSheet]. Remplace les anciennes sections « Favoris »
/// inline de Mes intérêts / Mes sources.
class ComposeTourneeButton extends StatelessWidget {
  const ComposeTourneeButton({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            HapticFeedback.mediumImpact();
            showTourneeComposerSheet(context);
          },
          icon: Icon(
            PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.bold),
            size: 16,
            color: colors.primary,
          ),
          label: Text(
            'Composer ma Tournée',
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ItemKind { theme, source, veille }

/// Un élément de la Tournée dans la zone « MA TOURNÉE » : un thème, une source
/// ou la veille. La `key` est alignée sur `sectionKey()` (`theme:`/`source:`/
/// `veille`) pour que [applyOrder] colle au rendu et à la dédup du provider.
class _TourneeItem {
  final String key;
  final _ItemKind kind;
  final String id; // slug | sourceId | configId
  final String label;
  final String emoji; // pour un thème / la veille
  final Color accent;
  final Source? source; // pour une source

  const _TourneeItem({
    required this.key,
    required this.kind,
    required this.id,
    required this.label,
    required this.accent,
    this.emoji = '',
    this.source,
  });
}

/// Emoji du thème Facteur (fallback 📰 hors des 9 thèmes).
String _themeEmoji(String slug) {
  for (final t in kVeilleFacteurThemes) {
    if (t.slug == slug) return t.emoji;
  }
  return '📰';
}

class _TourneeComposerContent extends ConsumerStatefulWidget {
  const _TourneeComposerContent();

  @override
  ConsumerState<_TourneeComposerContent> createState() =>
      _TourneeComposerContentState();
}

class _TourneeComposerContentState
    extends ConsumerState<_TourneeComposerContent> {
  /// Onglet actif de la zone « AJOUTER » : 0 = Sources, 1 = Thèmes.
  int _addTab = 0;

  // ── Ordre + membership ────────────────────────────────────────────────────

  Future<void> _appendOrder(String key) async {
    final current = ref.read(tourneeOrderPrefsProvider).order;
    if (current.contains(key)) return;
    await ref
        .read(tourneeOrderPrefsProvider.notifier)
        .setOrder([...current, key]);
  }

  Future<void> _removeOrder(String key) async {
    final next = ref
        .read(tourneeOrderPrefsProvider)
        .order
        .where((k) => k != key)
        .toList();
    await ref.read(tourneeOrderPrefsProvider.notifier).setOrder(next);
  }

  Future<void> _onAddTheme(String slug) async {
    try {
      await ref.read(userInterestsProvider.notifier).setInterestState(
            ThemeFavoriteRef(slug: slug),
            InterestState.favorite,
          );
      await _appendOrder(tourneeThemeKey(slug));
    } on FavoriteCapReachedException catch (e) {
      NotificationService.showError(
        'Tu as déjà ${e.cap} favoris. Retires-en un avant d\'en ajouter.',
      );
    } catch (e) {
      NotificationService.showError('Erreur : $e');
    }
  }

  Future<void> _onAddSource(String sourceId) async {
    try {
      await ref
          .read(userSourcesStateProvider.notifier)
          .setSourceState(sourceId, InterestState.favorite);
      await _appendOrder(tourneeSourceKey(sourceId));
    } on FavoriteCapReachedException catch (e) {
      NotificationService.showError(
        'Tu as déjà ${e.cap} sources favorites. Retires-en une d\'abord.',
      );
    } catch (e) {
      NotificationService.showError('Erreur : $e');
    }
  }

  Future<void> _onAddVeille() async {
    await ref.read(tourneeOrderPrefsProvider.notifier).setVeilleHidden(false);
    await _appendOrder(kTourneeVeilleKey);
  }

  Future<void> _onRemove(_TourneeItem item) async {
    // Retire d'abord la clé d'ordre (optimiste, sans risque), puis dé-favorise.
    await _removeOrder(item.key);
    switch (item.kind) {
      case _ItemKind.theme:
        try {
          await ref.read(userInterestsProvider.notifier).setInterestState(
                ThemeFavoriteRef(slug: item.id),
                InterestState.followed,
              );
        } catch (e) {
          NotificationService.showError('Erreur : $e');
        }
      case _ItemKind.source:
        try {
          await ref
              .read(userSourcesStateProvider.notifier)
              .setSourceState(item.id, InterestState.followed);
        } catch (e) {
          NotificationService.showError('Erreur : $e');
        }
      case _ItemKind.veille:
        // Décision PO : « masquer » (config conservée + self-heal désactivé),
        // pas d'archive backend. Ré-ajoutable via la tuile veille.
        await ref
            .read(tourneeOrderPrefsProvider.notifier)
            .setVeilleHidden(true);
    }
  }

  /// Persiste le nouvel ordre (prefs) puis synchronise — best-effort, en
  /// parallèle — les positions serveur par type pour garder « Mes intérêts » /
  /// « Mes sources » cohérents. Miroir de `pin_subjects_sheet._persistReorder`.
  Future<void> _persistReorder(List<_TourneeItem> ordered) async {
    await ref
        .read(tourneeOrderPrefsProvider.notifier)
        .setOrder(ordered.map((e) => e.key).toList());

    final themeRefs = <FavoriteRef>[
      for (final e in ordered)
        if (e.kind == _ItemKind.theme) ThemeFavoriteRef(slug: e.id),
    ];
    final sourceIds = <String>[
      for (final e in ordered)
        if (e.kind == _ItemKind.source) e.id,
    ];

    await Future.wait([
      _syncInterestPositions(themeRefs),
      _syncSourcePositions(sourceIds),
    ]);
  }

  /// Réordonne uniquement les `ThemeFavoriteRef` serveur selon [themeRefs] en
  /// préservant la position des veille/custom-topics (hors Tournée).
  Future<void> _syncInterestPositions(List<FavoriteRef> themeRefs) async {
    final interests = ref.read(userInterestsProvider).valueOrNull;
    if (interests == null) return;
    final themeSlots =
        interests.favorites.whereType<ThemeFavoriteRef>().length;
    if (themeRefs.length != themeSlots) return;
    var i = 0;
    final merged = [
      for (final f in interests.favorites)
        f is ThemeFavoriteRef ? themeRefs[i++] : f,
    ];
    try {
      await ref.read(userInterestsProvider.notifier).reorderFavorites(merged);
    } catch (_) {
      // best-effort : l'ordre prefs reste appliqué.
    }
  }

  /// Réassigne les positions canoniques des sources favorites selon [sourceIds].
  Future<void> _syncSourcePositions(List<String> sourceIds) async {
    if (sourceIds.isEmpty) return;
    final orderedRefs = [
      for (var i = 0; i < sourceIds.length; i++)
        SourceFavoriteRef(sourceId: sourceIds[i], position: i),
    ];
    try {
      await ref
          .read(userSourcesStateProvider.notifier)
          .reorderFavorites(orderedRefs);
    } catch (_) {
      // idem : best-effort.
    }
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

    // ── MA TOURNÉE — membership (thèmes favoris + sources favorites + veille) ─
    final favoriteThemeSlugs = <String>[
      for (final f in interests?.favorites ?? const <FavoriteRef>[])
        if (f is ThemeFavoriteRef) f.slug,
    ];
    final sourceFavorites = [...(sourcesState?.favorites ?? const [])]
      ..sort((a, b) => a.position.compareTo(b.position));

    final items = <_TourneeItem>[];
    for (final slug in favoriteThemeSlugs) {
      final v = visualFor(slug);
      items.add(_TourneeItem(
        key: tourneeThemeKey(slug),
        kind: _ItemKind.theme,
        id: slug,
        label: v.label,
        emoji: _themeEmoji(slug),
        accent: v.accent,
      ));
    }
    for (final f in sourceFavorites) {
      final source = sourceById[f.sourceId];
      if (source == null) continue;
      items.add(_TourneeItem(
        key: tourneeSourceKey(f.sourceId),
        kind: _ItemKind.source,
        id: f.sourceId,
        label: source.name,
        accent: sourceAccentFor(f.sourceId),
        source: source,
      ));
    }
    final showVeilleInTournee = veilleCfg != null && !tournee.veilleHidden;
    if (showVeilleInTournee) {
      items.add(_TourneeItem(
        key: kTourneeVeilleKey,
        kind: _ItemKind.veille,
        id: veilleCfg.id,
        label: 'Ma veille — ${veilleCfg.themeLabel}',
        emoji: '🔭',
        accent: _kVeilleAccent,
      ));
    }
    final orderedItems = applyOrder(items, tournee.order, (e) => e.key);

    // ── AJOUTER — candidats non encore dans la Tournée ────────────────────────
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

    // Caps serveur (Option A) — désactivation proactive + message.
    final interestsAtCap = interests != null &&
        interests.favoriteCount >= interests.favoriteCap;
    final sourcesAtCap = sourcesState != null &&
        sourcesState.favorites.length >= sourcesState.favoriteCap;

    final canAddVeille = veilleCfg != null &&
        (tournee.veilleHidden || !items.any((e) => e.kind == _ItemKind.veille));

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space4),
                Text(
                  'Composer ma Tournée',
                  style: textTheme.displaySmall?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mélange thèmes, sources et veille, dans l\'ordre que tu veux. '
                  'Les 5 premiers composent ta Tournée du jour.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space4),

                // ── MA TOURNÉE ──────────────────────────────────────────────
                _SectionLabel(label: 'MA TOURNÉE', colors: colors),
                const SizedBox(height: 8),
                if (orderedItems.isEmpty)
                  _EmptyHint(
                    label:
                        'Ta Tournée est vide. Ajoute des thèmes ou des sources '
                        'ci-dessous.',
                    colors: colors,
                  )
                else
                  _TourneeList(
                    items: orderedItems,
                    colors: colors,
                    onReorder: (oldIndex, newIndex) {
                      final reordered = [...orderedItems];
                      if (newIndex > oldIndex) newIndex -= 1;
                      final moved = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, moved);
                      _persistReorder(reordered);
                    },
                    onRemove: _onRemove,
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
                    atCap: sourcesAtCap,
                    colors: colors,
                    onAdd: _onAddSource,
                  )
                else
                  _ThemesAddList(
                    themes: addableThemes,
                    atCap: interestsAtCap,
                    colors: colors,
                    onAdd: _onAddTheme,
                  ),

                const SizedBox(height: FacteurSpacing.space3),
                if (canAddVeille)
                  _VeilleTile(
                    label: 'Ajouter ma veille — ${veilleCfg.themeLabel}',
                    colors: colors,
                    onTap: _onAddVeille,
                  )
                else if (veilleCfg == null)
                  _VeilleTile(
                    label: 'Créer ta veille',
                    icon: PhosphorIcons.binoculars(PhosphorIconsStyle.regular),
                    colors: colors,
                    onTap: () {
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.pushNamed(RouteNames.veilleConfig);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Liste réordonnable de la Tournée, avec un trait « Hors Tournée du jour »
/// inséré après le 5ᵉ élément. Les éléments sous le trait sont grisés (ils ne
/// s'affichent pas dans la Tournée tant qu'ils restent au-delà du cap).
class _TourneeList extends StatelessWidget {
  final List<_TourneeItem> items;
  final FacteurColors colors;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(_TourneeItem item) onRemove;

  const _TourneeList({
    required this.items,
    required this.colors,
    required this.onReorder,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final item = items[index];
        final dimmed = index >= kTourneeVisibleCap;
        return Column(
          key: ValueKey(item.key),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index == kTourneeVisibleCap)
              _CapDivider(colors: colors),
            _TourneeRow(
              item: item,
              index: index,
              dimmed: dimmed,
              colors: colors,
              onRemove: () => onRemove(item),
            ),
          ],
        );
      },
    );
  }
}

class _TourneeRow extends StatelessWidget {
  final _TourneeItem item;
  final int index;
  final bool dimmed;
  final FacteurColors colors;
  final VoidCallback onRemove;

  const _TourneeRow({
    required this.item,
    required this.index,
    required this.dimmed,
    required this.colors,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
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
              if (item.kind == _ItemKind.source && item.source != null)
                SourceLogoAvatar(source: item.source!, size: 28, radius: 6)
              else
                Text(item.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
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
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onRemove();
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    PhosphorIcons.minusCircle(PhosphorIconsStyle.fill),
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(4),
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

/// Trait « Hors Tournée du jour » séparant les 5 sections visibles du surplus.
class _CapDivider extends StatelessWidget {
  final FacteurColors colors;

  const _CapDivider({required this.colors});

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
              'Hors Tournée du jour',
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
  final bool atCap;
  final FacteurColors colors;
  final ValueChanged<String> onAdd;

  const _SourcesAddList({
    required this.sources,
    required this.atCap,
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
        if (atCap)
          _CapHint(label: 'Maximum de sources favorites atteint.', colors: colors),
        for (final s in sources)
          _AddRow(
            key: ValueKey('add_source_${s.id}'),
            leading: SourceLogoAvatar(source: s, size: 28, radius: 6),
            label: s.name,
            disabled: atCap,
            colors: colors,
            onTap: () => onAdd(s.id),
          ),
      ],
    );
  }
}

class _ThemesAddList extends StatelessWidget {
  final List<({String slug, String label, String emoji})> themes;
  final bool atCap;
  final FacteurColors colors;
  final ValueChanged<String> onAdd;

  const _ThemesAddList({
    required this.themes,
    required this.atCap,
    required this.colors,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    if (themes.isEmpty) {
      return _EmptyHint(
        label: 'Tous les thèmes sont déjà dans ta Tournée.',
        colors: colors,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (atCap)
          _CapHint(label: 'Maximum de favoris atteint.', colors: colors),
        for (final t in themes)
          _AddRow(
            key: ValueKey('add_theme_${t.slug}'),
            leading: Text(t.emoji, style: const TextStyle(fontSize: 14)),
            label: t.label,
            disabled: atCap,
            colors: colors,
            onTap: () => onAdd(t.slug),
          ),
      ],
    );
  }
}

class _AddRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final bool disabled;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _AddRow({
    super.key,
    required this.leading,
    required this.label,
    required this.disabled,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: disabled
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
  final FacteurColors colors;

  const _SectionLabel({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.textTertiary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
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

class _CapHint extends StatelessWidget {
  final String label;
  final FacteurColors colors;

  const _CapHint({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
