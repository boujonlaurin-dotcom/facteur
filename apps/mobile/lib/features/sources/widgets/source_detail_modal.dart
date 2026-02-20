import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../models/source_model.dart';
import '../../../widgets/design/facteur_button.dart';

class SourceDetailModal extends StatelessWidget {
  final Source source;
  final VoidCallback onToggleTrust;
  final VoidCallback? onToggleMute;

  const SourceDetailModal({
    super.key,
    required this.source,
    required this.onToggleTrust,
    this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

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
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: source.logoUrl != null
                    ? FacteurImage(
                        imageUrl: source.logoUrl!, fit: BoxFit.cover)
                    : Icon(PhosphorIcons.article(), color: colors.secondary),
              ),
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
          const SizedBox(height: 24),

          // FQS Score Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: colors.textTertiary.withValues(alpha: 0.2)),
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
          const SizedBox(height: 24),

          // Explanation Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: colors.textTertiary.withValues(alpha: 0.2)),
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
          if (source.isMuted) ...[
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
          ] else ...[
            // Trust/Untrust button
            FacteurButton(
              onPressed: () {
                onToggleTrust();
                Navigator.pop(context);
              },
              label: source.isTrusted
                  ? 'Ne plus suivre'
                  : 'Ajouter comme source de confiance',
              type: !source.isTrusted
                  ? FacteurButtonType.primary
                  : FacteurButtonType.secondary,
              icon: source.isTrusted
                  ? PhosphorIcons.check()
                  : PhosphorIcons.shieldCheck(),
            ),
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
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
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
