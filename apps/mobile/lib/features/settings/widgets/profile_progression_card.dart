import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../lettres/models/facteur_grade.dart';
import '../../lettres/providers/letters_provider.dart';
import '../../lettres/widgets/letter_mini_progress.dart';
import '../../lettres/widgets/ring_avatar.dart';
import '../providers/user_profile_provider.dart';

/// Section « PROGRESSION » en haut de l'écran Profil : même avatar que le
/// header (initiales/couleur via RingAvatar), grade actuel et étapes de la
/// lettre en cours. Tap → écran Progression.
class ProfileProgressionCard extends ConsumerWidget {
  const ProfileProgressionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final state = ref.watch(lettersProvider).valueOrNull;
    if (state == null) return const SizedBox.shrink();

    final displayName = ref.watch(userProfileProvider).displayName;
    final serein = ref.watch(sereinToggleProvider.select((s) => s.enabled));
    final grade = state.grade;
    final active = state.activeLetter;
    final activeDone = active?.doneActionCount ?? 0;
    final activeTotal = active?.totalActionCount ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space6,
            vertical: FacteurSpacing.space2,
          ),
          child: Text(
            'PROGRESSION',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  letterSpacing: 1.5,
                ),
          ),
        ),
        Container(
          margin:
              const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.surfaceElevated),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.pushNamed(RouteNames.lettres),
              child: Padding(
                padding: const EdgeInsets.all(FacteurSpacing.space4),
                child: Row(
                  children: [
                    RingAvatar.fromName(
                      displayName,
                      active?.progress,
                      level: grade.level,
                      serein: serein,
                    ),
                    const SizedBox(width: FacteurSpacing.space4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            grade.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (active != null && activeTotal > 0) ...[
                            const SizedBox(height: 6),
                            LetterMiniProgress(
                              progress: active.progress,
                              done: activeDone,
                              total: activeTotal,
                              showCount: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: FacteurSpacing.space2),
                    Icon(
                      PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
                      color: colors.textTertiary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
