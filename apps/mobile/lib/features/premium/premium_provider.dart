import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../config/constants.dart';

/// Stream du `CustomerInfo` RevenueCat. Émet la valeur initiale au démarrage,
/// puis chaque mise à jour poussée par RevenueCat (achat, renouvellement,
/// expiration, sortie d'essai). RevenueCat reste la source de vérité de
/// l'entitlement `premium` — la table Postgres `user_subscriptions` n'est
/// qu'un miroir analytics.
final customerInfoProvider = StreamProvider<CustomerInfo?>((ref) {
  // Web : pas de SDK. Natif : si RevenueCat n'est PAS configuré (clé API
  // absente, ex. build sans --dart-define=REVENUECAT_*), NE JAMAIS appeler le
  // SDK — `Purchases.*` sur un singleton non initialisé lève une exception
  // native → crash post-login. On émet simplement `null` (non-premium).
  if (kIsWeb || !RevenueCatConstants.isConfigured(isIOS: Platform.isIOS)) {
    return Stream<CustomerInfo?>.value(null);
  }

  final controller = StreamController<CustomerInfo?>();

  void listener(CustomerInfo info) {
    if (!controller.isClosed) controller.add(info);
  }

  try {
    Purchases.addCustomerInfoUpdateListener(listener);
  } catch (e) {
    // SDK indisponible/non initialisé → dégrade en non-premium sans crasher.
    if (!controller.isClosed) {
      controller.add(null);
      controller.close();
    }
    return controller.stream;
  }

  // Premier état : on récupère le snapshot courant pour que les consommateurs
  // n'aient pas à attendre un événement RevenueCat avant de pouvoir afficher.
  unawaited(() async {
    try {
      final info = await Purchases.getCustomerInfo();
      if (!controller.isClosed) controller.add(info);
    } catch (_) {
      if (!controller.isClosed) controller.add(null);
    }
  }());

  ref.onDispose(() {
    Purchases.removeCustomerInfoUpdateListener(listener);
    controller.close();
  });

  return controller.stream;
});

/// Booléen dérivé : l'utilisateur a-t-il un entitlement `premium` actif ?
/// Consommable directement par le paywall (ticket séparé) :
///
/// ```dart
/// final isPremium = ref.watch(isPremiumProvider);
/// ```
final isPremiumProvider = Provider<bool>((ref) {
  final asyncInfo = ref.watch(customerInfoProvider);
  return asyncInfo.maybeWhen(
    data: (info) =>
        info?.entitlements.active.containsKey(
          RevenueCatConstants.entitlementId,
        ) ??
        false,
    orElse: () => false,
  );
});
