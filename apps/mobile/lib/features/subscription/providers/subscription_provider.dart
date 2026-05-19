import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../config/constants.dart';

/// Adaptateur fin autour des appels statiques de `purchases_flutter` pour
/// permettre l'injection d'un fake en test.
class PurchasesAdapter {
  const PurchasesAdapter();

  Future<CustomerInfo> getCustomerInfo() => Purchases.getCustomerInfo();

  Future<Offerings> getOfferings() => Purchases.getOfferings();

  Future<CustomerInfo> purchasePackage(Package package) async {
    final result = await Purchases.purchasePackage(package);
    return result.customerInfo;
  }

  Future<CustomerInfo> restorePurchases() => Purchases.restorePurchases();

  void addCustomerInfoUpdateListener(CustomerInfoUpdateListener listener) {
    Purchases.addCustomerInfoUpdateListener(listener);
  }

  void removeCustomerInfoUpdateListener(CustomerInfoUpdateListener listener) {
    Purchases.removeCustomerInfoUpdateListener(listener);
  }
}

final purchasesAdapterProvider =
    Provider<PurchasesAdapter>((ref) => const PurchasesAdapter());

@immutable
class SubscriptionState {
  final bool isSubscribed;
  final CustomerInfo? customerInfo;
  final bool loading;
  final String? error;

  const SubscriptionState({
    this.isSubscribed = false,
    this.customerInfo,
    this.loading = false,
    this.error,
  });

  SubscriptionState copyWith({
    bool? isSubscribed,
    CustomerInfo? customerInfo,
    bool? loading,
    Object? error = _sentinel,
  }) {
    return SubscriptionState(
      isSubscribed: isSubscribed ?? this.isSubscribed,
      customerInfo: customerInfo ?? this.customerInfo,
      loading: loading ?? this.loading,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const Object _sentinel = Object();

bool _hasPremiumEntitlement(CustomerInfo info) {
  return info.entitlements.active
      .containsKey(RevenueCatConstants.premiumEntitlementId);
}

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier(this._adapter) : super(const SubscriptionState()) {
    _adapter.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);
    unawaited(refresh());
  }

  final PurchasesAdapter _adapter;

  void _onCustomerInfoUpdate(CustomerInfo info) {
    state = state.copyWith(
      customerInfo: info,
      isSubscribed: _hasPremiumEntitlement(info),
    );
  }

  Future<void> refresh() async {
    try {
      final info = await _adapter.getCustomerInfo();
      state = state.copyWith(
        customerInfo: info,
        isSubscribed: _hasPremiumEntitlement(info),
        error: null,
      );
    } catch (e) {
      debugPrint('Subscription: refresh failed: $e');
    }
  }

  /// Tente d'acheter le package donné. Retourne `true` si l'utilisateur
  /// est abonné après l'achat. Une annulation utilisateur ne lève pas
  /// d'erreur visible.
  Future<bool> purchase(Package package) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final info = await _adapter.purchasePackage(package);
      final ok = _hasPremiumEntitlement(info);
      state = state.copyWith(
        loading: false,
        customerInfo: info,
        isSubscribed: ok,
      );
      return ok;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        state = state.copyWith(loading: false, error: null);
        return false;
      }
      state = state.copyWith(
        loading: false,
        error: e.message ?? 'Achat impossible',
      );
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  /// Restaure les achats. Retourne `true` si un entitlement actif a été
  /// retrouvé.
  Future<bool> restore() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final info = await _adapter.restorePurchases();
      final ok = _hasPremiumEntitlement(info);
      state = state.copyWith(
        loading: false,
        customerInfo: info,
        isSubscribed: ok,
      );
      return ok;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  @override
  void dispose() {
    _adapter.removeCustomerInfoUpdateListener(_onCustomerInfoUpdate);
    super.dispose();
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>(
  (ref) => SubscriptionNotifier(ref.watch(purchasesAdapterProvider)),
);

/// Charge les offerings RevenueCat (packages disponibles à l'achat).
final offeringsProvider = FutureProvider<Offerings>((ref) async {
  final adapter = ref.watch(purchasesAdapterProvider);
  return adapter.getOfferings();
});
