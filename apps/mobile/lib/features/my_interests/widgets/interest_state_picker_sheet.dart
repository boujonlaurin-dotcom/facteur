/// Story 22.1 — bottom sheet picker des 4 états d'un intérêt/source.
library;

import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../models/user_interests_state.dart';

class InterestStatePickerSheet extends StatelessWidget {
  final String title;
  final InterestState currentState;
  final bool allowFavorite;

  const InterestStatePickerSheet({
    super.key,
    required this.title,
    required this.currentState,
    this.allowFavorite = true,
  });

  /// Affiche le picker et retourne l'état choisi (ou `null` si annulé).
  static Future<InterestState?> show(
    BuildContext context, {
    required String title,
    required InterestState currentState,
    bool allowFavorite = true,
  }) {
    return showModalBottomSheet<InterestState>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => InterestStatePickerSheet(
        title: title,
        currentState: currentState,
        allowFavorite: allowFavorite,
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
            for (final state in [
              if (allowFavorite) InterestState.favorite,
              InterestState.followed,
              InterestState.unfollowed,
              InterestState.hidden,
            ])
              _StateOption(
                state: state,
                accent: state.accent(colors),
                isSelected: currentState == state,
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
  final Color accent;
  final bool isSelected;

  const _StateOption({
    required this.state,
    required this.accent,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => Navigator.of(context).pop(state),
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
              child: Icon(state.iconData, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.label,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.description,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check, color: accent, size: 18),
          ],
        ),
      ),
    );
  }
}
