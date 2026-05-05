import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/letter.dart';

class LetterActionTile extends StatelessWidget {
  final LetterAction action;
  final VoidCallback? onTap;

  const LetterActionTile({
    super.key,
    required this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDone = action.status == LetterActionStatus.done;
    final isActive = action.status == LetterActionStatus.active;

    final labelColor = isDone ? colors.textTertiary : colors.textPrimary;
    final statusText = switch (action.status) {
      LetterActionStatus.done => 'Validée · cachet apposé',
      LetterActionStatus.active => 'Étape en cours',
      LetterActionStatus.todo => 'En attente',
    };
    final statusColor = switch (action.status) {
      LetterActionStatus.done => colors.success,
      LetterActionStatus.active => colors.primary,
      LetterActionStatus.todo => colors.textTertiary,
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.black.withOpacity(0.06)),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Check(status: action.status, colors: colors),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.label,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      color: labelColor,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.black.withOpacity(0.25),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusText.toUpperCase(),
                    style: GoogleFonts.courierPrime(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                PhosphorIcons.caretRight(),
                size: 16,
                color: isActive ? colors.primary : colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  final LetterActionStatus status;
  final FacteurColors colors;

  const _Check({required this.status, required this.colors});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case LetterActionStatus.done:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.success,
            border: Border.all(color: colors.success),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.check, size: 13, color: Colors.white),
        );
      case LetterActionStatus.active:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.primary, width: 2),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary,
            ),
          ),
        );
      case LetterActionStatus.todo:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.textTertiary, width: 1.5),
          ),
        );
    }
  }
}
