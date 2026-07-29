import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../config/theme.dart';
import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../soutien/widgets/founder_photos.dart';
import '../feedback_call_copy.dart';
import '../providers/feedback_providers.dart';
import 'call_invite_sheet.dart';

/// Entrée inline vers l'invitation « un café en visio » (Epic 13, story 13.3).
///
/// Posée **quelques blocs avant la fin** de la Tournée (et non dans la carte de
/// clôture, invisible en pratique) : une ligne slim, tappable, qui ouvre
/// [CallInviteSheet].
///
/// À la première exposition éligible, la modale se déploie **seule une fois**
/// (garde [NudgeIds.feedbackCallAutoModal], `frequency: once`). Le déclencheur
/// est la **visibilité réelle** (≥ 50 % du widget dans le viewport), pas le
/// build : ouvrir au build ferait surgir la modale alors que l'utilisateur est
/// encore en haut de sa tournée.
///
/// C'est aussi ici que part `markInviteShown()` (source de vérité backend du
/// cap `MAX_SHOWS`) : le compter au build de la carte de clôture revenait à
/// consommer des affichages que personne n'avait vus.
class CallInviteEntry extends ConsumerStatefulWidget {
  const CallInviteEntry({super.key});

  @override
  ConsumerState<CallInviteEntry> createState() => _CallInviteEntryState();
}

class _CallInviteEntryState extends ConsumerState<CallInviteEntry> {
  bool _exposureHandled = false;

  Future<void> _onFirstExposure(String? segment) async {
    // Cap d'affichages backend : compté sur une exposition réelle.
    await ref.read(feedbackRepositoryProvider).markInviteShown();
    await ref
        .read(analyticsServiceProvider)
        .trackFeedbackInviteShown(segment: segment);

    // Auto-déploiement, une seule fois dans la vie de l'app.
    final canAutoOpen = await ref
        .read(nudgeServiceProvider)
        .consumeFirstShow(NudgeIds.feedbackCallAutoModal);
    if (!canAutoOpen || !mounted) return;
    await _openSheet(segment, origin: 'auto');
  }

  Future<void> _openSheet(String? segment, {required String origin}) async {
    await ref
        .read(analyticsServiceProvider)
        .trackFeedbackInviteOpened(segment: segment, origin: origin);
    if (!mounted) return;
    await CallInviteSheet.show(context, segment: segment);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final invite = ref.watch(inviteStatusProvider).valueOrNull;
    if (invite == null || !invite.shouldShow) return const SizedBox.shrink();
    final segment = invite.segment;

    return VisibilityDetector(
      key: const ValueKey('call_invite_entry_vis'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction < 0.5 || _exposureHandled) return;
        _exposureHandled = true;
        // Hors de la passe de rendu : `VisibilityDetector` notifie pendant le
        // pipeline, où pousser une route est interdit.
        Future.microtask(() {
          if (mounted) _onFirstExposure(segment);
        });
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          child: InkWell(
            onTap: () => _openSheet(segment, origin: 'tap'),
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Row(
                children: [
                  const FounderMiniDuo(),
                  const SizedBox(width: FacteurSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          FeedbackCallCopy.entryLine,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          FeedbackCallCopy.ctaBook,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
