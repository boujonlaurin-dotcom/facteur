import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../config/theme.dart';
import '../providers/feedback_providers.dart';

/// Copy de la modal, adaptée au segment d'activité.
({String title, String body}) _copyForSegment(String? segment) {
  switch (segment) {
    case 'returning':
      return (
        title: 'Content de te revoir 👋',
        body:
            "Salut, c'est Laurin. Ça fait un moment qu'on s'était pas croisés — "
            "j'aimerais beaucoup comprendre ce qui t'a éloigné, et ce qui te "
            "ramène. Ton retour pèse directement sur ce que je code ensuite.",
      );
    case 'low_active':
      return (
        title: 'On prend 15 min ? 👋',
        body:
            "Salut, c'est Laurin. Je vois que tu passes de temps en temps — "
            "j'aimerais comprendre ce qui te retient de revenir plus souvent. "
            "Ton avis a un impact direct sur la suite de Facteur.",
      );
    case 'active':
    default:
      return (
        title: 'Merci d\'être là 🙏',
        body:
            "Salut, c'est Laurin. Tu lis Facteur régulièrement, et ça compte "
            "énormément. J'aimerais t'entendre : ce qui marche, ce qu'on peut "
            "améliorer. 15 min en visio, à l'horaire qui t'arrange.",
      );
  }
}

/// Modal d'invitation à un call qualitatif avec l'équipe (Epic 13).
///
/// Affichée 1x (gating segmenté côté backend) au moment de fermeture.
/// Trois sorties : prendre un call, signaler un point précis (les deux
/// ouvrent Calendly en v1), ou reporter ("Pas maintenant" → snooze backend).
class CallInviteSheet extends ConsumerWidget {
  final String? segment;

  const CallInviteSheet({super.key, this.segment});

  /// Affiche la modal en bottom sheet.
  static Future<void> show(BuildContext context, {String? segment}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CallInviteSheet(segment: segment),
    );
  }

  /// Option approfondie : réserver un créneau visio (Google Calendar).
  Future<void> _bookCall(BuildContext context, WidgetRef ref) async {
    await _accept(context, ref, ExternalLinks.feedbackCallUrl);
  }

  /// Option rapide : un mot direct à Laurin sur WhatsApp.
  Future<void> _quickMessage(BuildContext context, WidgetRef ref) async {
    await _accept(
      context,
      ref,
      'https://wa.me/${LaurinContact.whatsappE164}'
          '?text=Mon%20retour%20sur%20Facteur%20',
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref, String url) async {
    await ref.read(feedbackRepositoryProvider).submitInviteAction('accepted');
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    await ref.read(feedbackRepositoryProvider).submitInviteAction('declined');
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final copy = _copyForSegment(segment);

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
          const SizedBox(height: 20),

          // Avatar (placeholder — TODO(laurin): remplacer par une vraie photo)
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: colors.primary.withValues(alpha: 0.12),
              child: const Text(
                '👋',
                style: TextStyle(fontSize: 34),
              ),
            ),
          ),
          const SizedBox(height: FacteurSpacing.space4),

          Text(
            copy.title,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FacteurSpacing.space3),

          Text(
            copy.body,
            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FacteurSpacing.space6),

          // Approfondi : réserver un créneau visio.
          ElevatedButton(
            onPressed: () => _bookCall(context, ref),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
              ),
            ),
            child: const Text('Réserver 15 min en visio'),
          ),

          // Rapide : un mot direct à Laurin sur WhatsApp.
          if (LaurinContact.hasWhatsapp) ...[
            const SizedBox(height: FacteurSpacing.space3),
            OutlinedButton(
              onPressed: () => _quickMessage(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                side: BorderSide(color: colors.primary.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(FacteurRadius.medium),
                ),
              ),
              child: const Text('Juste un mot rapide (WhatsApp)'),
            ),
          ],
          const SizedBox(height: FacteurSpacing.space2),

          // Sortie douce
          TextButton(
            onPressed: () => _decline(context, ref),
            child: Text(
              'Pas maintenant',
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
