import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../core/ui/notification_service.dart';
import '../../../widgets/design/priority_slider.dart';
import '../../custom_topics/providers/algorithm_profile_provider.dart';
import '../../custom_topics/providers/personalization_provider.dart';
import '../../feed/models/content_model.dart' show ContentType;
import '../../feed/providers/feed_provider.dart';
import '../../feed/repositories/personalization_repository.dart';
import '../../sources/providers/sources_providers.dart';
import '../models/digest_models.dart';

/// Bottom sheet widget showing "Pourquoi cet article?" with scoring breakdown
/// Adapted from feed's PersonalizationSheet but for DigestItem
class DigestPersonalizationSheet extends ConsumerWidget {
  final DigestItem item;

  const DigestPersonalizationSheet({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final reason = item.recommendationReason;

    if (reason == null) {
      return _buildNoReasonView(context, ref, colors);
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: const EdgeInsets.only(top: 24, bottom: 40, left: 20, right: 20),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            _buildDragHandle(colors),
            const SizedBox(height: 20),

            // Header with icon, title and total score
            _buildHeader(context, colors, reason),
            const SizedBox(height: 24),

            // Breakdown list
            ..._buildBreakdown(reason.breakdown, colors),

            // Divider and actions
            if (item.source != null) ...[
              const SizedBox(height: 16),
              Divider(color: colors.border),
              const SizedBox(height: 16),
              _buildActions(context, ref, colors, item),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle(FacteurColors colors) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: colors.textTertiary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    FacteurColors colors,
    DigestRecommendationReason reason,
  ) {
    return Row(
      children: [
        Icon(
          PhosphorIcons.question(PhosphorIconsStyle.bold),
          color: colors.primary,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Pourquoi cet article ?',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (reason.scoreTotal > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${reason.scoreTotal.toInt()} pts',
              style: TextStyle(
                color: colors.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  static const _pillarOrder = [
    'pertinence',
    'source',
    'fraicheur',
    'qualite',
    'diversite',
    'penalite',
  ];

  static const _pillarHeaders = {
    'pertinence': "Vos centres d'intérêt",
    'source': 'Vos sources',
    'fraicheur': 'Actualité',
    'qualite': 'Qualité du contenu',
    'diversite': 'Diversité',
  };

  List<Widget> _buildBreakdown(
      List<DigestScoreBreakdown> breakdown, FacteurColors colors) {
    final hasPillars = breakdown.any((c) => c.pillar != null);
    if (!hasPillars) {
      // Fallback: flat list (legacy backend)
      return breakdown
          .map((c) => _buildContributionRow(colors, c))
          .toList();
    }

    // Sort by absolute contribution, take top 6
    final sorted = List.of(breakdown)
      ..sort((a, b) => b.points.abs().compareTo(a.points.abs()));
    final limited = sorted.take(6).toList();

    // Group by pillar
    final groups = <String?, List<DigestScoreBreakdown>>{};
    for (final c in limited) {
      groups.putIfAbsent(c.pillar, () => []).add(c);
    }

    final widgets = <Widget>[];
    for (final key in _pillarOrder) {
      if (!groups.containsKey(key)) continue;
      final header = _pillarHeaders[key];
      if (header != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            header,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ));
      }
      for (final c in groups[key]!) {
        widgets.add(_buildContributionRow(colors, c));
      }
    }

    // Any null-pillar items
    if (groups.containsKey(null)) {
      for (final c in groups[null]!) {
        widgets.add(_buildContributionRow(colors, c));
      }
    }

    if (breakdown.length > 6) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'et ${breakdown.length - 6} autre${breakdown.length - 6 > 1 ? 's' : ''} facteur${breakdown.length - 6 > 1 ? 's' : ''}…',
          style: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      ));
    }

    return widgets;
  }

  Widget _buildContributionRow(
    FacteurColors colors,
    DigestScoreBreakdown contribution,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            contribution.isPositive
                ? PhosphorIcons.trendUp(PhosphorIconsStyle.bold)
                : PhosphorIcons.trendDown(PhosphorIconsStyle.bold),
            color: contribution.isPositive ? colors.success : colors.error,
            size: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              contribution.label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            '${contribution.points > 0 ? '+' : ''}${contribution.points.toInt()}',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    WidgetRef ref,
    FacteurColors colors,
    DigestItem item,
  ) {
    final source = item.source;
    final theme = source?.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Personnaliser mon flux'.toUpperCase(),
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Source weight slider
        if (source != null && source.id != null && source.id!.isNotEmpty)
          _buildSourceWeightRow(context, ref, colors, source),

        // Mute source (red destructive action)
        if (source != null && source.id != null && source.id!.isNotEmpty)
          _buildActionOption(
            context,
            icon: PhosphorIcons.prohibit(PhosphorIconsStyle.regular),
            label: 'Ne plus afficher ${source.name}',
            onTap: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(feedProvider.notifier)
                    .muteSourceById(source.id!);
                NotificationService.showInfo('Source ${source.name} masquée');
              } catch (e) {
                NotificationService.showError(
                    'Impossible de masquer la source');
              }
            },
            colors: colors,
            isDestructive: true,
          ),

        // "Gérer mes sources" CTA
        if (source != null && source.id != null && source.id!.isNotEmpty)
          Center(
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.pushNamed(RouteNames.sources);
              },
              icon: Icon(
                PhosphorIcons.gear(),
                size: 14,
                color: colors.textSecondary,
              ),
              label: Text(
                'Gérer mes sources',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ),
          ),

        // Mute theme action
        if (theme != null && theme.isNotEmpty)
          _buildActionOption(
            context,
            icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
            label: 'Moins sur le thème "${_getThemeLabel(theme)}"',
            onTap: () async {
              Navigator.pop(context);
              try {
                final repo = ref.read(personalizationRepositoryProvider);
                await repo.muteTheme(theme);
                ref.invalidate(personalizationProvider);
                NotificationService.showInfo('Thème masqué');
              } catch (e) {
                NotificationService.showError('Impossible de masquer le thème');
              }
            },
            colors: colors,
          ),

        // Mute topic actions (all ML topics of this article)
        for (final topicSlug in item.topics)
          if (_getThemeLabel(theme ?? '').toLowerCase() !=
              getTopicLabel(topicSlug).toLowerCase())
            _buildActionOption(
              context,
              icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
              label: 'Moins sur "${getTopicLabel(topicSlug)}"',
              onTap: () async {
                Navigator.pop(context);
                try {
                  final repo = ref.read(personalizationRepositoryProvider);
                  await repo.muteTopic(topicSlug);
                  ref.invalidate(personalizationProvider);
                  NotificationService.showInfo('Sujet masqué');
                } catch (e) {
                  NotificationService.showError(
                      'Impossible de masquer le sujet');
                }
              },
              colors: colors,
            ),

        // "Already seen" — permanent strong impression penalty
        _buildActionOption(
          context,
          icon: PhosphorIcons.eyeClosed(PhosphorIconsStyle.regular),
          label: "J'ai déjà vu cet article",
          onTap: () async {
            Navigator.pop(context);
            try {
              await ref
                  .read(feedProvider.notifier)
                  .impressContentById(item.contentId);
              NotificationService.showInfo('Article marqué comme déjà vu');
            } catch (e) {
              NotificationService.showError(
                  'Erreur réseau — réessaie dans un instant');
            }
          },
          colors: colors,
        ),
      ],
    );
  }

  Widget _buildSourceWeightRow(
    BuildContext context,
    WidgetRef ref,
    FacteurColors colors,
    SourceMini source,
  ) {
    // Look up current multiplier from the full sources list
    final sourcesAsync = ref.watch(userSourcesProvider);
    final currentMultiplier = sourcesAsync.whenOrNull(
          data: (sources) {
            final match = sources.where((s) => s.id == source.id).firstOrNull;
            return match?.priorityMultiplier;
          },
        ) ??
        1.0;

    // Only show slider if source is trusted (not muted)
    final isTrusted = sourcesAsync.whenOrNull(
          data: (sources) {
            final match = sources.where((s) => s.id == source.id).firstOrNull;
            return match?.isTrusted == true && match?.isMuted != true;
          },
        ) ??
        false;

    if (!isTrusted) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Icon(
            currentMultiplier == 2.0
                ? PhosphorIcons.star(PhosphorIconsStyle.fill)
                : PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.regular),
            color: colors.textPrimary,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              source.name,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Builder(builder: (context) {
            final algoProfile = ref.watch(algorithmProfileProvider).valueOrNull;
            final sourceUsage = source.id != null
                ? algoProfile?.sourceAffinities[source.id!]
                : null;
            return PrioritySlider(
              currentMultiplier: currentMultiplier,
              onChanged: (multiplier) {
                ref
                    .read(userSourcesProvider.notifier)
                    .updateWeight(source.id!, multiplier);
              },
              usageWeight: sourceUsage,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActionOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required FacteurColors colors,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? colors.error : colors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoReasonView(
      BuildContext context, WidgetRef ref, FacteurColors colors) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: const EdgeInsets.only(top: 24, bottom: 40, left: 20, right: 20),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDragHandle(colors),
          const SizedBox(height: 20),

          // Header — still show a useful title
          Row(
            children: [
              Icon(
                PhosphorIcons.sliders(PhosphorIconsStyle.bold),
                color: colors.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Personnaliser',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ajustez vos préférences pour cet article.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
            ),
          ),

          // Always show personalization actions if source is available
          if (item.source != null) ...[
            const SizedBox(height: 16),
            Divider(color: colors.border),
            const SizedBox(height: 16),
            _buildActions(context, ref, colors, item),
          ],
        ],
      ),
      ),
    );
  }

  String _getContentTypeLabel(ContentType type) {
    switch (type) {
      case ContentType.audio:
        return 'de podcasts';
      case ContentType.youtube:
        return 'de vidéos YouTube';
      case ContentType.video:
        return 'de vidéos';
      case ContentType.article:
        return "d'articles";
    }
  }

  /// Maps Dart ContentType to backend content_type slug
  String _getContentTypeSlug(ContentType type) {
    switch (type) {
      case ContentType.audio:
        return 'podcast';
      case ContentType.youtube:
        return 'youtube';
      case ContentType.video:
        return 'youtube';
      case ContentType.article:
        return 'article';
    }
  }

  String _getThemeLabel(String slug) {
    const translations = {
      'tech': 'Tech',
      'international': 'International',
      'science': 'Science',
      'culture': 'Culture',
      'politics': 'Politique',
      'society': 'Société',
      'environment': 'Environnement',
      'economy': 'Économie',
      'sport': 'Sport',
    };
    return translations[slug.toLowerCase()] ?? slug;
  }
}
