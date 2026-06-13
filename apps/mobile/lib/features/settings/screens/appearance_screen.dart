import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../onboarding/widgets/theme_choice_bottom_sheet.dart';
import '../providers/display_mode_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/display_mode_bottom_sheet.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final themeMode = ref.watch(themeNotifierProvider);
    final displayMode = ref.watch(displayModeNotifierProvider);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Apparence'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.surfaceElevated),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AppearanceTile(
                icon: PhosphorIcons.palette(PhosphorIconsStyle.regular),
                title: 'Thème',
                subtitle: _themeName(themeMode),
                onTap: () => showThemeChoiceBottomSheet(context, ref),
              ),
              Divider(
                height: 1,
                indent: FacteurSpacing.space4,
                endIndent: FacteurSpacing.space4,
                color: colors.border.withValues(alpha: 0.5),
              ),
              _AppearanceTile(
                icon: PhosphorIcons.article(PhosphorIconsStyle.regular),
                title: 'Affichage des articles',
                subtitle: displayMode.label,
                onTap: () => showDisplayModeBottomSheet(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _themeName(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.light => 'Papier Dessin',
      AppThemeMode.dark => 'Encre & Nuit',
      AppThemeMode.oled => 'Encre Pure',
    };
  }
}

class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Row(
          children: [
            Icon(icon, color: colors.primary, size: 24),
            const SizedBox(width: FacteurSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
              color: colors.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
