/// Story 22.1 — bottom sheet picker des 4 états d'un intérêt/source.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/user_interests_state.dart';

/// Habillage de l'état `favorite` dans le picker.
///
/// - [theme] : étoile + "Favori (Tournée du jour)". S'applique aux thèmes et
///   aux veilles draggable dans le top 3.
/// - [pinnedTopic] : punaise + "Épinglé (apparaît dans Explorer)". S'applique
///   aux sujets personnalisés qui alimentent les onglets de la section
///   Explorer sans entrer dans le top 3 de la Tournée du jour.
enum FavoriteSemantics { theme, pinnedTopic }

class InterestStatePickerSheet extends StatelessWidget {
  final String title;
  final InterestState currentState;
  final bool allowFavorite;
  final FavoriteSemantics favoriteSemantics;

  const InterestStatePickerSheet({
    super.key,
    required this.title,
    required this.currentState,
    this.allowFavorite = true,
    this.favoriteSemantics = FavoriteSemantics.theme,
  });

  /// Affiche le picker et retourne l'état choisi (ou `null` si annulé).
  static Future<InterestState?> show(
    BuildContext context, {
    required String title,
    required InterestState currentState,
    bool allowFavorite = true,
    FavoriteSemantics favoriteSemantics = FavoriteSemantics.theme,
  }) {
    return showModalBottomSheet<InterestState>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => InterestStatePickerSheet(
        title: title,
        currentState: currentState,
        allowFavorite: allowFavorite,
        favoriteSemantics: favoriteSemantics,
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
                favoriteSemantics: favoriteSemantics,
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
  final FavoriteSemantics favoriteSemantics;

  const _StateOption({
    required this.state,
    required this.accent,
    required this.isSelected,
    required this.favoriteSemantics,
  });

  bool get _isPinnedTopic =>
      state == InterestState.favorite &&
      favoriteSemantics == FavoriteSemantics.pinnedTopic;

  String get _label =>
      _isPinnedTopic ? 'Épinglé' : state.label;

  String get _description => _isPinnedTopic
      ? 'Apparaît comme onglet dans la section Flâner.'
      : state.description;

  IconData get _icon =>
      _isPinnedTopic ? PhosphorIcons.pushPin(PhosphorIconsStyle.fill) : state.iconData;

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
              child: Icon(_icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _description,
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
