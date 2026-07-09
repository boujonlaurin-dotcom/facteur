/// Curseur 4-états réutilisable (Masqué → Neutre → Suivi → Favori).
///
/// Extrait verbatim de `_SourcePrioritySlider` (fiche source) pour homogénéiser
/// l'expérience thèmes / sujets de « Mes intérêts » avec la fiche source. Le
/// widget est **présentationnel** (sans dépendance provider) : il expose la
/// position optimiste pendant le drag et persiste via le callback `onChanged`
/// appelé sur `onChangeEnd`. La resynchronisation sur l'état réel (rollback
/// inclus) est portée par le parent qui repasse `value`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../models/user_interests_state.dart';
import '../providers/user_interests_provider.dart';
import 'interest_state_picker_sheet.dart'
    show FavoriteSemantics, InterestStateSemantics;

/// Curseur 4 points présentationnel. Chaque cran porte l'icône/couleur de son
/// [InterestState] ; le libellé + la description du cran courant s'actualisent
/// sous la piste au fil du glissement. `favoriteSemantics` bascule le cran
/// « Favori » vers « Épinglé » + punaise pour les sujets personnalisés.
class InterestPrioritySlider extends StatefulWidget {
  final InterestState value;
  final ValueChanged<InterestState> onChanged;
  final FavoriteSemantics favoriteSemantics;

  const InterestPrioritySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.favoriteSemantics = FavoriteSemantics.theme,
  });

  @override
  State<InterestPrioritySlider> createState() => _InterestPrioritySliderState();
}

class _InterestPrioritySliderState extends State<InterestPrioritySlider> {
  // Ordre gauche → droite du curseur.
  static const List<InterestState> _order = [
    InterestState.hidden,
    InterestState.unfollowed,
    InterestState.followed,
    InterestState.favorite,
  ];

  // Position optimiste pendant le drag (null = on suit `widget.value`).
  int? _pendingIndex;

  // Cran par défaut si `widget.value` sort de `_order` (indexOf == -1).
  static final int _defaultIndex = _order.indexOf(InterestState.followed);

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final providerIndex = _order.indexOf(widget.value);
    final index = _pendingIndex ?? (providerIndex < 0 ? _defaultIndex : providerIndex);
    final state = _order[index];
    final accent = state.accent(colors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: accent,
            inactiveTrackColor: colors.textPrimary.withValues(alpha: 0.12),
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            tickMarkShape: SliderTickMarkShape.noTickMark,
          ),
          child: Slider(
            value: index.toDouble(),
            min: 0,
            max: (_order.length - 1).toDouble(),
            divisions: _order.length - 1,
            onChanged: (v) => setState(() => _pendingIndex = v.round()),
            onChangeEnd: (v) {
              final picked = _order[v.round()];
              setState(() => _pendingIndex = null);
              if (picked != widget.value) widget.onChanged(picked);
            },
          ),
        ),
        // Icône + libellé court sous chaque point.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              for (var i = 0; i < _order.length; i++)
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        _order[i].iconFor(widget.favoriteSemantics),
                        size: 15,
                        color: i == index
                            ? _order[i].accent(colors)
                            : colors.textTertiary,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _order[i].labelFor(widget.favoriteSemantics),
                        textAlign: TextAlign.center,
                        style: textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          letterSpacing: 0,
                          color: i == index
                              ? _order[i].accent(colors)
                              : colors.textTertiary,
                          fontWeight:
                              i == index ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Description du statut courant, mise à jour au slide.
        Text(
          state.descriptionFor(widget.favoriteSemantics),
          style: textTheme.labelSmall?.copyWith(
            color: colors.textSecondary,
            fontSize: 12,
            height: 1.4,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet hébergeant [InterestPrioritySlider] pour un thème / sujet de
/// « Mes intérêts ». Même habillage que [InterestStatePickerSheet] (poignée +
/// titre). Le sheet reste ouvert et applique **en direct** via `onChanged`
/// (parité exacte avec la fiche source) ; l'utilisateur ferme via la
/// poignée / le scrim. La position se resynchronise sur `userInterestsProvider`
/// (rollback compris) car le curseur relit `stateOf(refTarget)` à chaque build.
class InterestStateSliderSheet extends ConsumerWidget {
  final String title;
  final FavoriteRef refTarget;
  final FavoriteSemantics favoriteSemantics;
  final ValueChanged<InterestState> onChanged;

  const InterestStateSliderSheet({
    super.key,
    required this.title,
    required this.refTarget,
    required this.onChanged,
    this.favoriteSemantics = FavoriteSemantics.theme,
  });

  /// Affiche le curseur en bottom sheet. Applique en direct via [onChanged].
  static Future<void> show(
    BuildContext context, {
    required String title,
    required FavoriteRef refTarget,
    required ValueChanged<InterestState> onChanged,
    FavoriteSemantics favoriteSemantics = FavoriteSemantics.theme,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => InterestStateSliderSheet(
        title: title,
        refTarget: refTarget,
        onChanged: onChanged,
        favoriteSemantics: favoriteSemantics,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final currentState = ref.watch(userInterestsProvider).valueOrNull
            ?.stateOf(refTarget) ??
        InterestState.unfollowed;

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
                color: colors.textTertiary.withValues(alpha: 0.3),
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
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: InterestPrioritySlider(
                value: currentState,
                favoriteSemantics: favoriteSemantics,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
