import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/grille/widgets/dashed_border.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Pastille d'état de lecture d'un article, sur un spectre à trois marches
/// (cf. [ReadState]) :
/// - **[ReadState.opened]** : cercle **non plein**, contour **pointillé** vert,
///   coche verte → « ouvert, à peine parcouru », signal secondaire.
/// - **[ReadState.partiallyRead]** : cercle plein, simple coche blanche.
/// - **[ReadState.completed]** : cercle plein, double coche blanche.
///
/// Widget partagé et non recopié : la duplication précédente avait déjà produit
/// un bug — la copie de la carte Essentiel codait `check` en dur, donc était
/// structurellement incapable d'afficher une complétion. Le choix de la variante
/// ne doit vivre qu'à un seul endroit.
///
/// [ReadState.unread] ne rend rien : les cartes n'instancient la pastille que
/// pour un article lu.
class ReadStateMark extends StatelessWidget {
  const ReadStateMark({
    super.key,
    required this.color,
    required this.state,
    this.size = 22,
  });

  /// Token couleur (palette `success`) — jamais une couleur brute.
  final Color color;

  /// Marche du spectre de lecture. `unread` → widget vide.
  final ReadState state;

  final double size;

  @override
  Widget build(BuildContext context) {
    if (state == ReadState.unread) return const SizedBox.shrink();

    // Variante « Ouvert » : contour pointillé, fond quasi transparent, coche
    // verte — délibérément moins affirmée que la coche pleine des marches
    // supérieures.
    if (state == ReadState.opened) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size(size, size),
          painter: DashedRRectPainter(
            color: color,
            radius: size / 2,
            strokeWidth: 1.5,
            dashLength: 2.5,
            gapLength: 2,
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Icon(
                PhosphorIcons.check(PhosphorIconsStyle.bold),
                size: size * 0.55,
                color: color,
              ),
            ),
          ),
        ),
      );
    }

    // Variantes « Lu en partie » / « Lu jusqu'au bout » : cercle plein, icône
    // blanche (simple vs double coche).
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        state == ReadState.completed
            ? PhosphorIcons.checks(PhosphorIconsStyle.bold)
            : PhosphorIcons.check(PhosphorIconsStyle.bold),
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }
}
