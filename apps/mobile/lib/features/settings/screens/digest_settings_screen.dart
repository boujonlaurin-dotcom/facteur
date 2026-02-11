import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../digest/models/digest_mode.dart';
import '../../digest/providers/digest_mode_provider.dart';

/// Écran Settings > Mon Essentiel
/// Permet de configurer le mode du digest avec descriptions étendues.
class DigestSettingsScreen extends ConsumerWidget {
  const DigestSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final modeState = ref.watch(digestModeProvider);

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

            // 3 mode cards (theme_focus déprécié)
            ...DigestMode.values.map((mode) {
              final isSelected = mode == modeState.mode;
              final modeColor = mode.effectiveColor(colors.primary);

              return Padding(
                padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
                child: _ModeCard(
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
                    'Tu peux aussi changer de mode directement depuis le digest.',
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

class _ModeCard extends StatelessWidget {
  final DigestMode mode;
  final bool isSelected;
  final Color modeColor;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _ModeCard({
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
