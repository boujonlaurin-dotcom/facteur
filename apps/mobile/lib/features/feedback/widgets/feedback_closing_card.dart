import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../providers/feedback_providers.dart';
import 'call_invite_sheet.dart';
import 'sentiment_picker.dart';

/// Carte de fin de Tournée du jour dédiée au feedback (Epic 13).
///
/// Insérée juste après la carte « Fin de tournée » sur la page l'Essentiel.
/// - Toujours : micro-feedback emoji (😴/🙂/🔥).
/// - Si l'utilisateur est éligible (gating segmenté côté backend) : un CTA
///   discret pour prendre un call qualitatif avec Laurin (ouvre CallInviteSheet).
class FeedbackClosingCard extends ConsumerStatefulWidget {
  /// Date de la tournée notée (par défaut : aujourd'hui côté backend).
  final DateTime? digestDate;

  const FeedbackClosingCard({super.key, this.digestDate});

  @override
  ConsumerState<FeedbackClosingCard> createState() =>
      _FeedbackClosingCardState();
}

class _FeedbackClosingCardState extends ConsumerState<FeedbackClosingCard> {
  bool _shownMarked = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final invite = ref.watch(inviteStatusProvider).valueOrNull;
    final showCall = invite?.shouldShow ?? false;

    // Marque l'invitation comme affichée une seule fois (source de vérité
    // backend pour le cap d'affichages et le snooze).
    if (showCall && !_shownMarked) {
      _shownMarked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(feedbackRepositoryProvider).markInviteShown();
      });
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tampon « TON AVIS COMPTE » dans l'esprit des cartes de tournée.
            Transform.rotate(
              angle: -2 * math.pi / 180,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.primary, width: 1.5),
                ),
                child: Text(
                  'TON AVIS COMPTE',
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Micro-feedback emoji (toujours présent).
            SentimentPicker(digestDate: widget.digestDate),

            // Invitation au call (conditionnelle, gated backend).
            if (showCall) ...[
              const SizedBox(height: 18),
              Divider(
                height: 1,
                color: colors.textTertiary.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 16),
              _CallInviteTeaser(
                onTap: () =>
                    CallInviteSheet.show(context, segment: invite?.segment),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bloc compact qui amorce l'invitation au call : avatar + une phrase + CTA.
/// Le détail (copy segmentée + 3 sorties) vit dans [CallInviteSheet].
class _CallInviteTeaser extends StatelessWidget {
  final VoidCallback onTap;

  const _CallInviteTeaser({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Column(
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colors.primary.withValues(alpha: 0.12),
              child: const Text('👋', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Laurin (qui construit Facteur) aimerait t’entendre 15 min.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
              ),
            ),
            child: const Text('Discuter avec Laurin'),
          ),
        ),
      ],
    );
  }
}
