import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../config/theme.dart';
import '../models/source_model.dart';
import '../../../widgets/design/facteur_button.dart';

class SourceDetailModal extends StatelessWidget {
  final Source source;
  final VoidCallback onToggleTrust;

  const SourceDetailModal({
    super.key,
    required this.source,
    required this.onToggleTrust,
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
                    ? CachedNetworkImage(
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

          // Description
          if (source.description != null) ...[
            Text(
              source.description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
          ],

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
                      'Qualité Facteur (FQS)',
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
                    context, 'UX & Publicité', source.scoreUx ?? 0.0),
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
              "Facteur analyse l'ensemble des médias pour vous proposer une information plurielle et fiable. En ajoutant cette source à vos favoris, vous nous indiquez vouloir la privilégier dans votre veille quotidienne.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ),
          const SizedBox(height: 24),

          // Action Button
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
