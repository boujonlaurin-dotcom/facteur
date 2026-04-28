import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Bandeau pleine largeur, inseré dans le flux d'une sheet, d'un article, etc.
///
/// Style DM Sans uniquement. Icône phosphor optionnelle à gauche, bouton de
/// dismiss à droite, CTA optionnel (tap → [onAction], indépendant du dismiss).
class NudgeInlineBanner extends StatelessWidget {
  const NudgeInlineBanner({
    super.key,
    required this.body,
    required this.onDismiss,
    this.icon,
    this.actionLabel,
    this.onAction,
  }) : assert(
          (actionLabel == null) == (onAction == null),
          'actionLabel and onAction must be provided together',
        );

  final String body;
  final VoidCallback onDismiss;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space3,
          vertical: FacteurSpacing.space3,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: FacteurSpacing.space2),
            ],
            Expanded(
              child: Text(
                body,
                style: FacteurTypography.bodyMedium(colors.textPrimary),
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(width: FacteurSpacing.space2),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space2,
                    vertical: FacteurSpacing.space1,
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: FacteurTypography.labelLarge(colors.primary),
                ),
              ),
            ],
            IconButton(
              onPressed: onDismiss,
              icon: Icon(
                PhosphorIcons.x(),
                size: 16,
                color: colors.textTertiary,
              ),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              tooltip: 'Fermer',
            ),
          ],
        ),
      ),
    );
  }
}
