import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../soutien_copy.dart';
import 'checkout_cta_button.dart';
import 'mission_card.dart';
import 'price_row.dart';

/// Les trois murs de feature affichés en bottom sheet (la veille a son écran
/// dédié : [VeilleWallScreen]).
enum PaywallWallVariant { sources, analyses, serein }

/// Mur de feature « porte 2 » : eyebrow mono, headline Fraunces, argumentaire,
/// fil mission vers Soutien, prix, CTA email. Zéro urgence, zéro
/// culpabilisation.
class PaywallSheet extends StatelessWidget {
  const PaywallSheet({super.key, required this.variant});

  final PaywallWallVariant variant;

  static Future<void> show(BuildContext context, PaywallWallVariant variant) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PaywallSheet(variant: variant),
    );
  }

  String get _eyebrow => switch (variant) {
        PaywallWallVariant.sources => SoutienCopy.sourcesWallEyebrow,
        PaywallWallVariant.analyses => SoutienCopy.analysesWallEyebrow,
        PaywallWallVariant.serein => SoutienCopy.sereinWallEyebrow,
      };

  String get _headline => switch (variant) {
        PaywallWallVariant.sources => SoutienCopy.sourcesWallHeadline,
        PaywallWallVariant.analyses => SoutienCopy.analysesWallHeadline,
        PaywallWallVariant.serein => SoutienCopy.sereinWallHeadline,
      };

  String get _body => switch (variant) {
        PaywallWallVariant.sources => SoutienCopy.sourcesWallBody,
        PaywallWallVariant.analyses => SoutienCopy.analysesWallBody,
        PaywallWallVariant.serein => SoutienCopy.sereinWallBody,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: colors.backgroundPrimary,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          FacteurSpacing.space6,
          FacteurSpacing.space3,
          FacteurSpacing.space6,
          FacteurSpacing.space4 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: FacteurSpacing.space6),
            Text(
              _eyebrow.toUpperCase(),
              style: GoogleFonts.courierPrime(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              _headline,
              style: GoogleFonts.fraunces(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.2,
                letterSpacing: -0.5,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              _body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: FacteurSpacing.space4),
            MissionCard(
              text: SoutienCopy.wallMissionLine,
              onOurStory: () {
                Navigator.of(context).pop();
                context.pushNamed(RouteNames.soutien);
              },
            ),
            const SizedBox(height: FacteurSpacing.space4),
            const PriceRow(note: '· ${SoutienCopy.wallPriceNote}'),
            const SizedBox(height: FacteurSpacing.space4),
            const CheckoutCtaButton(
              label: SoutienCopy.wallCta,
              popBeforePush: true,
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Center(
              child: Text(
                SoutienCopy.wallDisclaimer,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
