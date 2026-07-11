import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:facteur/core/ui/notification_service.dart';
import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../providers/subscription_provider.dart';

/// Écran de paywall — branché sur RevenueCat.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final offeringsAsync = ref.watch(offeringsProvider);
    final subState = ref.watch(subscriptionProvider);

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
                borderColor: colors.textTertiary.withOpacity(0.2),
              ),
              const SizedBox(height: FacteurSpacing.space4),
              offeringsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _OfferingsError(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(offeringsProvider),
                ),
                data: (offerings) {
                  final package = offerings.current?.monthly ??
                      offerings.current?.availablePackages.firstOrNull;
                  if (package == null) {
                    return _OfferingsError(
                      message: 'Aucune offre disponible.',
                      onRetry: () => ref.invalidate(offeringsProvider),
                    );
                  }
                  return _SubscriptionCard(
                    title: 'Facteur Engagé',
                    price: package.storeProduct.priceString,
                    description: package.storeProduct.description.isNotEmpty
                        ? package.storeProduct.description
                        : 'Soutenez le journalisme indépendant',
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
                    buttonText: 'S\'abonner',
                    onSubscribe: subState.loading
                        ? null
                        : () => _onSubscribe(package),
                  );
                },
              ),
              const SizedBox(height: FacteurSpacing.space6),
              if (offeringsAsync.hasValue)
                PrimaryButton(
                  label: subState.loading ? 'Achat en cours…' : 'S\'abonner',
                  onPressed: subState.loading
                      ? null
                      : () {
                          final pkg = offeringsAsync.value?.current?.monthly ??
                              offeringsAsync
                                  .value?.current?.availablePackages.firstOrNull;
                          if (pkg != null) _onSubscribe(pkg);
                        },
                ),
              const SizedBox(height: FacteurSpacing.space4),
              TextButton(
                onPressed: subState.loading ? null : _onRestore,
                child: Text(
                  'Restaurer mes achats',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ),
              const SizedBox(height: FacteurSpacing.space4),
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

  Future<void> _onSubscribe(Package package) async {
    final notifier = ref.read(subscriptionProvider.notifier);
    final ok = await notifier.purchase(package);
    if (!mounted) return;
    if (ok) {
      NotificationService.showSuccess('Bienvenue chez Facteur Engagé');
      context.pop();
    } else {
      final err = ref.read(subscriptionProvider).error;
      if (err != null) NotificationService.showError(err);
    }
  }

  Future<void> _onRestore() async {
    final notifier = ref.read(subscriptionProvider.notifier);
    final ok = await notifier.restore();
    if (!mounted) return;
    NotificationService.showInfo(
      ok ? 'Achats restaurés' : 'Aucun achat à restaurer',
    );
    if (ok) context.pop();
  }
}

class _OfferingsError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _OfferingsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
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
  final VoidCallback? onSubscribe;

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
    this.onSubscribe,
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
                    color: colors.primary.withOpacity(0.1),
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
              onPressed: onSubscribe,
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
