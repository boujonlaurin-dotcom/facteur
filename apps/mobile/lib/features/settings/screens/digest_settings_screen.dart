import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../digest/models/digest_mode.dart';
import '../../digest/providers/digest_format_provider.dart';
import '../../digest/providers/digest_mode_provider.dart';
import '../../digest/widgets/digest_mode_card.dart';

/// Écran Settings > Mon Essentiel
/// Permet de configurer le mode et le format du digest.
class DigestSettingsScreen extends ConsumerWidget {
  const DigestSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modeState = ref.watch(digestModeProvider);
    final currentFormat = ref.watch(digestFormatProvider);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Mon Essentiel'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mode de votre essentiel',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space3),

            // 3 mode cards
            ...DigestMode.values.map((mode) {
              final isSelected = mode == modeState.mode;
              final modeColor = mode.effectiveColor(colors.primary);

              return Padding(
                padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
                child: DigestModeCard(
                  mode: mode,
                  isSelected: isSelected,
                  modeColor: modeColor,
                  colors: colors,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(digestModeProvider.notifier).setMode(mode);
                  },
                ),
              );
            }),

            const SizedBox(height: FacteurSpacing.space6),

            // Format section
            Text(
              'Format d\u2019affichage',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space3),

            ...DigestFormat.values.map((format) {
              final isSelected = format == currentFormat;
              return Padding(
                padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
                child: _DigestFormatCard(
                  format: format,
                  isSelected: isSelected,
                  colors: colors,
                  isDark: isDark,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(digestFormatProvider.notifier).setFormat(format);
                  },
                ),
              );
            }),

            const SizedBox(height: FacteurSpacing.space6),

            // Info text
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIcons.info(PhosphorIconsStyle.regular),
                  size: 16,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ton essentiel est généré chaque matin à 8h avec ce mode. '
                    'Le changement sera appliqué dès demain.',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                      fontFamily: 'DM Sans',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact card for digest format selection.
class _DigestFormatCard extends StatelessWidget {
  final DigestFormat format;
  final bool isSelected;
  final FacteurColors colors;
  final bool isDark;
  final VoidCallback onTap;

  const _DigestFormatCard({
    required this.format,
    required this.isSelected,
    required this.colors,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? colors.primary
        : isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.08);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: isDark ? 0.12 : 0.08)
              : colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
              format == DigestFormat.topics
                  ? PhosphorIcons.squaresFour(PhosphorIconsStyle.fill)
                  : PhosphorIcons.listBullets(PhosphorIconsStyle.fill),
              size: 22,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    format.label,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      fontFamily: 'DM Sans',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    format.description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontFamily: 'DM Sans',
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                size: 20,
                color: colors.primary,
              ),
          ],
        ),
      ),
    );
  }
}
