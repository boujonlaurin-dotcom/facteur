import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../settings/providers/theme_provider.dart';

/// Bottom sheet de choix de thème (3 options : Clair / Sombre / Encre Pure).
///
/// Comportement : prévisualisation live sur tap d'une option (le thème
/// s'applique à toute l'app), choix entériné par le bouton « Confirmer ».
/// Si l'utilisateur ferme la sheet sans confirmer (swipe down / tap barrière),
/// le thème initial est restauré.
Future<void> showThemeChoiceBottomSheet(
    BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(themeNotifierProvider.notifier);
  final initialTheme = ref.read(themeNotifierProvider);

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.facteurColors.scrim,
    builder: (ctx) => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: _ThemeChoiceContent(initialTheme: initialTheme),
      ),
    ),
  );

  // Dismiss sans confirmation : on restaure visuellement le thème d'avant,
  // sans toucher à la persistance (qui n'a jamais bougé pendant la preview).
  if (confirmed != true) {
    notifier.previewThemeMode(initialTheme);
  }
}

class _ThemeChoiceContent extends ConsumerWidget {
  final AppThemeMode initialTheme;

  const _ThemeChoiceContent({required this.initialTheme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final current = ref.watch(themeNotifierProvider);

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
              Expanded(
                child: _ThemeOption(
                  icon: Icons.wb_sunny_outlined,
                  label: 'Clair',
                  isSelected: current == AppThemeMode.light,
                  onTap: () => ref
                      .read(themeNotifierProvider.notifier)
                      .previewThemeMode(AppThemeMode.light),
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Expanded(
                child: _ThemeOption(
                  icon: Icons.dark_mode_outlined,
                  label: 'Sombre',
                  isSelected: current == AppThemeMode.dark,
                  onTap: () => ref
                      .read(themeNotifierProvider.notifier)
                      .previewThemeMode(AppThemeMode.dark),
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Expanded(
                child: _ThemeOption(
                  icon: Icons.contrast,
                  label: 'Encre Pure',
                  isSelected: current == AppThemeMode.oled,
                  onTap: () => ref
                      .read(themeNotifierProvider.notifier)
                      .previewThemeMode(AppThemeMode.oled),
                ),
              ),
            ],
          ),

          const SizedBox(height: FacteurSpacing.space6),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ref.read(themeNotifierProvider.notifier).commitThemeMode(
                      initial: initialTheme,
                      chosen: current,
                    );
                Navigator.of(context).pop(true);
              },
              child: const Text('Confirmer'),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space2),
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: FacteurSpacing.space4,
          horizontal: FacteurSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withOpacity(0.1)
              : colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(
            color: isSelected
                ? colors.primary.withOpacity(0.5)
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
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
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
