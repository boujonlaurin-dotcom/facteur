/// Story 22.1 — écran « Mes intérêts » refondu sur le modèle 4-états.
///
/// Provider canonique : `userInterestsProvider`. La sheet Serein continue à
/// utiliser `customTopicsProvider` pour le toggle `excludedFromSerein` car ces
/// concepts sont orthogonaux à l'état 4-états (un Sujet peut être `followed` mais
/// exclu du Mode Serein, et inversement).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/serein_colors.dart';
import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../shared/widgets/fab_nudge_bubble.dart';
import '../../../shared/widgets/states/friendly_error_view.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../custom_topics/providers/personalization_provider.dart';
import '../../custom_topics/widgets/entity_add_sheet.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../feed/repositories/personalization_repository.dart';
import '../../veille/providers/veille_active_config_provider.dart';
import '../../veille/providers/veille_repository_provider.dart';
import '../models/user_interests_state.dart';
import '../providers/user_interests_provider.dart';
import '../widgets/favorites_reorderable_section.dart';
import '../widgets/interest_state_picker_sheet.dart';

const Map<String, String> _apiSlugToMacroLabel = {
  'tech': 'Technologie',
  'science': 'Sciences',
  'society': 'Société',
  'politics': 'Politique',
  'economy': 'Économie',
  'environment': 'Environnement',
  'culture': 'Culture',
  'international': 'Géopolitique',
  'sport': 'Sport',
};

class MyInterestsScreen extends ConsumerStatefulWidget {
  /// Si défini, force le toggle Serein sur ON à l'arrivée (CTA onboarding).
  final bool forceSereinOn;

  const MyInterestsScreen({super.key, this.forceSereinOn = false});

  @override
  ConsumerState<MyInterestsScreen> createState() => _MyInterestsScreenState();
}

