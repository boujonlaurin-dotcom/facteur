import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../providers/weather_provider.dart';
import '../utils/closing_activity.dart';
import 'tournee_cta_buttons.dart';

/// Closing card displayed after the four Flux Continu sections.
///
/// Layout per maquette V6 :
/// - "FIN DE TOURNÉE" stamp Courier Prime 10 w700, color/border #2E7D32,
///   rotation -2°.
/// - Heading "Tu es à jour" Fraunces 700 24px.
/// - Primary CTA "Continuer à Flâner" (background #D35400) + ghost CTA
///   "Refermer pour aujourd'hui" (border 1.5px rgba(0,0,0,0.1)).
class ClosingCardV18 extends ConsumerWidget {
  final VoidCallback? onContinue;
  final VoidCallback? onClose;

  /// Phrase de fermeture affichée à la place du bouton « Refermer » quand
  /// [onClose] est null (cas iOS : la fermeture programmatique est interdite
  /// par l'App Store). Ignorée si [onClose] est fourni (cas Android).
  final String? closeHint;

  const ClosingCardV18({
    super.key,
    this.onContinue,
    this.onClose,
    this.closeHint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    // Météo en cours/échec → null → pickClosingActivities retombe sur
    // l'intérieur (carte calme, pas de spinner). La logique vit dans la
    // fonction pure.
    final condition = ref.watch(weatherProvider).valueOrNull?.condition;
    final activities = pickClosingActivities(condition: condition);
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 30, 18, 24),
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
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/notifications/facteur_bike.png',
              height: 168,
              cacheHeight: 336,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 14),
            Transform.rotate(
              angle: -2 * math.pi / 180,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF2E7D32),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  'FIN DE TOURNÉE',
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2E7D32),
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tu es à jour',
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.1,
                letterSpacing: -0.4,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            _ActivitySuggestions(activities: activities),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TourneePrimaryButton(
                label: 'Continuer à Flâner',
                onTap: onContinue,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TourneeGhostButton(
                  label: "Refermer pour aujourd'hui",
                  onTap: onClose,
                ),
              ),
            ] else if (closeHint != null) ...[
              const SizedBox(height: 14),
              Text(
                closeHint!,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  height: 1.4,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bloc discret « Et si tu en profitais pour… » : trois propositions tangibles
/// hors-écran à faire maintenant. Toujours affiché (même si rien n'a été lu) —
/// c'est la valeur ajoutée de la fin de tournée. Reste léger : pas de CTA, juste
/// des invitations tournées en question.
class _ActivitySuggestions extends StatelessWidget {
  final List<ClosingActivity> activities;

  const _ActivitySuggestions({required this.activities});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    if (activities.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Et si tu en profitais pour…',
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        // Fond blanc (plus de container orange) : les propositions reposent
        // directement sur la surface de la carte pour alléger la fin de tournée.
        Column(
          children: [
            for (final activity in activities)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Text(activity.emoji, style: const TextStyle(fontSize: 17)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        activity.prompt,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
