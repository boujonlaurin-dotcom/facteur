import 'package:flutter/material.dart';

import '../../../../config/theme.dart';

/// Barre de progression **segmentée** du header du reader — un segment par
/// article de la section (Story 34.1).
///
/// C'est le seul repère de position du deck : il réutilise la barre déjà
/// présente dans le header plutôt que d'y ajouter un compteur, et dit d'un coup
/// d'œil combien d'articles restent derrière celui-ci — y compris ceux que la
/// Tournée n'affichait pas.
///
/// **Le segment courant compte pour *atteint*** : à l'article k, k segments
/// portent de l'encre, donc au dernier la barre est pleine de bout en bout. Ne
/// peindre que les articles passés laissait au dernier article une case vide en
/// permanence — la séquence n'y finissait jamais.
class DeckProgressBar extends StatelessWidget {
  const DeckProgressBar({
    super.key,
    required this.index,
    required this.length,
    required this.progress,
    required this.completed,
  });

  /// Position de l'article courant dans la section.
  final int index;

  /// Nombre d'articles de la section.
  final int length;

  /// Progression de lecture de l'article courant, entre 0 et 1.
  final double progress;

  /// Article courant terminé (latch de complétion du reader).
  final bool completed;

  /// Clé du segment d'index [i], pour les tests.
  static ValueKey<String> segmentKey(int i) =>
      ValueKey<String>('deck-segment-$i');

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final barHeight = completed ? 6.0 : 3.5;
    final target = completed ? colors.success : colors.primary;
    final trackColor = colors.textTertiary.withValues(alpha: 0.12);
    // Article déjà lu dans la séquence : présent mais en retrait, il ne
    // concurrence pas le courant.
    final pastColor = colors.success.withValues(alpha: 0.45);
    // Aplat « atteint » de l'article courant : plus clair que sa progression de
    // lecture, qui le remplit par-dessus.
    final reachedColor = target.withValues(alpha: 0.3);
    final progressColor = target.withValues(
      alpha: completed ? 0.9 : 0.15 + (progress.clamp(0.0, 1.0) * 0.35),
    );

    return SizedBox(
      height: barHeight,
      child: Row(
        children: [
          for (var i = 0; i < length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: ClipRRect(
                key: segmentKey(i),
                borderRadius: BorderRadius.circular(barHeight),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: trackColor),
                    if (i <= index)
                      ColoredBox(color: i < index ? pastColor : reachedColor),
                    // Progression de lecture, sur le segment courant seulement.
                    // Un article terminé remplit son segment même si le scroll
                    // s'est arrêté avant le bas (latch de complétion).
                    if (i == index)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor:
                              completed ? 1.0 : progress.clamp(0.0, 1.0),
                          heightFactor: 1,
                          child: ColoredBox(color: progressColor),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
