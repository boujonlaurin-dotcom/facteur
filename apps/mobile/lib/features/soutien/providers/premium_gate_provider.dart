import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../premium/premium_provider.dart';
import '../../sources/providers/sources_providers.dart';

/// Plafond de sources suivies pour les comptes free.
const kFreeSourceCap = 30;

/// Façade de gating premium « Fact·eur·isse » — client-side uniquement
/// (décision produit : pas d'enforcement backend).
class PremiumGate {
  final bool isPremium;
  final int followedSourcesCount;

  const PremiumGate({
    required this.isPremium,
    required this.followedSourcesCount,
  });

  bool get sourceCapReached =>
      !isPremium && followedSourcesCount >= kFreeSourceCap;
  bool get canCreateVeille => isPremium;
  bool get canCustomizeSerein => isPremium;
}

final premiumGateProvider = Provider<PremiumGate>((ref) {
  final isPremium = ref.watch(isPremiumProvider);
  final sources = ref.watch(userSourcesProvider).valueOrNull ?? const [];
  return PremiumGate(
    isPremium: isPremium,
    followedSourcesCount: sources.length,
  );
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
