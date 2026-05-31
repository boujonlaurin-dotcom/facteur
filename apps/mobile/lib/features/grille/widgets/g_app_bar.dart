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
  });

  final bool showBack;
  final int streak;
  final String title;
  final VoidCallback? onBack;

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
          SizedBox(
            width: 36,
            child: streak > 0
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
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
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
