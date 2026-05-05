import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/letter.dart';
import 'envelope_thumb.dart';

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

    final dateForDisplay = isArchived ? letter.archivedAt : letter.startedAt;
    final dateLabel = dateForDisplay != null
        ? _formatShortDate(dateForDisplay.toLocal())
        : null;
    final metaParts = <String>['Étape ${letter.letterNum}'];
    if (dateLabel != null) metaParts.add(dateLabel);

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
    final doneCount =
        letter.actions.where((a) => a.status == LetterActionStatus.done).length;
    final total = letter.actions.length;

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
                        metaParts.join(' · ').toUpperCase(),
                        style: GoogleFonts.courierPrime(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 4),
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
                        _MiniProgress(
                          progress: letter.progress,
                          done: doneCount,
                          total: total,
                          colors: colors,
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

class _MiniProgress extends StatelessWidget {
  final double progress;
  final int done;
  final int total;
  final FacteurColors colors;
  final bool dimmed;

  const _MiniProgress({
    required this.progress,
    required this.done,
    required this.total,
    required this.colors,
    required this.dimmed,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor =
        dimmed ? colors.textTertiary.withOpacity(0.4) : colors.primary;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(
                  height: 3,
                  color: Colors.black.withOpacity(0.07),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(height: 3, color: fillColor),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$done/$total',
          style: GoogleFonts.courierPrime(
            fontSize: 10,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
            color: colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

const _months = [
  'janv.',
  'févr.',
  'mars',
  'avril',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _formatShortDate(DateTime d) {
  return '${d.day} ${_months[d.month - 1]}';
}
