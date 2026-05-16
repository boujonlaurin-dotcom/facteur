/// Story 22.1 — bottom sheet picker des 4 états d'un intérêt/source.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/user_interests_state.dart';

class InterestStatePickerSheet extends StatelessWidget {
  final String title;
  final InterestState currentState;
  final bool favoriteAvailable;

  const InterestStatePickerSheet({
    super.key,
    required this.title,
    required this.currentState,
    this.favoriteAvailable = true,
  });

  /// Affiche le picker et retourne l'état choisi (ou `null` si annulé).
  static Future<InterestState?> show(
    BuildContext context, {
    required String title,
    required InterestState currentState,
    bool favoriteAvailable = true,
  }) {
    return showModalBottomSheet<InterestState>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => InterestStatePickerSheet(
        title: title,
        currentState: currentState,
        favoriteAvailable: favoriteAvailable,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textTertiary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            _StateOption(
              state: InterestState.favorite,
              label: 'Favori',
              description: favoriteAvailable
                  ? 'En haut de votre flux, jusqu\'à 3'
                  : 'Limite atteinte (3) — retirez-en un d\'abord',
              iconBuilder: (color) => Icon(
                PhosphorIcons.star(PhosphorIconsStyle.fill),
                color: color,
                size: 22,
              ),
              accent: colors.primary,
              isSelected: currentState == InterestState.favorite,
              enabled:
                  favoriteAvailable || currentState == InterestState.favorite,
            ),
            _StateOption(
              state: InterestState.followed,
              label: 'Suivi',
              description: 'Présent dans votre flux',
              iconBuilder: (color) => Icon(
                PhosphorIcons.check(PhosphorIconsStyle.bold),
                color: color,
                size: 22,
              ),
              accent: colors.success,
              isSelected: currentState == InterestState.followed,
              enabled: true,
            ),
            _StateOption(
              state: InterestState.unfollowed,
              label: 'Neutre',
              description: 'Apparaît seulement si très pertinent',
              iconBuilder: (color) => Icon(
                PhosphorIcons.minus(PhosphorIconsStyle.bold),
                color: color,
                size: 22,
              ),
              accent: colors.textSecondary,
              isSelected: currentState == InterestState.unfollowed,
              enabled: true,
            ),
            _StateOption(
              state: InterestState.hidden,
              label: 'Masqué',
              description: 'Ne plus voir dans le flux',
              iconBuilder: (color) => Icon(
                PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
                color: color,
                size: 22,
              ),
              accent: colors.textTertiary,
              isSelected: currentState == InterestState.hidden,
              enabled: true,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _StateOption extends StatelessWidget {
  final InterestState state;
  final String label;
  final String description;
  final Widget Function(Color) iconBuilder;
  final Color accent;
  final bool isSelected;
  final bool enabled;

  const _StateOption({
    required this.state,
    required this.label,
    required this.description,
    required this.iconBuilder,
    required this.accent,
    required this.isSelected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: enabled ? () => Navigator.of(context).pop(state) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.12),
                ),
                alignment: Alignment.center,
                child: iconBuilder(accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  PhosphorIcons.check(PhosphorIconsStyle.bold),
                  color: accent,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
