import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../soutien/widgets/founder_photos.dart';
import '../feedback_call_copy.dart';
import '../providers/feedback_providers.dart';
import 'feedback_stamp.dart';

/// Modale d'invitation à « un café en visio » avec Django et Laurin
/// (Epic 13, story 13.3).
///
/// Ouverte automatiquement une fois (garde nudge côté [CallInviteEntry]), puis
/// à la demande depuis l'entrée inline. Trois sorties nettes : réserver un
/// créneau (`accepted` + ouverture Google Agenda), « Plus tard » (`declined`,
/// snooze backend) et « On l'a déjà fait » (`already_done`, terminal).
class CallInviteSheet extends ConsumerWidget {
  final String? segment;

  const CallInviteSheet({super.key, this.segment});

  /// Affiche la modale en bottom sheet.
  static Future<void> show(BuildContext context, {String? segment}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CallInviteSheet(segment: segment),
    );
  }

  Future<void> _book(BuildContext context, WidgetRef ref) async {
    await ref
        .read(analyticsServiceProvider)
        .trackFeedbackInviteAction('accepted', segment: segment);
    await ref.read(feedbackRepositoryProvider).submitInviteAction('accepted');
    ref.invalidate(inviteStatusProvider);
    final uri = Uri.parse(ExternalLinks.feedbackCallBookingUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _dismiss(
    BuildContext context,
    WidgetRef ref, {
    required String action,
  }) async {
    await ref
        .read(analyticsServiceProvider)
        .trackFeedbackInviteAction(action, segment: segment);
    await ref.read(feedbackRepositoryProvider).submitInviteAction(action);
    // Le backend renvoie désormais `should_show: false` (snooze ou terminal) :
    // relire le statut fait disparaître l'entrée inline tout de suite, au lieu
    // de laisser un CTA que l'utilisateur vient d'écarter.
    ref.invalidate(inviteStatusProvider);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final bodyStyle = textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
      height: 1.45,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: FacteurSpacing.space6),

            // Nos deux visages (photos + étiquettes mono), réutilisées de
            // l'écran Soutien : c'est ce qui rend l'invitation humaine.
            const Center(child: FounderCollage(photoSize: 96)),
            const SizedBox(height: FacteurSpacing.space4),

            const Center(child: FeedbackStamp(label: FeedbackCallCopy.stamp)),
            const SizedBox(height: FacteurSpacing.space3),

            Text(
              FeedbackCallCopy.title,
              style: GoogleFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space3),

            Text(
              FeedbackCallCopy.bodyForSegment(segment),
              style: bodyStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space3),

            Text(
              FeedbackCallCopy.ask,
              style: bodyStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space3),

            Text(
              FeedbackCallCopy.signature,
              style: GoogleFonts.courierPrime(
                fontSize: 12,
                color: colors.textTertiary,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space6),

            ElevatedButton(
              onPressed: () => _book(context, ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(FacteurRadius.medium),
                ),
              ),
              child: const Text(FeedbackCallCopy.ctaBook),
            ),
            const SizedBox(height: FacteurSpacing.space1),

            // Deux sorties distinctes : reporter (snooze 21 j) ou clore
            // définitivement parce qu'on s'est déjà parlé.
            TextButton(
              onPressed: () => _dismiss(context, ref, action: 'declined'),
              child: Text(
                FeedbackCallCopy.ctaLater,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _dismiss(context, ref, action: 'already_done'),
              child: Text(
                FeedbackCallCopy.ctaAlreadyDone,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
