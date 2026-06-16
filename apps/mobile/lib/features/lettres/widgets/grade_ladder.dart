import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/facteur_grade.dart';

/// Échelle visible des 6 grades de facteur, non interactive :
/// - grades atteints → cochés, couleur pleine ;
/// - grade courant → mis en avant (couleur primaire) ;
/// - grades futurs → verrouillés / grisés (cadenas).
class GradeLadder extends StatelessWidget {
  final FacteurGrade grade;

  const GradeLadder({super.key, required this.grade});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < facteurLadder.length; i++)
            _GradeRow(
              // level dans FacteurGrade est 1-indexé (index + 1).
              title: facteurLadder[i].title,
              reached: (i + 1) < grade.level,
              current: (i + 1) == grade.level,
            ),
        ],
      ),
    );
  }
}

class _GradeRow extends StatelessWidget {
  final String title;
  final bool reached;
  final bool current;

  const _GradeRow({
    required this.title,
    required this.reached,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final locked = !reached && !current;

    final Color leadingColor;
    final IconData icon;
    if (current) {
      leadingColor = colors.primary;
      icon = PhosphorIcons.mapPin(PhosphorIconsStyle.fill);
    } else if (reached) {
      leadingColor = colors.textSecondary;
      icon = PhosphorIcons.checkCircle(PhosphorIconsStyle.fill);
    } else {
      leadingColor = colors.textTertiary;
      icon = PhosphorIcons.lock(PhosphorIconsStyle.regular);
    }

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: leadingColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                color: current
                    ? colors.primary
                    : (reached ? colors.textPrimary : colors.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );

    return locked ? Opacity(opacity: 0.55, child: row) : row;
  }
}
