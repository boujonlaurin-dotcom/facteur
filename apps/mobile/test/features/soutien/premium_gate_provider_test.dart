import 'package:facteur/features/premium/premium_provider.dart';
import 'package:facteur/features/soutien/providers/premium_gate_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _makeContainer({required bool isPremium}) {
  final container = ProviderContainer(
    overrides: [
      isPremiumProvider.overrideWithValue(isPremium),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('free : veille et serein verrouillés', () {
    final gate = _makeContainer(isPremium: false).read(premiumGateProvider);

    expect(gate.isPremium, isFalse);
    expect(gate.canCreateVeille, isFalse);
    expect(gate.canCustomizeSerein, isFalse);
  });

  test('premium : veille et serein débloqués', () {
    final gate = _makeContainer(isPremium: true).read(premiumGateProvider);

    expect(gate.isPremium, isTrue);
    expect(gate.canCreateVeille, isTrue);
    expect(gate.canCustomizeSerein, isTrue);
  });
}
