import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';
import '../models/digest_mode.dart';

/// Tab selector horizontal pour les 4 modes du digest.
///
/// Chaque pill affiche icône + label avec la couleur du mode.
/// Le tap change immédiatement la sélection visuelle et déclenche le callback.
class DigestModeTabSelector extends StatelessWidget {
  final DigestMode selectedMode;
  final ValueChanged<DigestMode> onModeChanged;
  final bool isRegenerating;

  const DigestModeTabSelector({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    this.isRegenerating = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space2,
      ),
      child: Row(
        children: DigestMode.values.map((mode) {
          final isSelected = mode == selectedMode;
          final modeColor = mode.effectiveColor(colors.primary);

          return Padding(
            padding: const EdgeInsets.only(right: FacteurSpacing.space2),
            child: _ModePill(
              mode: mode,
              isSelected: isSelected,
              modeColor: modeColor,
              textColor: colors.textTertiary,
              onTap: isRegenerating
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      onModeChanged(mode);
                    },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final DigestMode mode;
  final bool isSelected;
  final Color modeColor;
  final Color textColor;
  final VoidCallback? onTap;

  const _ModePill({
    required this.mode,
    required this.isSelected,
    required this.modeColor,
    required this.textColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? modeColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(FacteurRadius.pill),
          border: Border.all(
            color: isSelected
                ? modeColor.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode.icon,
              size: 16,
              color: isSelected ? modeColor : textColor,
            ),
            const SizedBox(width: 6),
            Text(
              mode.label,
              style: TextStyle(
                color: isSelected ? modeColor : textColor,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                fontFamily: 'DM Sans',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
