import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/digest_mode.dart';

/// Reusable card widget for selecting a DigestMode.
/// Used in both DigestSettingsScreen and onboarding DigestModeQuestion.
class DigestModeCard extends StatelessWidget {
  final DigestMode mode;
  final bool isSelected;
  final Color modeColor;
  final FacteurColors colors;
  final VoidCallback onTap;

  const DigestModeCard({
    super.key,
    required this.mode,
    required this.isSelected,
    required this.modeColor,
    required this.colors,
    required this.onTap,
  });

  String get _description {
    switch (mode) {
      case DigestMode.pourVous:
        return 'Votre sélection personnalisée, équilibrée entre vos thèmes et sources.';
      case DigestMode.serein:
        return 'Pas de politique, pas de faits divers ni de sujets anxiogènes. Zen.';
      case DigestMode.perspective:
        return 'Découvrez des points de vue opposés à vos habitudes de lecture.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        decoration: BoxDecoration(
          color: isSelected
              ? modeColor.withValues(alpha: 0.1)
              : colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(
            color: isSelected
                ? modeColor.withValues(alpha: 0.5)
                : colors.surfaceElevated,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: modeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
              ),
              child: Icon(
                mode.icon,
                color: modeColor,
                size: 20,
              ),
            ),
            const SizedBox(width: FacteurSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: TextStyle(
                      color: isSelected ? modeColor : colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'DM Sans',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      fontFamily: 'DM Sans',
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                color: modeColor,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
