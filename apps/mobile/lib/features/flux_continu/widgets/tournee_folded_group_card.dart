import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Collapsed summary card shown when **every** editorial section of the day
/// has been folded (the user has finished their Tournée).
///
/// Replaces the visual pile of individual [FoldedSectionCard]s with a single
/// H1-weighted row that signals « mission accomplie » without cluttering the
/// screen. Tapping it expands back to the individual stack so any section can
/// still be reopened.
///
/// Layout mirrors [FoldedSectionCard] (same padding / hairline) but uses a
/// larger Fraunces H1 weight and [Icons.expand_more] to signpost the action.
class TourneeFoldedGroupCard extends StatelessWidget {
  final VoidCallback onTap;

  const TourneeFoldedGroupCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 14, 18, 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colors.textPrimary.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.check, size: 18, color: colors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tournée du jour ✓',
                  style: GoogleFonts.fraunces(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.4,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.expand_more,
                size: 22,
                color: colors.textPrimary.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
