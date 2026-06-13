import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/letter.dart';
import 'envelope_thumb.dart';
import 'letter_mini_progress.dart';

class LetterRow extends StatelessWidget {
  final Letter letter;
  final VoidCallback? onTap;

  const LetterRow({
    super.key,
    required this.letter,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isArchived = letter.status == LetterStatus.archived;
    final isUpcoming = letter.status == LetterStatus.upcoming;

    final pillData = switch (letter.status) {
      LetterStatus.active => (
          'EN COURS',
          colors.primary.withOpacity(0.10),
          colors.primary,
        ),
      LetterStatus.upcoming => (
          'À VENIR',
          colors.border,
          colors.textTertiary,
        ),
      LetterStatus.archived => (
          'CLASSÉE',
          Colors.black.withOpacity(0.06),
          colors.textTertiary,
        ),
    };

    final showProgress = letter.actions.isNotEmpty;
    final doneCount = letter.doneActionCount;
    final total = letter.totalActionCount;

    Widget content = Container(
      margin: const EdgeInsets.only(bottom: 8),
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
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EnvelopeThumb(archived: isArchived),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        letter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.fraunces(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _StatusPill(
                        label: pillData.$1,
                        background: pillData.$2,
                        foreground: pillData.$3,
                      ),
                      if (showProgress) ...[
                        const SizedBox(height: 6),
                        LetterMiniProgress(
                          progress: letter.progress,
                          done: doneCount,
                          total: total,
                          dimmed: isUpcoming,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isArchived) {
      content = Opacity(opacity: 0.7, child: content);
    }
    return content;
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.courierPrime(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: foreground,
        ),
      ),
    );
  }
}
