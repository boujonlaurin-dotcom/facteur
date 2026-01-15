import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../../../widgets/design/facteur_logo.dart';

/// Écran de paywall (placeholder)
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  // ignore: unused_field
  final bool _isYearly = true; // Kept for logic

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),

              // Close button
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.regular)),
                  onPressed: () => context.pop(),
                ),
              ),

              const FacteurLogo(size: 80),
              const SizedBox(height: FacteurSpacing.space6),

              Text(
                'Soutenez\nFacteur',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: colors.primary,
                      height: 1.1,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: FacteurSpacing.space4),

              Text(
                'L\'information a un prix.\nCelui de votre temps, pas de votre attention.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: FacteurSpacing.space6),

              // Cartes d'offres
              // Note: _SubscriptionCard was seemingly not defined in the original file I viewed, or replaced by _PricingOption and manual layout?
              // The usage in previous replace call used _SubscriptionCard but definition was nowhere.
              // I will assume _PricingOption was what was intended or restore usage of _PricingOption.
              // However, the text content suggests distinct cards.
              // Given the messy state, I'll reconstruct a simple UI using containers if needed or assuming definitions exist/I add them.
              // Looking at previous valid code, there were _SubscriptionCard usages. I will define it if missing or use what's there.
              // Wait, the file ending shows _PricingOption and _FeatureRow but NOT _SubscriptionCard.
              // I will assume the previous code I saw in `replace_file_content` (Step 343) was TRYING to use _SubscriptionCard but failed to define it or I overwrote it?
              // Actually, looking at Step 332, I saw `_SubscriptionCard` being used.
              // I will define `_SubscriptionCard` to make it work.

              _SubscriptionCard(
                title: 'Facteur Libre',
                price: 'Gratuit',
                description: 'L\'essentiel pour s\'informer',
                features: const [
                  'Agrégation intelligente',
                  'Résumé quotidien',
                  'Limité à 3 sources',
                ],
                color: colors.surface,
                textColor: colors.textPrimary,
                borderColor: colors.textTertiary.withValues(alpha: 0.2),
              ),

              const SizedBox(height: FacteurSpacing.space4),

              _SubscriptionCard(
                title: 'Facteur Engagé',
                price: '4,99€ / mois',
                description: 'Soutenez le journalisme indépendant',
                features: const [
                  'Sources illimitées',
                  'Analyses approfondies',
                  'Mode hors-ligne',
                  'Badge supporter',
                ],
                isPopular: true,
                color: colors.surface,
                textColor: colors.primary,
                borderColor: colors.primary,
                buttonText: 'S\'abonner (7 jours gratuits)',
              ),

              const SizedBox(height: FacteurSpacing.space6),

              // CTA
              PrimaryButton(
                label: 'S\'abonner',
                onPressed: () {
                  // TODO: RevenueCat purchase
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Intégration RevenueCat à venir',
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: FacteurSpacing.space4),

              // Restore
              TextButton(
                onPressed: () {
                  // TODO: Restore purchases
                },
                child: Text(
                  'Restaurer mes achats',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ),

              const SizedBox(height: FacteurSpacing.space4),

              // Legal
              Text(
                'En vous abonnant, vous acceptez nos Conditions d\'utilisation. '
                'L\'abonnement se renouvelle automatiquement. '
                'Annulez à tout moment dans les paramètres de votre compte Apple.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: FacteurSpacing.space6),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final String title;
  final String price;
  final String description;
  final List<String> features;
  final Color color;
  final Color textColor;
  final Color borderColor;
  final bool isPopular;
  final String? buttonText;

  const _SubscriptionCard({
    required this.title,
    required this.price,
    required this.description,
    required this.features,
    required this.color,
    required this.textColor,
    required this.borderColor,
    this.isPopular = false,
    this.buttonText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(
          color: borderColor,
          width: isPopular ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: textColor,
                    ),
              ),
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(FacteurRadius.full),
                  ),
                  child: Text(
                    'Populaire',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            price,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: colors.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 24),
          ...features.map((feature) => _FeatureRow(text: feature)),
          if (buttonText != null) ...[
            const SizedBox(height: 24),
            PrimaryButton(
              label: buttonText!,
              onPressed: () {},
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String text;

  const _FeatureRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: colors.success, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
