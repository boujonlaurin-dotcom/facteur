import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../models/source_model.dart';

/// Bottom sheet déclenchée au tap sur une PepiteCard (hors bouton "Suivre").
/// Affiche plus de contexte sur la source et expose un CTA "Suivre" explicite.
class PepitePreviewSheet extends StatelessWidget {
  final Source source;
  final VoidCallback onFollow;

  const PepitePreviewSheet({
    super.key,
    required this.source,
    required this.onFollow,
  });

  static Future<void> show(
    BuildContext context, {
    required Source source,
    required VoidCallback onFollow,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PepitePreviewSheet(
        source: source,
        onFollow: () {
          Navigator.of(ctx).pop();
          onFollow();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: FacteurSpacing.space4,
        right: FacteurSpacing.space4,
        top: FacteurSpacing.space3,
        bottom: MediaQuery.of(context).viewInsets.bottom + FacteurSpacing.space6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildLogo(colors),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      source.getThemeLabel(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (source.followerCount > 0)
            Row(
              children: [
                Icon(
                  PhosphorIcons.users(PhosphorIconsStyle.regular),
                  size: 14,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Source de confiance de ${source.followerCount} '
                  '${source.followerCount > 1 ? "lecteurs" : "lecteur"}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          if (source.description != null &&
              source.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              source.description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Suivre cette source',
            icon: PhosphorIcons.plus(PhosphorIconsStyle.bold),
            onPressed: onFollow,
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(FacteurColors colors) {
    if (source.logoUrl != null && source.logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        child: Image.network(
          source.logoUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildLogoFallback(colors),
        ),
      );
    }
    return _buildLogoFallback(colors);
  }

  Widget _buildLogoFallback(FacteurColors colors) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
      ),
      child: Icon(
        PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
        size: 26,
        color: colors.primary,
      ),
    );
  }
}
