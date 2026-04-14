import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../../widgets/design/facteur_stamp.dart';
import '../../../widgets/design/priority_slider.dart';
import '../models/source_model.dart';
import 'source_detail_modal.dart';

class SourceListItem extends StatelessWidget {
  final Source source;
  final VoidCallback? onTap;
  final VoidCallback? onToggleMute;
  final ValueChanged<double>? onWeightChanged;
  final VoidCallback? onToggleSubscription;
  final double? usageWeight;

  const SourceListItem({
    super.key,
    required this.source,
    this.onTap,
    this.usageWeight,
    this.onToggleMute,
    this.onWeightChanged,
    this.onToggleSubscription,
  });

  IconData get _typeIcon {
    switch (source.type) {
      case SourceType.youtube:
        return PhosphorIcons.video(PhosphorIconsStyle.fill);
      case SourceType.reddit:
        return PhosphorIcons.redditLogo(PhosphorIconsStyle.fill);
      case SourceType.podcast:
        return PhosphorIcons.headphones(PhosphorIconsStyle.fill);
      case SourceType.video:
        return PhosphorIcons.filmStrip(PhosphorIconsStyle.fill);
      default:
        return PhosphorIcons.article(PhosphorIconsStyle.fill);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isTrusted = source.isTrusted;
    final isMuted = source.isMuted;

    return GestureDetector(
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => SourceDetailModal(
            source: source,
            onToggleTrust: onTap ?? () {},
            onToggleMute: onToggleMute,
            onToggleSubscription: onToggleSubscription,
            usageWeight: usageWeight,
          ),
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: isMuted ? 0.5 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMuted
                ? colors.surface
                : isTrusted
                    ? colors.surfaceElevated
                    : colors.surface,
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
            border: isMuted
                ? Border.all(color: Colors.transparent, width: 1.5)
                : isTrusted
                    ? Border.all(
                        color: colors.primary.withOpacity(0.3),
                        width: 1.5)
                    : Border.all(color: Colors.transparent, width: 1.5),
          ),
          child: Row(
            children: [
              // Logo or Placeholder
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: source.logoUrl != null && source.logoUrl!.isNotEmpty
                    ? FacteurImage(
                        imageUrl: source.logoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context) => Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.secondary.withOpacity(0.3),
                            ),
                          ),
                        ),
                        errorWidget: (context) =>
                            Icon(_typeIcon, color: colors.secondary, size: 20),
                      )
                    : Icon(_typeIcon, color: colors.secondary, size: 20),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            source.name,
                            style:
                                Theme.of(context).textTheme.labelLarge?.copyWith(
                                      color: colors.textPrimary,
                                    ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (source.biasStance != 'unknown' &&
                            source.biasStance != 'neutral') ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: source.getBiasColor(),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (source.theme != null)
                      Text(
                        source.getThemeLabel(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                      ),
                  ],
                ),
              ),

              // Priority slider for trusted, non-muted sources
              if (!isMuted && isTrusted && onWeightChanged != null) ...[
                const SizedBox(width: 8),
                PrioritySlider(
                  key: ValueKey(source.priorityMultiplier),
                  currentMultiplier: source.priorityMultiplier,
                  onChanged: onWeightChanged!,
                  usageWeight: usageWeight,
                ),
              ],

              // "+" icon for unfollowed sources
              if (!isMuted && !isTrusted)
                Icon(
                  PhosphorIcons.plus(PhosphorIconsStyle.bold),
                  size: 20,
                  color: colors.textTertiary,
                ),

              // Muted Indicator
              if (isMuted)
                FacteurStamp(
                  text: 'MASQUEE',
                  isNew: true,
                  color: colors.error,
                ),
              // Subscription stamp
              if (source.hasSubscription && !isMuted) ...[
                const SizedBox(width: 8),
                FacteurStamp(
                  text: 'ABONNÉ',
                  isNew: true,
                  color: colors.success,
                ),
              ],
              // Custom source stamp (only when no slider shown)
              if (source.isCustom && (isMuted || !isTrusted)) ...[
                const SizedBox(width: 8),
                FacteurStamp(
                  text: 'PERSO',
                  isNew: true,
                  color: colors.secondary,
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
