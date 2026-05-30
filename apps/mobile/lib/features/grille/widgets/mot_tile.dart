import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/tile_state.dart';
import 'dashed_border.dart';

/// Couleurs résolues d'une tuile selon son [TileState] (tokens + hors-token).
class _TileColors {
  const _TileColors(this.background, this.border, this.foreground);
  final Color background;
  final Color border;
  final Color foreground;

  static _TileColors of(BuildContext context, TileState state) {
    final c = context.facteurColors;
    switch (state) {
      case TileState.place:
        return _TileColors(c.success, c.success, Colors.white);
      case TileState.present:
        return _TileColors(c.primary, c.primary, Colors.white);
      case TileState.absent:
        return const _TileColors(
          GrilleConstants.absentGrille,
          GrilleConstants.absentGrille,
          Colors.white,
        );
      case TileState.hint:
        return _TileColors(
          c.primary.withValues(alpha: 0.04),
          c.primary,
          c.primary,
        );
      case TileState.filled:
        return _TileColors(c.surfacePaper, c.textSecondary, c.textPrimary);
      case TileState.empty:
        return _TileColors(c.surfacePaper, c.border, c.textPrimary);
    }
  }
}

/// Une case de la grille « Le mot du jour ».
///
/// Géométrie fidèle à `.mt-tile` (grille.css) : rayon 6, bord 1.5, lettre serif
/// `size*0.52`. La case `filled` grossit légèrement (`scale 1.02`), la `hint`
/// a un bord pointillé primary, la `place` porte le sceau `mt-seal` (liseré
/// pointillé blanc en retrait).
class MotTile extends StatelessWidget {
  const MotTile({
    super.key,
    required this.state,
    this.letter = '',
    this.size = GrilleConstants.tileSize,
  });

  final TileState state;
  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = _TileColors.of(context, state);
    final isHint = state == TileState.hint;
    final isFilled = state == TileState.filled;

    final content = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(GrilleConstants.tileRadius),
        border: isHint
            ? null
            : Border.all(color: colors.border, width: 1.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Bord pointillé pour la case « première lettre offerte ».
          if (isHint)
            Positioned.fill(
              child: CustomPaint(
                painter: DashedRRectPainter(
                  color: colors.border,
                  strokeWidth: 1.5,
                  radius: GrilleConstants.tileRadius,
                ),
              ),
            ),
          // Sceau « bonne adresse » sur les lettres livrées.
          if (state == TileState.place)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: CustomPaint(
                  painter: DashedRRectPainter(
                    color: Colors.white.withValues(alpha: 0.45),
                    strokeWidth: 1,
                    radius: 3,
                  ),
                ),
              ),
            ),
          Text(
            letter.toUpperCase(),
            style: GoogleFonts.fraunces(
              fontSize: size * 0.52,
              fontWeight: FontWeight.w700,
              height: 1,
              color: colors.foreground,
            ),
          ),
        ],
      ),
    );

    if (isFilled) {
      return Transform.scale(scale: 1.02, child: content);
    }
    return content;
  }
}
