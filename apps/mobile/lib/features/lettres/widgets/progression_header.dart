import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../../settings/providers/user_profile_provider.dart';
import '../models/facteur_grade.dart';
import '../models/letter_progress.dart';
import 'letter_mini_progress.dart';
import 'ring_avatar.dart';

/// Header gamifié de l'écran Progression : avatar + grade de facteur,
/// progression globale et étapes de la lettre active.
class ProgressionHeader extends ConsumerWidget {
  final LetterProgressState state;

  const ProgressionHeader({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final displayName = ref.watch(userProfileProvider).displayName;
    final grade = state.grade;
    final active = state.activeLetter;

    final activeDone = active?.doneActionCount ?? 0;
    final activeTotal = active?.totalActionCount ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RingAvatar.fromName(
                  displayName,
                  active?.progress,
                  level: grade.level,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    grade.title,
                    style: GoogleFonts.fraunces(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                      letterSpacing: -0.3,
                      height: 1.15,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LetterMiniProgress(
              progress: grade.globalProgress,
              done: activeDone,
              total: activeTotal,
              height: 5,
              showCount: true,
            ),
          ],
        ),
      ),
    );
  }
}
