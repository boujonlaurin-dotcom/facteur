import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Banner that opens a Flux Continu V1.8 section.
///
/// Visual: subtle gradient tinted with [accent], a 28×2 rule line on the
/// left, a small placeholder illustration tile, and a Fraunces title with
/// an optional blurb. Illustrations are intentionally minimal at MVP —
/// real PNGs will be wired in once the design team delivers them.
class SectionBanner extends StatelessWidget {
  final String title;
  final String? blurb;
  final Color accent;
  final IconData icon;

  const SectionBanner({
    super.key,
    required this.title,
    required this.accent,
    this.blurb,
    this.icon = Icons.article_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        FacteurSpacing.space4,
        FacteurSpacing.space2,
        FacteurSpacing.space4,
        FacteurSpacing.space3,
      ),
      padding: const EdgeInsets.fromLTRB(
        FacteurSpacing.space4,
        FacteurSpacing.space4,
        FacteurSpacing.space4,
        FacteurSpacing.space4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.12),
            accent.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 2,
            margin: const EdgeInsets.only(right: FacteurSpacing.space3),
            color: accent,
          ),
          _IllustrationTile(accent: accent, icon: icon),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: accent,
                  ),
                ),
                if (blurb != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    blurb!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.4,
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

class _IllustrationTile extends StatelessWidget {
  final Color accent;
  final IconData icon;

  const _IllustrationTile({required this.accent, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: accent, size: 22),
    );
  }
}
