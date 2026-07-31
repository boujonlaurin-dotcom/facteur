import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../soutien_copy.dart';
import '../widgets/checkout_cta_button.dart';
import '../widgets/mission_card.dart';
import '../widgets/price_row.dart';

/// Porte 2 pour la veille : mur de feature plein écran (la veille n'existe
/// pas encore pour les free, contrairement aux murs sheet qui interrompent
/// une action en cours).
class VeilleWallScreen extends StatelessWidget {
  const VeilleWallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
            color: colors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  FacteurSpacing.space6,
                  FacteurSpacing.space2,
                  FacteurSpacing.space6,
                  FacteurSpacing.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/notifications/facteur_veille.png',
                        height: 120,
                        errorBuilder: (_, __, ___) => Icon(
                          PhosphorIcons.binoculars(PhosphorIconsStyle.duotone),
                          size: 88,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: FacteurSpacing.space6),
                    Text(
                      SoutienCopy.veilleWallEyebrow.toUpperCase(),
                      style: GoogleFonts.courierPrime(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: FacteurSpacing.space3),
                    Text(
                      SoutienCopy.veilleWallHeadline,
                      style: GoogleFonts.fraunces(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        letterSpacing: -0.5,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: FacteurSpacing.space6),
                    const _Benefit(text: SoutienCopy.veilleWallBenefit1),
                    const _Benefit(text: SoutienCopy.veilleWallBenefit2),
                    const _Benefit(text: SoutienCopy.veilleWallBenefit3),
                    const SizedBox(height: FacteurSpacing.space6),
                    MissionCard(
                      text: SoutienCopy.veilleWallMission,
                      onOurStory: () =>
                          context.pushNamed(RouteNames.soutien),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FacteurSpacing.space6,
                FacteurSpacing.space2,
                FacteurSpacing.space6,
                FacteurSpacing.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PriceRow(note: SoutienCopy.veilleWallPriceNote),
                  const SizedBox(height: FacteurSpacing.space3),
                  const CheckoutCtaButton(label: SoutienCopy.wallCta),
                  const SizedBox(height: FacteurSpacing.space2),
                  Center(
                    child: Text(
                      SoutienCopy.wallDisclaimer,
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
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

class _Benefit extends StatelessWidget {
  const _Benefit({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: FacteurSpacing.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
              size: 18,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
