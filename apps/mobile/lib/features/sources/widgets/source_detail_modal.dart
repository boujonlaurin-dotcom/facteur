import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/priority_slider.dart';
import '../models/smart_search_result.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import '../../../widgets/design/facteur_button.dart';
import 'source_logo_avatar.dart';

class SourceDetailModal extends ConsumerWidget {
  final Source source;
  final VoidCallback onToggleTrust;
  final VoidCallback? onToggleMute;
  final VoidCallback? onCopyFeedUrl;
  final VoidCallback? onToggleSubscription;
  final ValueChanged<double>? onPriorityChanged; // Epic 12: frequency slider
  final double? usageWeight;
  final List<SmartSearchRecentItem>? recentItems;

  const SourceDetailModal({
    super.key,
    required this.source,
    required this.onToggleTrust,
    this.onToggleMute,
    this.onCopyFeedUrl,
    this.onToggleSubscription,
    this.onPriorityChanged,
    this.usageWeight,
    this.recentItems,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    // Read live source from provider so priority slider / trust state stay in sync
    // when the user toggles via the modal itself.
    final liveSource = ref
            .watch(userSourcesProvider)
            .valueOrNull
            ?.where((s) => s.id == source.id)
            .firstOrNull ??
        source;
    final displaySource = liveSource;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              SourceLogoAvatar(source: displaySource, size: 64, radius: 16),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: source.getBiasColor().withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        source.getBiasLabel().toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: source.getBiasColor(),
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (displaySource.followerCount > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  PhosphorIcons.users(PhosphorIconsStyle.regular),
                  size: 14,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Source de confiance de ${displaySource.followerCount} '
                  '${displaySource.followerCount > 1 ? "lecteurs" : "lecteur"}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),

          // Recent articles (only shown when provided, e.g. from smart search)
          if (recentItems != null && recentItems!.isNotEmpty) ...[
            _buildRecentArticles(context, colors),
            const SizedBox(height: 16),
          ],

          // FQS Score Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: colors.textTertiary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(PhosphorIcons.shieldCheck(PhosphorIconsStyle.fill),
                        color: source.getReliabilityColor()),
                    const SizedBox(width: 8),
                    Text(
                      'Évaluation de qualité',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      source.getReliabilityLabel(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: source.getReliabilityColor(),
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildFqsPillar(
                    context, 'Indépendance', source.scoreIndependence ?? 0.0),
                const SizedBox(height: 8),
                _buildFqsPillar(context, 'Rigueur Journalistique',
                    source.scoreRigor ?? 0.0),
                const SizedBox(height: 8),
                _buildFqsPillar(
                    context, 'Accessibilité', source.scoreUx ?? 0.0),
              ],
            ),
          ),
          // Epic 12: Priority slider (only for trusted/followed sources)
          if (onPriorityChanged != null && displaySource.isTrusted) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: colors.textTertiary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        PhosphorIcons.slidersHorizontal(
                            PhosphorIconsStyle.regular),
                        size: 18,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Fréquence',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const Spacer(),
                      PrioritySlider(
                        key: ValueKey(source.id),
                        currentMultiplier: displaySource.priorityMultiplier,
                        onChanged: onPriorityChanged!,
                        usageWeight: usageWeight,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ajustez à quel point vous souhaitez voir cette source',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.3,
                        ),
                  ),
                ],
              ),
            ),
          ],
          if (displaySource.editorialNote != null &&
              displaySource.editorialNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: colors.textTertiary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/recos_facteur.png',
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pourquoi on apprécie',
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    displaySource.editorialNote!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Explanation Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: colors.textTertiary.withOpacity(0.2)),
            ),
            child: Text(
              source.description ??
                  "Facteur analyse l'ensemble des médias pour vous proposer une information plurielle et fiable. En ajoutant cette source à vos favoris, vous nous indiquez vouloir la privilégier dans votre veille quotidienne.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          if (displaySource.isMuted) ...[
            // Muted state: follow (auto-unmutes via backend) + unmute
            FacteurButton(
              onPressed: () {
                onToggleTrust();
                Navigator.pop(context);
              },
              label: 'Ajouter comme source de confiance',
              type: FacteurButtonType.primary,
              icon: PhosphorIcons.shieldCheck(),
            ),
            const SizedBox(height: 8),
            FacteurButton(
              onPressed: () {
                onToggleMute?.call();
                Navigator.pop(context);
              },
              label: 'Ne plus masquer',
              type: FacteurButtonType.secondary,
              icon: PhosphorIcons.eye(),
            ),
            if (onCopyFeedUrl != null) ...[
              const SizedBox(height: 8),
              FacteurButton(
                onPressed: onCopyFeedUrl!,
                label: 'Copier l\'URL du flux RSS',
                type: FacteurButtonType.secondary,
                icon: PhosphorIcons.copy(),
              ),
            ],
          ] else ...[
            // Trust/Untrust button
            FacteurButton(
              onPressed: () {
                onToggleTrust();
                Navigator.pop(context);
              },
              label: displaySource.isTrusted
                  ? 'Ne plus suivre'
                  : 'Ajouter comme source de confiance',
              type: !displaySource.isTrusted
                  ? FacteurButtonType.primary
                  : FacteurButtonType.secondary,
              icon: displaySource.isTrusted
                  ? PhosphorIcons.check()
                  : PhosphorIcons.shieldCheck(),
            ),
            if (onToggleSubscription != null) ...[
              const SizedBox(height: 8),
              FacteurButton(
                onPressed: () {
                  onToggleSubscription!();
                  Navigator.pop(context);
                },
                label: displaySource.hasSubscription
                    ? 'Ne plus marquer comme Premium'
                    : 'J\'ai un abonnement',
                type: FacteurButtonType.secondary,
                icon: displaySource.hasSubscription
                    ? PhosphorIcons.star(PhosphorIconsStyle.regular)
                    : PhosphorIcons.star(PhosphorIconsStyle.fill),
              ),
            ],
            if (onToggleMute != null) ...[
              const SizedBox(height: 8),
              // Mute button
              FacteurButton(
                onPressed: () {
                  onToggleMute!();
                  Navigator.pop(context);
                },
                label: 'Masquer cette source',
                type: FacteurButtonType.secondary,
                icon: PhosphorIcons.eyeSlash(),
              ),
            ],
            if (onCopyFeedUrl != null) ...[
              const SizedBox(height: 8),
              FacteurButton(
                onPressed: onCopyFeedUrl!,
                label: 'Copier l\'URL du flux RSS',
                type: FacteurButtonType.secondary,
                icon: PhosphorIcons.copy(),
              ),
            ],
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildRecentArticles(BuildContext context, FacteurColors colors) {
    final items = recentItems!.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.textTertiary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIcons.newspaperClipping(PhosphorIconsStyle.regular),
                  size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Derniers articles',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                          PhosphorIcons.dotOutline(PhosphorIconsStyle.fill),
                          size: 12,
                          color: colors.primary),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.title,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildFqsPillar(BuildContext context, String label, double value) {
    final colors = context.facteurColors;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: colors.surface,
              valueColor: AlwaysStoppedAnimation(colors.primary),
              minHeight: 6,
            ),
          ),
        ),
      ],
    );
  }
}
