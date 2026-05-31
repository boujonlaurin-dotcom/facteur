import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Barre supérieure de La Grille (`.g-appbar`) : back · wordmark · streak.
class GAppBar extends StatelessWidget {
  const GAppBar({
    super.key,
    this.showBack = true,
    this.streak = 0,
    this.title = 'Facteur',
    this.onBack,
    this.onHelp,
  });

  final bool showBack;
  final int streak;
  final String title;
  final VoidCallback? onBack;

  /// Si fourni, affiche une icône « ? » (côté droit) qui ouvre l'intro du jeu.
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: showBack
                ? IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      PhosphorIcons.arrowLeft(),
                      size: 19,
                      color: c.textSecondary,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: GoogleFonts.fraunces(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 36),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (streak > 0) ...[
                  Icon(
                    PhosphorIcons.fire(PhosphorIconsStyle.fill),
                    size: 16,
                    color: c.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$streak',
                    style: FacteurTypography.bodySmall(c.textSecondary)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
                if (onHelp != null) ...[
                  if (streak > 0) const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: onHelp,
                      tooltip: 'Comment jouer',
                      icon: Icon(
                        PhosphorIcons.info(),
                        size: 19,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
