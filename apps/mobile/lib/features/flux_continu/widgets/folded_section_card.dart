import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Compact "menu-list" version of [SectionBanner] used when the user has
/// already consumed a section. Identity reduces to: section title, article
/// count, chevron — over the bare parchment, with a hairline separator.
/// No accent fill, no illustration: the card recedes to pure navigation
/// once the day's content has been read.
class FoldedSectionCard extends StatelessWidget {
  final String title;
  final int? articleCount;
  final VoidCallback? onTap;

  /// When true, prefix the title with a small green check, matching the v3
  /// spec for the folded "L'Essentiel du jour" ruban. Kept opt-in so the
  /// existing digest sections (essentiel legacy, bonnes) stay unchanged.
  final bool showCheck;

  const FoldedSectionCard({
    super.key,
    required this.title,
    this.articleCount,
    this.onTap,
    this.showCheck = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 6, 18, 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colors.textPrimary.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showCheck) ...[
                Icon(Icons.check, size: 16, color: colors.success),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.fraunces(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    letterSpacing: -0.3,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (articleCount != null) ...[
                const SizedBox(width: 10),
                Text(
                  '$articleCount',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary.withValues(alpha: 0.40),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: colors.textPrimary.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
