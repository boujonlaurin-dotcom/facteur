import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../providers/display_mode_provider.dart';

/// Bottom sheet de choix du mode d'affichage des articles (Normal /
/// Minimaliste / Ludique). Même contrat que la sheet de thème
/// (`theme_choice_bottom_sheet.dart`) : prévisualisation live sur tap d'une
/// option (le feed derrière la sheet se re-render), choix entériné par
/// « Confirmer », restauration du mode initial si dismiss sans confirmer.
Future<void> showDisplayModeBottomSheet(
    BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(displayModeNotifierProvider.notifier);
  final initialMode = ref.read(displayModeNotifierProvider);

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.facteurColors.scrim,
    builder: (ctx) => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: _DisplayModeChoiceContent(initialMode: initialMode),
      ),
    ),
  );

  if (confirmed != true) {
    notifier.previewDisplayMode(initialMode);
  }
}

class _DisplayModeChoiceContent extends ConsumerWidget {
  final DisplayMode initialMode;

  const _DisplayModeChoiceContent({required this.initialMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final current = ref.watch(displayModeNotifierProvider);

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
            'Comment veux-tu voir tes articles ?',
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Text(
            _subtitleFor(current),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FacteurSpacing.space6),
          Row(
            children: [
              for (final mode in DisplayMode.values) ...[
                if (mode != DisplayMode.values.first)
                  const SizedBox(width: FacteurSpacing.space2),
                Expanded(
                  child: _DisplayModeOption(
                    icon: _iconFor(mode),
                    label: mode.label,
                    isSelected: current == mode,
                    onTap: () => ref
                        .read(displayModeNotifierProvider.notifier)
                        .previewDisplayMode(mode),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: FacteurSpacing.space6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ref.read(displayModeNotifierProvider.notifier).commitDisplayMode(
                      initial: initialMode,
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

  IconData _iconFor(DisplayMode mode) => switch (mode) {
        DisplayMode.normal => Icons.view_agenda_outlined,
        DisplayMode.minimal => Icons.notes,
        DisplayMode.playful => Icons.image_outlined,
      };

  String _subtitleFor(DisplayMode mode) => switch (mode) {
        DisplayMode.normal => 'L\'équilibre texte et images, tel quel.',
        DisplayMode.minimal => 'Juste le texte, plus compact, sans images.',
        DisplayMode.playful => 'Images en grand et titres plus lisibles.',
      };
}

class _DisplayModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DisplayModeOption({
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
