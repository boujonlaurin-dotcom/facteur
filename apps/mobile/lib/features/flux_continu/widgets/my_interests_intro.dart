import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Typographic divider inserted once in the Flux Continu feed, right before
/// the first user-favorite theme section. Tells the user that the next
/// section(s) are configurable and offers a ghost CTA that opens the same
/// bottom sheet as the inline favorite stars on the banners themselves.
class MyInterestsIntro extends StatelessWidget {
  final int favoriteCount;
  final VoidCallback onTapManage;

  const MyInterestsIntro({
    super.key,
    required this.favoriteCount,
    required this.onTapManage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // The hero-card padding is 22px horizontally — match it so the rule lines
    // up with the title/blurb edge of the section banner that follows.
    final label = favoriteCount > 1
        ? 'TES $favoriteCount THÈMES FAVORIS'
        : 'TON THÈME FAVORI';
    final stampStyle = GoogleFonts.dmSans(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: colors.textStamp,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            PhosphorIcons.star(PhosphorIconsStyle.fill),
            size: 11,
            color: colors.textStamp,
          ),
          const SizedBox(width: 6),
          Text(label, style: stampStyle),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: colors.textPrimary.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(width: 10),
          _ManageButton(onTap: onTapManage, colors: colors),
        ],
      ),
    );
  }
}

class _ManageButton extends StatelessWidget {
  final VoidCallback onTap;
  final FacteurColors colors;

  const _ManageButton({required this.onTap, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 5, 10, 5),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'GÉRER',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                PhosphorIcons.caretRight(),
                size: 11,
                color: colors.textPrimary.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
