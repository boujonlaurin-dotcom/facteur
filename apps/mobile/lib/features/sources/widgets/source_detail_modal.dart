import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../my_interests/widgets/interest_state_pill.dart';
import '../models/smart_search_result.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import '../../../widgets/design/facteur_button.dart';
import 'premium_source_connection.dart';
import 'recent_articles_list.dart';
import 'source_logo_avatar.dart';

class SourceDetailModal extends ConsumerWidget {
  final Source source;
  final VoidCallback onToggleTrust;
  final VoidCallback? onToggleMute;
  final VoidCallback? onCopyFeedUrl;
  final List<SmartSearchRecentItem>? recentItems;

  /// Contexte onboarding : quand non-null, le bouton principal reflète l'état de
  /// sélection du questionnaire (et non l'état « confiance » global), avec un
  /// libellé « Sélectionner / Retirer de ma sélection ».
  final bool? isSelectedOverride;

  /// Libellé du bouton principal quand la source n'est pas sélectionnée
  /// (contexte onboarding). Défaut : « Sélectionner cette source ».
  final String? selectLabel;

  const SourceDetailModal({
    super.key,
    required this.source,
    required this.onToggleTrust,
    this.onToggleMute,
    this.onCopyFeedUrl,
    this.recentItems,
    this.isSelectedOverride,
    this.selectLabel,
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
                        color: source.getBiasColor().withValues(alpha: 0.1),
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
            RecentArticlesList(items: recentItems!),
            const SizedBox(height: 16),
          ],

          // FQS Score Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.textTertiary.withValues(alpha: 0.2)),
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
          if (displaySource.isTrusted) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.textTertiary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.regular),
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Place cette source dans votre flux',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.3,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SourceStatePill(
                    sourceId: source.id,
                    title: source.name,
                  ),
                ],
              ),
            ),
          ],
          if (displaySource.recommendedBy != null &&
              displaySource.recommendedBy!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.textTertiary.withValues(alpha: 0.2)),
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
                      Expanded(
                        child: Text(
                          'Recommandé par ${displaySource.recommendedBy} '
                          '— équipe Facteur',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  if (displaySource.recommendationReason != null &&
                      displaySource.recommendationReason!
                          .trim()
                          .isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      displaySource.recommendationReason!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                    ),
                  ],
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
              border: Border.all(color: colors.textTertiary.withValues(alpha: 0.2)),
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
            // CTA abonnement premium — proéminent (primary, en tête) pour les
            // sources payantes. Label selon l'état : déjà abonné / config
            // générique (« Associer ») / config curée (« Connecter »).
            if (displaySource.premiumConnection != null) ...[
              FacteurButton(
                onPressed: () =>
                    _openPremiumConnectionFlow(context, ref, displaySource),
                label: displaySource.hasSubscription
                    ? 'Reconnecter cet abonnement'
                    : (displaySource.premiumConnection!.isGeneric
                        ? 'Associer mon abonnement'
                        : 'Connecter mon abonnement'),
                type: displaySource.hasPaywall
                    ? FacteurButtonType.primary
                    : FacteurButtonType.secondary,
                icon: PhosphorIcons.link(PhosphorIconsStyle.regular),
              ),
              const SizedBox(height: 8),
            ],
            // Bouton principal : confiance (global) ou sélection (onboarding).
            Builder(builder: (context) {
              final bool inOnboarding = isSelectedOverride != null;
              final bool isSelected =
                  isSelectedOverride ?? displaySource.isTrusted;
              return FacteurButton(
                onPressed: () {
                  onToggleTrust();
                  Navigator.pop(context);
                },
                label: inOnboarding
                    ? (isSelected
                        ? 'Retirer de ma sélection'
                        : (selectLabel ?? 'Sélectionner cette source'))
                    : (isSelected
                        ? 'Ne plus suivre'
                        : 'Ajouter comme source de confiance'),
                type: (!isSelected &&
                        !(displaySource.premiumConnection != null &&
                            displaySource.hasPaywall))
                    ? FacteurButtonType.primary
                    : FacteurButtonType.secondary,
                icon: isSelected
                    ? PhosphorIcons.check()
                    : PhosphorIcons.shieldCheck(),
              );
            }),
            if (displaySource.isTrusted) ...[
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final isFavorite = ref
                        .watch(userSourcesStateProvider)
                        .valueOrNull
                        ?.favorites
                        .any((f) => f.sourceId == source.id) ??
                    false;
                return FacteurButton(
                  onPressed: () async {
                    final next = isFavorite
                        ? InterestState.followed
                        : InterestState.favorite;
                    try {
                      await ref
                          .read(userSourcesStateProvider.notifier)
                          .setSourceState(source.id, next);
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Impossible de mettre à jour cette source.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  label: isFavorite
                      ? 'Retirer des favoris'
                      : 'Ajouter aux favoris',
                  type: FacteurButtonType.secondary,
                  icon: isFavorite
                      ? PhosphorIcons.star(PhosphorIconsStyle.regular)
                      : PhosphorIcons.star(PhosphorIconsStyle.fill),
                );
              }),
            ],
            if (displaySource.hasSubscription) ...[
              const SizedBox(height: 8),
              FacteurButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(userSourcesProvider.notifier)
                        .disconnectSubscription(displaySource.id);
                    // Purge la session persistée (cookies média) — le paywall
                    // doit réapparaître après dissociation.
                    await ref
                        .read(premiumSessionStoreProvider)
                        .clearForSource(displaySource);
                    if (context.mounted) Navigator.pop(context);
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Impossible de dissocier cet abonnement.'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                },
                label: 'Dissocier mon abonnement',
                type: FacteurButtonType.secondary,
                icon: PhosphorIcons.linkBreak(PhosphorIconsStyle.regular),
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

  Future<void> _openPremiumConnectionFlow(
    BuildContext context,
    WidgetRef ref,
    Source source,
  ) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await Future<void>.delayed(Duration.zero);
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => PremiumSourceConnection(
          source: source,
          onConnected: () => ref
              .read(userSourcesProvider.notifier)
              .connectSubscription(source.id),
        ),
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
