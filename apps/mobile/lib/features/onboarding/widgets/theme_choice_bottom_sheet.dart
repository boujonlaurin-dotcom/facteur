import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../settings/providers/theme_provider.dart';

/// Shows a bottom sheet to let the user choose between light and dark mode
/// after onboarding completion.
Future<void> showThemeChoiceBottomSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: _ThemeChoiceContent(ref: ref),
    ),
  );
}

class _ThemeChoiceContent extends StatelessWidget {
  final WidgetRef ref;

  const _ThemeChoiceContent({required this.ref});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space6),
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FacteurRadius.large),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space6),

          Text(
            'Comment préférez-vous lire ?',
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          Row(
            children: [
              // Light mode
              Expanded(
                child: _ThemeOption(
                  icon: Icons.wb_sunny_outlined,
                  label: 'Clair',
                  isSelected:
                      Theme.of(context).brightness == Brightness.light,
                  onTap: () {
                    ref
                        .read(themeNotifierProvider.notifier)
                        .setThemeMode(ThemeMode.light);
                    Navigator.of(context).pop();
                  },
                ),
              ),

              const SizedBox(width: FacteurSpacing.space4),

              // Dark mode
              Expanded(
                child: _ThemeOption(
                  icon: Icons.dark_mode_outlined,
                  label: 'Sombre',
                  isSelected:
                      Theme.of(context).brightness == Brightness.dark,
                  onTap: () {
                    ref
                        .read(themeNotifierProvider.notifier)
                        .setThemeMode(ThemeMode.dark);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: FacteurSpacing.space6),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: FacteurSpacing.space6,
          horizontal: FacteurSpacing.space4,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.5)
                : colors.surfaceElevated,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isSelected ? colors.primary : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
