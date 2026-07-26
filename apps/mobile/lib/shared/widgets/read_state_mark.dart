import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Pastille d'état de lecture d'un article : simple coche s'il a été ouvert,
/// double coche s'il a été lu **jusqu'au bout**.
///
/// Widget partagé et non recopié : la duplication précédente avait déjà produit
/// un bug — la copie de la carte Essentiel codait `check` en dur, donc était
/// structurellement incapable d'afficher une complétion. Le choix
/// `check`/`checks` ne doit vivre qu'à un seul endroit.
///
/// Ne rend rien de plus pour un article non abouti : même taille, même couleur,
/// un chevron de plus. Aucun état vide, aucun contre-signal.
class ReadStateMark extends StatelessWidget {
  const ReadStateMark({
    super.key,
    required this.color,
    this.isCompleted = false,
    this.size = 22,
  });

  final Color color;

  /// Lu jusqu'au bout (`completedAt != null`), pas seulement ouvert — ce que le
  /// seuil d'1 s suffit à déclencher.
  final bool isCompleted;

  final double size;

  @override
  Widget build(BuildContext context) {
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
        isCompleted
            ? PhosphorIcons.checks(PhosphorIconsStyle.bold)
            : PhosphorIcons.check(PhosphorIconsStyle.bold),
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }
}
