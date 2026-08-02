import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../config/constants.dart';
import 'premium_provider.dart';

/// Rafraîchit l'entitlement `premium` après un checkout web (parcours soutien).
///
/// Le grant côté serveur est asynchrone (webhook Stripe -> entitlement
/// promotionnel RevenueCat), donc au retour dans l'app l'info peut ne pas être
/// encore à jour. On invalide le cache RevenueCat puis on poll brièvement
/// (3 essais, backoff 1/2/4 s) jusqu'à voir l'entitlement actif, avant de
/// réinvalider `customerInfoProvider` pour que le gating se rafraîchisse.
///
/// No-op sur web ou si RevenueCat n'est pas configuré (jamais d'appel SDK sur
/// un singleton non initialisé, cf. [customerInfoProvider]).
Future<void> refreshPremiumAfterCheckout(WidgetRef ref) async {
  if (kIsWeb || !RevenueCatConstants.isConfigured(isIOS: Platform.isIOS)) {
    return;
  }

  try {
    await Purchases.invalidateCustomerInfoCache();
  } catch (_) {
    // SDK indisponible : on abandonne silencieusement (dégrade en non-premium).
    return;
  }

  const delays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];
  for (final delay in delays) {
    await Future<void>.delayed(delay);
    try {
      final info = await Purchases.getCustomerInfo();
      if (info.entitlements.active.containsKey(
        RevenueCatConstants.entitlementId,
      )) {
        break;
      }
    } catch (_) {
      // Réseau/SDK flaky : on retente au prochain palier.
    }
  }

  // Force le stream à réémettre l'état frais (le gating lit customerInfoProvider).
  ref.invalidate(customerInfoProvider);
}
