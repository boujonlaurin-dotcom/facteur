import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../../widgets/design/priority_slider.dart';
import '../../sources/providers/sources_providers.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';

class PersonalizationSheet extends ConsumerWidget {
  final Content content;

  const PersonalizationSheet({super.key, required this.content});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final reason = content.recommendationReason;
    final theme = content.source.theme;

    // Topic logic: use progressionTopic or derive from Reason if possible.
    final topic = content.progressionTopic;

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
          // Header
          Row(
            children: [
              Icon(PhosphorIcons.question(PhosphorIconsStyle.bold),
                  color: colors.primary, size: 24),
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
              if (reason != null && reason.scoreTotal > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          ),
          const SizedBox(height: 20),

          // Breakdown
          if (reason != null && reason.breakdown.isNotEmpty) ...[
            ..._buildBreakdown(reason.breakdown, colors),
            const SizedBox(height: 16),
            Divider(color: colors.border),
            const SizedBox(height: 16),
          ],

          // Actions
          Text(
            'Personnaliser mon flux'.toUpperCase(),
            style: TextStyle(
              color: colors.textSecondary, // Use secondary for section title
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Source weight slider
          if (content.source.name.isNotEmpty && content.source.isTrusted && !content.source.isMuted)
            _buildSourceWeightRow(context, ref, colors),

          // Subscription toggle (premium source)
          if (content.source.name.isNotEmpty && content.source.isTrusted && !content.source.isMuted)
            _buildSubscriptionToggle(context, ref, colors),

          // Mute source (red destructive action)
          if (content.source.name.isNotEmpty)
            _buildActionOption(
              context,
              icon: PhosphorIcons.prohibit(PhosphorIconsStyle.regular),
              label: 'Ne plus afficher ${content.source.name}',
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(feedProvider.notifier).muteSource(content);
                  NotificationService.showInfo(
                      'Source ${content.source.name} masquée');
                } catch (e) {
                  NotificationService.showError(
                      'Impossible de masquer la source');
                }
              },
              colors: colors,
              isDestructive: true,
            ),

          // "Gérer mes sources" CTA
          if (content.source.name.isNotEmpty)
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

          if (theme != null && theme.isNotEmpty)
            _buildActionOption(
              context,
              icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
              label: 'Moins sur le thème "${_getThemeLabel(theme)}"',
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(feedProvider.notifier).muteTheme(theme);
                  NotificationService.showInfo('Thème masqué');
                } catch (e) {
                  NotificationService.showError(
                      'Impossible de masquer le thème');
                }
              },
              colors: colors,
            ),

          if (topic != null &&
              topic.isNotEmpty &&
              _normalize(topic) != _normalize(theme ?? ''))
            _buildActionOption(
              context,
              icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
              label: 'Moins sur le sujet "${_getThemeLabel(topic)}"',
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(feedProvider.notifier).muteTopic(topic);
                  NotificationService.showInfo('Sujet masqué');
                } catch (e) {
                  NotificationService.showError(
                      'Impossible de masquer le sujet');
                }
              },
              colors: colors,
            ),

          // Mute content type
          if (content.contentType != ContentType.article)
            _buildActionOption(
              context,
              icon: PhosphorIcons.funnel(PhosphorIconsStyle.regular),
              label:
                  'Moins ${_getContentTypeLabel(content.contentType)}',
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref
                      .read(feedProvider.notifier)
                      .muteContentType(
                          _getContentTypeSlug(content.contentType));
                  NotificationService.showInfo('Type de contenu masqué');
                } catch (e) {
                  NotificationService.showError(
                      'Impossible de masquer ce type de contenu');
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
                    .impressContent(content);
                NotificationService.showInfo('Article marqué comme déjà vu');
              } catch (e) {
                NotificationService.showError(
                    'Erreur réseau — réessaie dans un instant');
              }
            },
            colors: colors,
          ),

          const SizedBox(height: 8),
        ],
      ),
      ),
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
      List<ScoreContribution> breakdown, FacteurColors colors) {
    final hasPillars = breakdown.any((c) => c.pillar != null);
    if (!hasPillars) {
      // Fallback: flat list (legacy backend)
      return breakdown.map((c) => _buildContributionRow(c, colors)).toList();
    }

    // Sort by absolute contribution, take top 6
    final sorted = List.of(breakdown)
      ..sort((a, b) => b.points.abs().compareTo(a.points.abs()));
    final limited = sorted.take(6).toList();

    // Group by pillar
    final groups = <String?, List<ScoreContribution>>{};
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
        widgets.add(_buildContributionRow(c, colors));
      }
    }

    // Any null-pillar items
    if (groups.containsKey(null)) {
      for (final c in groups[null]!) {
        widgets.add(_buildContributionRow(c, colors));
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
      ScoreContribution contribution, FacteurColors colors) {
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

  Widget _buildSourceWeightRow(
    BuildContext context, WidgetRef ref, FacteurColors colors) {
    // Watch live multiplier from provider (not stale content snapshot)
    final sourcesAsync = ref.watch(userSourcesProvider);
    final liveMultiplier = sourcesAsync.whenOrNull(
          data: (sources) => sources
              .where((s) => s.id == content.source.id)
              .firstOrNull
              ?.priorityMultiplier,
        ) ??
        content.source.priorityMultiplier;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Icon(
            liveMultiplier == 2.0
                ? PhosphorIcons.star(PhosphorIconsStyle.fill)
                : PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.regular),
            color: colors.textPrimary,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              content.source.name,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'Priorité :',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(width: 8),
          PrioritySlider(
            currentMultiplier: liveMultiplier,
            onChanged: (multiplier) {
              ref
                  .read(userSourcesProvider.notifier)
                  .updateWeight(content.source.id, multiplier);
            },
            labels: const ['Reduit', 'Normal', 'Favori'],
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionToggle(
      BuildContext context, WidgetRef ref, FacteurColors colors) {
    final sourcesAsync = ref.watch(userSourcesProvider);
    final isSubscribed = sourcesAsync.whenOrNull(
          data: (sources) => sources
              .where((s) => s.id == content.source.id)
              .firstOrNull
              ?.hasSubscription,
        ) ??
        content.source.hasSubscription;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Icon(
            isSubscribed
                ? PhosphorIcons.crown(PhosphorIconsStyle.fill)
                : PhosphorIcons.crown(PhosphorIconsStyle.regular),
            color: isSubscribed ? colors.primary : colors.textPrimary,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              "J'y suis abonné(e)",
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch.adaptive(
            value: isSubscribed,
            activeColor: colors.primary,
            onChanged: (value) {
              HapticFeedback.lightImpact();
              ref
                  .read(userSourcesProvider.notifier)
                  .toggleSubscription(content.source.id, isSubscribed);
            },
          ),
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

  String _normalize(String input) {
    const withDiacritics =
        'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    const withoutDiacritics =
        'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';

    var result = input;
    for (int i = 0; i < withDiacritics.length; i++) {
      result = result.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }
    return result.toLowerCase();
  }
}
