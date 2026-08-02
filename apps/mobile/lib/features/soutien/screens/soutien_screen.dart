import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_stamp.dart';
import '../../premium/premium_provider.dart';
import '../../premium/premium_refresh.dart';
import '../soutien_copy.dart';
import '../widgets/checkout_cta_button.dart';
import '../widgets/founder_photos.dart';
import '../widgets/price_row.dart';

/// Porte 1 du système de monétisation : l'écran Soutien, incarné par les
/// fondateurs. Lettre 2 §, carte bonus, réassurances, prix, CTA email.
///
/// Le soutien se finalise sur le web (option c : email -> page prix libre ->
/// Stripe). Au retour dans l'app (reprise), on rafraîchit l'entitlement premium
/// pour refléter le grant serveur asynchrone sans que l'utilisateur ait à
/// relancer l'app.
class SoutienScreen extends ConsumerStatefulWidget {
  const SoutienScreen({super.key});

  @override
  ConsumerState<SoutienScreen> createState() => _SoutienScreenState();
}

class _SoutienScreenState extends ConsumerState<SoutienScreen> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _onResume);
  }

  void _onResume() {
    // Déjà premium : rien à rafraîchir (évite un poll SDK inutile à chaque
    // reprise de l'écran).
    if (ref.read(isPremiumProvider)) return;
    unawaited(refreshPremiumAfterCheckout(ref));
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FacteurSpacing.space6,
          FacteurSpacing.space2,
          FacteurSpacing.space6,
          FacteurSpacing.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              SoutienCopy.soutienEyebrow,
              style: GoogleFonts.courierPrime(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              SoutienCopy.soutienHeadline,
              style: GoogleFonts.fraunces(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.15,
                letterSpacing: -0.5,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space6),
            const Center(child: FounderCollage()),
            const SizedBox(height: FacteurSpacing.space6),
            Text(
              SoutienCopy.soutienLetterP1,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space4),
            Text(
              SoutienCopy.soutienLetterP2,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space4),
            Text(
              SoutienCopy.soutienSignature,
              style: GoogleFonts.fraunces(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space6),
            _BonusCard(colors: colors, textTheme: textTheme),
            const SizedBox(height: FacteurSpacing.space6),
            const _Reassurance(text: SoutienCopy.reassurance1),
            const _Reassurance(text: SoutienCopy.reassurance2),
            const _Reassurance(text: SoutienCopy.reassurance3),
            const SizedBox(height: FacteurSpacing.space6),
            const PriceRow(note: SoutienCopy.soutienPriceNote),
            const SizedBox(height: FacteurSpacing.space4),
            const CheckoutCtaButton(label: SoutienCopy.soutienCta),
            const SizedBox(height: FacteurSpacing.space3),
            Center(
              child: Text(
                SoutienCopy.soutienDisclaimer,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
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

class _BonusCard extends StatelessWidget {
  const _BonusCard({required this.colors, required this.textTheme});

  final FacteurColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FacteurSpacing.space6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.surfaceElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SoutienCopy.soutienBonusIntro,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: FacteurSpacing.space4),
          const _BonusItem(
            title: SoutienCopy.bonusVeilleTitle,
            body: SoutienCopy.bonusVeilleBody,
          ),
          const _BonusItem(
            title: SoutienCopy.bonusAnalysesTitle,
            body: SoutienCopy.bonusAnalysesBody,
          ),
          const _BonusItem(
            title: SoutienCopy.bonusSereinTitle,
            body: SoutienCopy.bonusSereinBody,
          ),
          const SizedBox(height: FacteurSpacing.space2),
          const _SoonItem(label: SoutienCopy.bonusSoonAlertes),
          const SizedBox(height: FacteurSpacing.space2),
          const _SoonItem(label: SoutienCopy.bonusSoonResumes),
        ],
      ),
    );
  }
}

class _BonusItem extends StatelessWidget {
  const _BonusItem({required this.title, required this.body});

  final String title;
  final String body;

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
            child: Text.rich(
              TextSpan(
                text: title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      height: 1.45,
                    ),
                children: [
                  TextSpan(
                    text: ', $body',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoonItem extends StatelessWidget {
  const _SoonItem({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      children: [
        const FacteurStamp(text: SoutienCopy.bientotStamp),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ),
      ],
    );
  }
}

class _Reassurance extends StatelessWidget {
  const _Reassurance({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              PhosphorIcons.sealCheck(PhosphorIconsStyle.regular),
              size: 15,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
