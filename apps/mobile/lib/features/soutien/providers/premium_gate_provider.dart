import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../premium/premium_provider.dart';

/// Façade de gating premium « Fact·eur·isse » — client-side uniquement
/// (décision produit : pas d'enforcement backend).
class PremiumGate {
  final bool isPremium;

  const PremiumGate({
    required this.isPremium,
  });

  bool get canCreateVeille => isPremium;
  bool get canCustomizeSerein => isPremium;

  @override
  bool operator ==(Object other) =>
      other is PremiumGate && other.isPremium == isPremium;

  @override
  int get hashCode => isPremium.hashCode;
}

final premiumGateProvider = Provider<PremiumGate>((ref) {
  final isPremium = ref.watch(isPremiumProvider);
  return PremiumGate(isPremium: isPremium);
});

/// Date de souscription (« Fact·eur·isse depuis mois année »). Null si
/// non-premium ou si RevenueCat ne fournit pas l'originalPurchaseDate →
/// l'UI masque la ligne.
final premiumSinceProvider = Provider<DateTime?>((ref) {
  final info = ref.watch(customerInfoProvider).valueOrNull;
  final entitlement =
      info?.entitlements.active[RevenueCatConstants.entitlementId];
  final raw = entitlement?.originalPurchaseDate;
  if (raw == null) return null;
  return DateTime.tryParse(raw);
});
