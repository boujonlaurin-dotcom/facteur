import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:facteur/config/theme.dart';

enum FacteurButtonType {
  primary,
  secondary, // Outlined
  text,
}

class FacteurButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final FacteurButtonType type;
  final IconData? icon;
  final bool isLoading;

  const FacteurButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.type = FacteurButtonType.primary,
    this.icon,
    this.isLoading = false,
  });

  Future<void> _handlePress() async {
    if (onPressed == null || isLoading) return;

    // "Heavy Stamp" feel for buttons
    await HapticFeedback.heavyImpact();

    onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    // Shared content
    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white, // Always white on primary
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
        ] else if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: FacteurSpacing.space2),
        ],
        Text(label),
      ],
    );

    switch (type) {
      case FacteurButtonType.primary:
        return ElevatedButton(
          onPressed: isLoading ? null : _handlePress,
          child: content,
        );
      case FacteurButtonType.secondary:
        return OutlinedButton(
          onPressed: isLoading ? null : _handlePress,
          child: content,
        );
      case FacteurButtonType.text:
        return TextButton(
          onPressed: isLoading ? null : _handlePress,
          child: content,
        );
    }
  }
}
