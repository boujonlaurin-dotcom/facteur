import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../../widgets/design/priority_slider.dart';
import '../models/source_model.dart';
import '../../../widgets/design/facteur_button.dart';

class SourceDetailModal extends StatelessWidget {
  final Source source;
  final VoidCallback onToggleTrust;
  final VoidCallback? onToggleMute;
  final VoidCallback? onCopyFeedUrl;
  final VoidCallback? onToggleSubscription;
  final ValueChanged<double>? onPriorityChanged; // Epic 12: frequency slider
  const SourceDetailModal({
    super.key,
    required this.source,
    required this.onToggleTrust,
    this.onToggleMute,
    this.onCopyFeedUrl,
    this.onToggleSubscription,
    this.onPriorityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Header — name + bias badge (no logo, more breathing room)
          Text(
            source.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (source.logoUrl != null) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FacteurImage(
                      imageUrl: source.logoUrl!, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
              ],
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
              if (source.theme != null) ...[
                const SizedBox(width: 8),
                Text(
                  source.getThemeLabel(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // FQS Score Card
          _buildFqsCard(context, colors),
          // Epic 12: Priority slider (only for trusted/followed sources)
          if (onPriorityChanged != null && source.isTrusted) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: colors.textTertiary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.regular),
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
                    currentMultiplier: source.priorityMultiplier,
                    onChanged: onPriorityChanged!,
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
            if (onToggleSubscription != null) ...[
              const SizedBox(height: 8),
              FacteurButton(
                onPressed: () {
                  onToggleSubscription!();
                  Navigator.pop(context);
                },
                label: source.hasSubscription
                    ? 'Ne plus marquer comme Premium'
                    : 'J\'ai un abonnement',
                type: FacteurButtonType.secondary,
                icon: source.hasSubscription
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
          // Methodology note
          _buildMethodologyNote(context, colors),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
        ),
      ),
    );
  }

  bool get _hasEvaluation =>
      source.scoreIndependence != null ||
      source.scoreRigor != null ||
      source.scoreUx != null;

  Widget _buildFqsCard(BuildContext context, FacteurColors colors) {
    return Container(
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
                  size: 20,
                  color: _hasEvaluation
                      ? source.getReliabilityColor()
                      : colors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "L'évaluation de Facteur",
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              if (_hasEvaluation)
                Text(
                  source.getReliabilityLabel(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: source.getReliabilityColor(),
                        fontWeight: FontWeight.bold,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_hasEvaluation) ...[
            _buildFqsPillar(
                context, 'Indépendance', source.scoreIndependence ?? 0.0),
            const SizedBox(height: 8),
            _buildFqsPillar(
                context, 'Rigueur', source.scoreRigor ?? 0.0),
            const SizedBox(height: 8),
            _buildFqsPillar(
                context, 'Accessibilité', source.scoreUx ?? 0.0),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Cette source n\'a pas encore pu être évaluée par la méthodologie de Facteur.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMethodologyNote(BuildContext context, FacteurColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              PhosphorIcons.info(PhosphorIconsStyle.regular),
              size: 14,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://facteur.app'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text.rich(
                TextSpan(
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 11,
                        height: 1.4,
                      ),
                  children: [
                    const TextSpan(
                      text:
                          'Facteur évalue ces critères sur la base d\'une méthodologie '
                          'inspirée des codes de déontologie journalistiques. '
                          'Ce standard ouvert, développé par Facteur, est en cours '
                          'de relecture par des instituts indépendants. ',
                    ),
                    TextSpan(
                      text: 'En savoir plus',
                      style: TextStyle(
                        color: colors.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: colors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
