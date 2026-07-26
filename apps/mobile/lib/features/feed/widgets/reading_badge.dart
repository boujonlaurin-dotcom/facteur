import 'package:facteur/config/theme.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/content_model.dart';

/// Badge d'état de lecture sur les cartes article.
///
/// Deux états seulement — « Lu » (ouvert) et « Lu jusqu'au bout » (complété) —
/// adossés à `completedAt` et non plus à `readingProgress`, qui est plafonné à
/// 25 pour ~90 % du catalogue et affichait donc « Parcouru » sur des lectures
/// pourtant menées à leur terme.
///
/// Le niveau « Parcouru » (icône `eye`, gris) a été retiré : ce n'est pas un
/// accomplissement, et le nommer revient à commenter la lecture superficielle
/// de l'utilisateur. L'opacité de la carte suffit à le signaler.
class ReadingBadge extends StatelessWidget {
  final Content content;

  const ReadingBadge({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final label = content.readingLabel;
    if (label == null) return const SizedBox.shrink();

    final colors = context.facteurColors;

    final Color bgColor = colors.success;
    const Color fgColor = Colors.white;
    final IconData icon = content.isCompleted
        ? PhosphorIcons.checks(PhosphorIconsStyle.bold)
        : PhosphorIcons.checkCircle(PhosphorIconsStyle.fill);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
