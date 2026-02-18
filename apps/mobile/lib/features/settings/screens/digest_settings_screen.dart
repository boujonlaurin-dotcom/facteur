import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../digest/models/digest_mode.dart';
import '../../digest/providers/digest_mode_provider.dart';
import '../../digest/widgets/digest_mode_card.dart';

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
