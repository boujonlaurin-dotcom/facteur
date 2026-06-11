import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../onboarding_strings.dart';

/// Carte d'ajout d'abonnement presse, affichée en bas de la page sources de
/// l'onboarding à la place de l'ancien `OutlinedButton` peu engageant.
///
/// Gabarit visuel aligné sur la `PersonalisationCtaCard` du Flux Continu : carte
/// pleine largeur, fond surface, bordure accent douce, en-tête illustré (icône
/// étoile sur pastille accent), titre + sous-titre incitatif et bouton primaire
/// « Ajouter mes abonnements » → ouvre la [PremiumSourcesSheet] via [onTap].
class AddSubscriptionCard extends StatelessWidget {
  final VoidCallback onTap;

  const AddSubscriptionCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final accent = colors.primary;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(FacteurRadius.medium),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    PhosphorIcons.star(PhosphorIconsStyle.fill),
                    size: 20,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    OnboardingStrings.addSubscriptionCardTitle,
                    style: GoogleFonts.fraunces(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -0.3,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              OnboardingStrings.addSubscriptionCardSubtitle,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _PrimaryButton(
              label: OnboardingStrings.addSubscriptionCardButton,
              accent: accent,
              onTap: () {
                HapticFeedback.mediumImpact();
                onTap();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(FacteurRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
