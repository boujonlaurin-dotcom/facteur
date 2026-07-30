import 'package:facteur/config/theme.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/content_model.dart';

/// Badge d'état de lecture sur les cartes article.
///
/// Trois marches sur un spectre d'engagement (cf. [ReadState]) — « Ouvert »,
/// « Lu en partie » et « Lu jusqu'au bout ». Piloté par [readState] quand la
/// carte le fournit (état serveur fusionné avec la session), sinon retombe sur
/// `content.readState`.
class ReadingBadge extends StatelessWidget {
  final Content content;

  /// État effectif (fusion session incluse). `null` → dérivé de [content].
  final ReadState? readState;

  const ReadingBadge({super.key, required this.content, this.readState});

  @override
  Widget build(BuildContext context) {
    final state = readState ?? content.readState;
    final label = readingLabelForState(state, isVideo: content.isVideo);
    if (label == null) return const SizedBox.shrink();

    final colors = context.facteurColors;

    final Color bgColor = colors.success;
    const Color fgColor = Colors.white;
    final IconData icon = state == ReadState.completed
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