class _MyInterestsScreenState extends ConsumerState<MyInterestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.forceSereinOn && !ref.read(sereinToggleProvider).enabled) {
        ref.read(sereinToggleProvider.notifier).setEnabledLocal(true);
      }
    });
  }

  void _handleBack() {
    if (widget.forceSereinOn) {
      context.goNamed(RouteNames.onboarding);
    } else if (context.canPop()) {
      context.pop();
    }
  }

  Future<void> _pickState({
    required String title,
    required FavoriteRef refTarget,
    required InterestState currentState,
  }) async {
    final selected = await InterestStatePickerSheet.show(
      context,
      title: title,
      currentState: currentState,
      allowFavorite: refTarget is! CustomTopicFavoriteRef,
    );
    if (selected == null || selected == currentState) return;

    try {
      await ref
          .read(userInterestsProvider.notifier)
          .setInterestState(refTarget, selected);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Impossible de mettre à jour cet intérêt.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Menu contextuel pour le favori veille — "Modifier" / "Archiver"
  /// (Story 23.2 PR-4). Pas de InterestStatePickerSheet car les états
  /// hidden/unfollowed/followed ne s'appliquent pas à la veille :
  /// elle est soit favorite, soit archivée (DELETE backend).
  Future<void> _showVeilleMenu(VeilleFavoriteRef refTarget) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(PhosphorIcons.pencilSimple()),
              title: const Text('Modifier la veille'),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            ListTile(
              leading: Icon(
                PhosphorIcons.archive(),
                color: Colors.red.shade700,
              ),
              title: Text(
                'Archiver',
                style: TextStyle(color: Colors.red.shade700),
              ),
              onTap: () => Navigator.of(sheetContext).pop('archive'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'edit') {
      context.pushNamed(
        RouteNames.veilleConfig,
        queryParameters: const {'mode': 'edit'},
      );
    } else if (choice == 'archive') {
      await _confirmAndArchive();
    }
  }

  Future<void> _confirmAndArchive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archiver la veille ?'),
        content: const Text(
          "Ta veille sera retirée de Mes intérêts et de ta Tournée. "
          'Tu pourras en créer une nouvelle à tout moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Archiver'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await ref.read(veilleRepositoryProvider).deleteConfig();
      // Refresh : la config active devient null, le favori veille disparaît
      // de la liste user_interests.
      ref.invalidate(veilleActiveConfigProvider);
      ref.invalidate(userInterestsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veille archivée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'archiver la veille.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final interestsAsync = ref.watch(userInterestsProvider);
    final sereinMode = ref.watch(sereinToggleProvider).enabled;

    return PopScope(
      canPop: !widget.forceSereinOn,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.forceSereinOn) {
          context.goNamed(RouteNames.onboarding);
        }
      },
      child: Scaffold(
        backgroundColor: colors.backgroundPrimary,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          title: const Text('Mes Intérêts'),
          backgroundColor: colors.backgroundPrimary,
          elevation: 0,
          titleTextStyle: textTheme.displaySmall,
        ),
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Flexible(
              child: FabNudgeBubble(
                text: 'Suivez vos sujets pour les booster',
                dismissKey: 'nudge_custom_topic_v1',
              ),
            ),
            const SizedBox(width: 6),
            FloatingActionButton.extended(
              onPressed: () => EntityAddSheet.show(context),
              backgroundColor: const Color(0xFFE07A5F),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Sujet personnalisé',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        body: interestsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => FriendlyErrorView(
            error: e,
            onRetry: () => ref.invalidate(userInterestsProvider),
          ),
          data: (interests) => _buildBody(
            context: context,
            interests: interests,
            sereinMode: sereinMode,
            colors: colors,
            textTheme: textTheme,
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required UserInterestsState interests,
    required bool sereinMode,
    required FacteurColors colors,
    required TextTheme textTheme,
  }) {
    final hiddenItems = <_HiddenEntry>[
      for (final t in interests.themes.where((t) => t.state == InterestState.hidden))
        _HiddenEntry.theme(slug: t.interestSlug),
      for (final c in interests.customTopics.where((c) => c.state == InterestState.hidden))
        _HiddenEntry.customTopic(id: c.id, name: c.topicName),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: FacteurSpacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroBlock(sereinMode: sereinMode),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FacteurSpacing.space4,
              0,
              FacteurSpacing.space4,
              FacteurSpacing.space3,
            ),
            child: _SereinToggleTile(
              enabled: sereinMode,
              onChanged: () =>
                  ref.read(sereinToggleProvider.notifier).toggle(),
            ),
          ),
          if (!sereinMode)
            FavoritesReorderableSection<FavoriteRef>(
              items: interests.favorites,
              keyOf: (ref) => ValueKey('${ref.kind}:${ref.targetId}'),
              itemBuilder: (context, refItem) => _FavoriteRow(
                refItem: refItem,
                interests: interests,
                onTap: () {
                  if (refItem is VeilleFavoriteRef) {
                    _showVeilleMenu(refItem);
                  } else {
                    _pickState(
                      title: _labelFor(refItem, interests),
                      refTarget: refItem,
                      currentState: InterestState.favorite,
                    );
                  }
                },
              ),
              onReorder: (reordered) async {
                try {
                  await ref
                      .read(userInterestsProvider.notifier)
                      .reorderFavorites(reordered);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Impossible de réordonner les favoris.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
            ),
          // CTA "Crée ta veille" — visible si aucun VeilleFavoriteRef dans
          // les favoris. La veille devient le 3ᵉ type de favori (Story 23.2 PR-4).
          if (!sereinMode &&
              interests.favorites.whereType<VeilleFavoriteRef>().isEmpty)
            _CreateVeilleCta(
              onTap: () => context.pushNamed(RouteNames.veilleConfig),
            ),
          ...macroThemeOrder.map((macroLabel) {
            final themeSlug = macroThemeToApiSlug[macroLabel] ?? macroLabel;
            return _ThemeBlock(
              macroLabel: macroLabel,
              themeSlug: themeSlug,
              interests: interests,
              sereinMode: sereinMode,
              onPickThemeState: (current) => _pickState(
                title: macroLabel,
                refTarget: ThemeFavoriteRef(slug: themeSlug),
                currentState: current,
              ),
              onPickTopicState: (topicId, name, current) => _pickState(
                title: name,
                refTarget: CustomTopicFavoriteRef(id: topicId),
                currentState: current,
              ),
            );
          }),
          if (hiddenItems.isNotEmpty && !sereinMode)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space4,
                vertical: FacteurSpacing.space2,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(FacteurRadius.large),
                  border: Border.all(color: colors.surfaceElevated),
                ),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space3,
                      vertical: FacteurSpacing.space2,
                    ),
                    leading: Icon(
                      PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
                      size: 18,
                      color: colors.textTertiary,
                    ),
                    title: Text(
                      'Masqués (${hiddenItems.length})',
                      style: textTheme.titleSmall?.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: hiddenItems
                        .map((entry) => _HiddenItemRow(
                              entry: entry,
                              onRestore: () => _pickState(
                                title: entry.displayName,
                                refTarget: entry.refTarget,
                                currentState: InterestState.hidden,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          if (!sereinMode) _ContentTypesSection(),
        ],
      ),
    );
  }

  String _labelFor(FavoriteRef ref, UserInterestsState interests) {
    return switch (ref) {
      ThemeFavoriteRef(:final slug) => _apiSlugToMacroLabel[slug] ?? slug,
      CustomTopicFavoriteRef(:final id) => interests.customTopics
              .where((c) => c.id == id)
              .map((c) => c.topicName)
              .firstOrNull ??
          'Sujet',
      VeilleFavoriteRef() => 'Ma veille',
    };
  }
}

class _HiddenEntry {
  final FavoriteRef refTarget;
  final String displayName;
  final bool isTheme;

  _HiddenEntry._(
      {required this.refTarget,
      required this.displayName,
      required this.isTheme});

  factory _HiddenEntry.theme({required String slug}) => _HiddenEntry._(
        refTarget: ThemeFavoriteRef(slug: slug),
        displayName: _apiSlugToMacroLabel[slug] ?? slug,
        isTheme: true,
      );

  factory _HiddenEntry.customTopic({required String id, required String name}) =>
      _HiddenEntry._(
        refTarget: CustomTopicFavoriteRef(id: id),
        displayName: name,
        isTheme: false,
      );
}

class _HeroBlock extends StatelessWidget {
  final bool sereinMode;
  const _HeroBlock({required this.sereinMode});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sereinMode ? 'Vos bonnes nouvelles' : 'Vos centres d\'intérêt',
            style: textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Text(
            sereinMode
                ? 'Choisissez ce qui reste dans vos bonnes nouvelles. Cochez pour garder, décochez pour mettre de côté.'
                : 'Étoilez vos favoris pour les voir en tête du flux. Les 3 premiers (ordre modifiable) constituent votre Tournée du jour.',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SereinToggleTile extends StatelessWidget {
  final bool enabled;
  final VoidCallback onChanged;

  const _SereinToggleTile({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final borderRadius = BorderRadius.circular(FacteurRadius.large);
    return Material(
      color: colors.surface,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onChanged,
        borderRadius: borderRadius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: colors.surfaceElevated),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space3,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SereinColors.sereinColor.withOpacity(0.12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  SereinColors.sereinIcon,
                  color: SereinColors.sereinColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mode Serein',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Une lecture plus calme, sans urgence',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeColor: SereinColors.sereinColor,
                onChanged: (_) => onChanged(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteRow extends StatelessWidget {
  final FavoriteRef refItem;
  final UserInterestsState interests;
  final VoidCallback onTap;

  const _FavoriteRow({
    required this.refItem,
    required this.interests,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final (label, emoji) = switch (refItem) {
      ThemeFavoriteRef(:final slug) => (
          _apiSlugToMacroLabel[slug] ?? slug,
          getMacroThemeEmoji(_apiSlugToMacroLabel[slug] ?? ''),
        ),
      CustomTopicFavoriteRef(:final id) => (
          interests.customTopics
                  .where((c) => c.id == id)
                  .map((c) => c.topicName)
                  .firstOrNull ??
              'Sujet',
          '',
        ),
      VeilleFavoriteRef() => ('Ma veille', ''),
    };

    final isVeille = refItem is VeilleFavoriteRef;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space2,
          vertical: FacteurSpacing.space2,
        ),
        child: Row(
          children: [
            Icon(
              isVeille
                  ? PhosphorIcons.binoculars(PhosphorIconsStyle.fill)
                  : PhosphorIcons.star(PhosphorIconsStyle.fill),
              color: isVeille ? colors.sectionVeille1 : colors.primary,
              size: 16,
            ),
            const SizedBox(width: 8),
            if (emoji.isNotEmpty) ...[
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isVeille) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.sectionVeille1.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'VEILLE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: colors.sectionVeille1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// CTA "Crée ta veille" — visible quand l'utilisateur n'a pas encore de
/// veille active dans ses favoris. Tap → flow de configuration (intro
/// puis 3-steps). Story 23.2 PR-4.
class _CreateVeilleCta extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateVeilleCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FacteurSpacing.space4,
        FacteurSpacing.space2,
        FacteurSpacing.space4,
        FacteurSpacing.space3,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        child: Container(
          padding: const EdgeInsets.all(FacteurSpacing.space3),
          decoration: BoxDecoration(
            color: colors.sectionVeille1.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(
              color: colors.sectionVeille1.withValues(alpha: 0.3),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.sectionVeille1.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIcons.binoculars(PhosphorIconsStyle.duotone),
                  color: colors.sectionVeille1,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Crée ta veille',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Un thème sur-mesure pour ta Tournée du jour',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
                size: 14,
                color: colors.sectionVeille1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeBlock extends ConsumerWidget {
  final String macroLabel;
  final String themeSlug;
  final UserInterestsState interests;
  final bool sereinMode;
  final Future<void> Function(InterestState current) onPickThemeState;
  final Future<void> Function(String topicId, String name, InterestState current)
      onPickTopicState;

  const _ThemeBlock({
    required this.macroLabel,
    required this.themeSlug,
    required this.interests,
    required this.sereinMode,
    required this.onPickThemeState,
    required this.onPickTopicState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final themeRow = interests.themes
        .where((t) => t.interestSlug == themeSlug)
        .firstOrNull;
    final themeState = themeRow?.state ?? InterestState.unfollowed;

    // slug_parent en DB est un slug fin (ex. 'cinema', 'ai', 'feminism'). On
    // remonte au macro-thème via getTopicMacroTheme() pour matcher le bloc
    // affiché. Avant : comparaison directe `slugParent == themeSlug` qui
    // masquait ~85% des sujets followed (PR #622).
    final topics = interests.customTopics
        .where((c) =>
            getTopicMacroTheme(c.slugParent) == macroLabel &&
            c.state != InterestState.hidden)
        .toList();

    // Hide the whole block in normal mode when there's nothing to show
    // (theme unfollowed + no topics) — keeps the screen compact.
    if (!sereinMode &&
        themeState == InterestState.unfollowed &&
        topics.isEmpty) {
      return _DiscoverHint(
        macroLabel: macroLabel,
        themeSlug: themeSlug,
        onPickThemeState: () => onPickThemeState(themeState),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space2,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(color: colors.surfaceElevated),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: themeState == InterestState.favorite,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: FacteurSpacing.space3,
              vertical: FacteurSpacing.space2,
            ),
            title: Row(
              children: [
                Text(getMacroThemeEmoji(macroLabel),
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    macroLabel,
                    style: textTheme.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (!sereinMode)
                  _StateChip(
                    state: themeState,
                    onTap: () => onPickThemeState(themeState),
                  ),
              ],
            ),
            children: [
              if (sereinMode)
                ...topics.map((topic) => _SereinTopicRow(topic: topic))
              else ...[
                ...topics.map(
                  (topic) => _TopicRow(
                    topic: topic,
                    onPickState: () =>
                        onPickTopicState(topic.id, topic.topicName, topic.state),
                  ),
                ),
                _AddTopicInlineButton(themeSlug: themeSlug),
              ],
              const SizedBox(height: FacteurSpacing.space2),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverHint extends StatelessWidget {
  final String macroLabel;
  final String themeSlug;
  final VoidCallback onPickThemeState;

  const _DiscoverHint({
    required this.macroLabel,
    required this.themeSlug,
    required this.onPickThemeState,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space1,
      ),
      child: InkWell(
        onTap: onPickThemeState,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space3,
            vertical: FacteurSpacing.space2,
          ),
          child: Row(
            children: [
              Text(getMacroThemeEmoji(macroLabel),
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  macroLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.regular),
                color: colors.textTertiary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTopicInlineButton extends StatelessWidget {
  final String themeSlug;

  const _AddTopicInlineButton({required this.themeSlug});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => EntityAddSheet.show(context, themeSlug: themeSlug),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space2,
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.plus(PhosphorIconsStyle.regular),
              size: 14,
              color: colors.textTertiary,
            ),
            const SizedBox(width: FacteurSpacing.space2),
            Text(
              'Ajouter un sujet',
              style: textTheme.bodySmall?.copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final CustomTopicInterest topic;
  final VoidCallback onPickState;

  const _TopicRow({required this.topic, required this.onPickState});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space2,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFE07A5F),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          Expanded(
            child: Text(
              topic.topicName,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _StateChip(
            state: topic.state,
            onTap: onPickState,
          ),
        ],
      ),
    );
  }
}

class _SereinTopicRow extends ConsumerWidget {
  final CustomTopicInterest topic;

  const _SereinTopicRow({required this.topic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final customTopicsAsync = ref.watch(customTopicsProvider);
    final legacyTopic = customTopicsAsync.value
        ?.where((t) => t.id == topic.id)
        .firstOrNull;
    final included = legacyTopic == null ? true : !legacyTopic.excludedFromSerein;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space1,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: included,
              onChanged: legacyTopic == null
                  ? null
                  : (v) async {
                      try {
                        await ref
                            .read(customTopicsProvider.notifier)
                            .setExcludedFromSerein(topic.id, !(v ?? false));
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Impossible de mettre à jour ce sujet.'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          Expanded(
            child: Text(
              topic.topicName,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final InterestState state;
  final VoidCallback onTap;

  const _StateChip({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final (icon, color, label) = switch (state) {
      InterestState.favorite => (
          PhosphorIcons.star(PhosphorIconsStyle.fill),
          colors.primary,
          'Favori',
        ),
      InterestState.followed => (
          PhosphorIcons.check(PhosphorIconsStyle.bold),
          colors.success,
          'Suivi',
        ),
      InterestState.unfollowed => (
          PhosphorIcons.minus(PhosphorIconsStyle.bold),
          colors.textSecondary,
          'Neutre',
        ),
      InterestState.hidden => (
          PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
          colors.textTertiary,
          'Masqué',
        ),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HiddenItemRow extends StatelessWidget {
  final _HiddenEntry entry;
  final VoidCallback onRestore;

  const _HiddenItemRow({required this.entry, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      dense: true,
      leading: Icon(
        entry.isTheme
            ? PhosphorIcons.shapes(PhosphorIconsStyle.regular)
            : PhosphorIcons.tag(PhosphorIconsStyle.regular),
        size: 16,
        color: colors.textTertiary,
      ),
      title: Text(
        entry.displayName,
        style: textTheme.bodyMedium?.copyWith(
          color: colors.textSecondary,
        ),
      ),
      trailing: TextButton(
        onPressed: onRestore,
        child: const Text('Modifier'),
      ),
    );
  }
}

class _ContentTypesSection extends ConsumerWidget {
  static const _contentTypes = <String, String>{
    'article': 'Articles',
    'podcast': 'Podcasts',
    'youtube': 'Vidéos YouTube',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final perso = ref.watch(personalizationProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space2,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(color: colors.surfaceElevated),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TYPES DE CONTENU',
              style: textTheme.labelSmall?.copyWith(
                color: colors.textTertiary,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            ..._contentTypes.entries.map((entry) {
              final isMuted =
                  perso?.mutedContentTypes.contains(entry.key) ?? false;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.value,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: isMuted ? colors.textTertiary : null,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: !isMuted,
                    activeColor: colors.primary,
                    onChanged: (enabled) async {
                      final repo =
                          ref.read(personalizationRepositoryProvider);
                      if (enabled) {
                        await repo.unmuteContentType(entry.key);
                      } else {
                        await repo.muteContentType(entry.key);
                      }
                      ref.invalidate(personalizationProvider);
                    },
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

