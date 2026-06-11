import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/personalisation_cta_provider.dart';
import 'tournee_composer_sheet.dart';

/// Carte d'invitation à composer sa Tournée, affichée juste sous le hero
/// « L'Essentiel du jour » au plus une fois tous les 30 jours. Après activation,
/// elle est remplacée par l'inline discret [MyInterestsIntro] pour les comptes
/// qui ont déjà personnalisé leur Tournée (cf. `flux_continu_screen`).
///
/// Gabarit visuel aligné sur la `CarteCta` de la Grille : carte pleine largeur,
/// fond accent doux, illustration (`facteur_reparation_cropped.svg`), titre +
/// sous-titre incitatif, bouton primaire « Composer ma Tournée » → ouvre la
/// sheet unifiée via [showTourneeComposerSheet].
class PersonalisationCtaCard extends ConsumerWidget {
  const PersonalisationCtaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final accent = colors.sectionEssentiel;
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FacteurSpacing.space3,
        FacteurSpacing.space2,
        FacteurSpacing.space3,
        FacteurSpacing.space4,
      ),
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Illustration : fond blanc en light, masquée en dark pour conserver
            // le comportement historique de l'asset à fond clair.
            if (!isDark)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SvgPicture.asset(
                  'assets/images/facteur_reparation_cropped.svg',
                  height: 132,
                  fit: BoxFit.contain,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Personnalise ton Essentiel',
                    style: GoogleFonts.fraunces(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -0.3,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choisis les thèmes et sources qui composent ta Tournée du '
                    'matin — réglée pour toi, en moins d\'une minute.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PrimaryButton(
                    label: 'Composer ma Tournée',
                    accent: accent,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      ref
                          .read(personalisationCtaShouldShowProvider.notifier)
                          .activate();
                      showTourneeComposerSheet(context);
                    },
                  ),
                ],
              ),
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
                PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.bold),
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
