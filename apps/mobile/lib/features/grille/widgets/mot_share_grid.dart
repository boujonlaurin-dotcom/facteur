import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/grille_models.dart';
import '../models/tile_state.dart';

/// Grille de partage (`.mot-share-grid`) : carrés de couleur **sans lettre**
/// (façon Wordle) → partageable sans spoiler.
class MotShareGrid extends StatelessWidget {
  const MotShareGrid({super.key, required this.essais});

  final List<GrilleEssai> essais;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < essais.length; r++) ...[
          _row(context, essais[r]),
          if (r < essais.length - 1) const SizedBox(height: 5),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, GrilleEssai essai) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < essai.etats.length; i++) ...[
          _cell(context, TileStateX.fromServer(essai.etats[i])),
          if (i < essai.etats.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }

  Widget _cell(BuildContext context, TileState state) {
    final c = context.facteurColors;
    Color color;
    switch (state) {
      case TileState.place:
        color = c.success;
      case TileState.present:
        color = c.primary;
      default:
        color = GrilleConstants.absentGrille;
    }
    return Container(
      width: GrilleConstants.shareCellSize,
      height: GrilleConstants.shareCellSize,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(GrilleConstants.shareCellRadius),
      ),
    );
  }
}
