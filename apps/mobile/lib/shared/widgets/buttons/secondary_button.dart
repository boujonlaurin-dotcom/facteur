import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Bouton secondaire Facteur (outline)
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool fullWidth;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      width:
          fullWidth ? double.infinity : null, // Keep original fullWidth logic
      height: 56, // Changed from 52 to 56
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: colors
                .surfaceElevated, // Changed from FacteurColors.surfaceElevated
            width: 1.5, // Added width
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FacteurRadius
                .pill), // Changed from FacteurRadius.small to FacteurRadius.pill
          ),
          backgroundColor: Colors.transparent, // Added backgroundColor
          foregroundColor:
              colors.textPrimary, // Changed from FacteurColors.textPrimary
        ),
        child: isLoading
            ? SizedBox(
                // Changed from const SizedBox
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5, // Changed from 2 to 2.5
                  valueColor: AlwaysStoppedAnimation(
                    // Removed <Color>
                    colors
                        .textPrimary, // Changed from FacteurColors.textPrimary
                  ),
                ),
              )
            : Row(
                // The original Row structure is preserved, but the Text style is updated
                mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
      ),
    );
  }
}
