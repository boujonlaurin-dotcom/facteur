import 'package:facteur/features/subscription/providers/subscription_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class _MockAdapter extends Mock implements PurchasesAdapter {}

class _FakeCustomerInfo extends Fake implements CustomerInfo {
  _FakeCustomerInfo({required this.hasPremium});
  final bool hasPremium;

  @override
  EntitlementInfos get entitlements => _FakeEntitlements(hasPremium: hasPremium);
}

class _FakeEntitlements extends Fake implements EntitlementInfos {
  _FakeEntitlements({required this.hasPremium});
  final bool hasPremium;

  @override
  Map<String, EntitlementInfo> get active => hasPremium
      ? {'premium': _FakeEntitlementInfo()}
      : <String, EntitlementInfo>{};
}

class _FakeEntitlementInfo extends Fake implements EntitlementInfo {}

class _FakePackage extends Fake implements Package {}

void main() {
  late _MockAdapter adapter;

  setUpAll(() {
    registerFallbackValue(_FakePackage());
    registerFallbackValue((CustomerInfo _) {});
  });

  setUp(() {
    adapter = _MockAdapter();
    when(() => adapter.addCustomerInfoUpdateListener(any())).thenReturn(null);
    when(() => adapter.removeCustomerInfoUpdateListener(any())).thenReturn(null);
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [purchasesAdapterProvider.overrideWithValue(adapter)],
    );
  }

  test('refresh marks isSubscribed when premium entitlement is active',
      () async {
    when(() => adapter.getCustomerInfo())
        .thenAnswer((_) async => _FakeCustomerInfo(hasPremium: true));
    final container = makeContainer();
    addTearDown(container.dispose);

    // Bootstrap kicks off refresh() — wait for it.
    await container.read(subscriptionProvider.notifier).refresh();

    expect(container.read(subscriptionProvider).isSubscribed, isTrue);
  });

  test('purchase success flips isSubscribed and clears loading', () async {
    when(() => adapter.getCustomerInfo())
        .thenAnswer((_) async => _FakeCustomerInfo(hasPremium: false));
    when(() => adapter.purchasePackage(any()))
        .thenAnswer((_) async => _FakeCustomerInfo(hasPremium: true));

    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(subscriptionProvider.notifier).refresh();

    final ok = await container
        .read(subscriptionProvider.notifier)
        .purchase(_FakePackage());

    expect(ok, isTrue);
    final s = container.read(subscriptionProvider);
    expect(s.isSubscribed, isTrue);
    expect(s.loading, isFalse);
    expect(s.error, isNull);
  });

  test('cancelled purchase exposes no error and returns false', () async {
    when(() => adapter.getCustomerInfo())
        .thenAnswer((_) async => _FakeCustomerInfo(hasPremium: false));
    when(() => adapter.purchasePackage(any())).thenThrow(
      PlatformException(
        code: '1',
        message: 'cancelled',
        details: {'readable_error_code': 'PURCHASE_CANCELLED'},
      ),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(subscriptionProvider.notifier).refresh();

    final ok = await container
        .read(subscriptionProvider.notifier)
        .purchase(_FakePackage());

    expect(ok, isFalse);
    final s = container.read(subscriptionProvider);
    expect(s.isSubscribed, isFalse);
    expect(s.error, isNull);
    expect(s.loading, isFalse);
  });

  test('restore without active entitlement keeps isSubscribed=false',
      () async {
    when(() => adapter.getCustomerInfo())
        .thenAnswer((_) async => _FakeCustomerInfo(hasPremium: false));
    when(() => adapter.restorePurchases())
        .thenAnswer((_) async => _FakeCustomerInfo(hasPremium: false));

    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(subscriptionProvider.notifier).refresh();

    final ok =
        await container.read(subscriptionProvider.notifier).restore();

    expect(ok, isFalse);
    expect(container.read(subscriptionProvider).isSubscribed, isFalse);
  });
}
