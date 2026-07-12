import 'package:facteur/features/premium/premium_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/soutien/providers/premium_gate_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSourcesNotifier extends UserSourcesNotifier {
  _FakeSourcesNotifier(this.count);

  final int count;

  @override
  Future<List<Source>> build() async => List.generate(
        count,
        (i) => Source(
          id: 'src-$i',
          name: 'Source $i',
          type: SourceType.article,
        ),
      );
}

ProviderContainer _makeContainer({
  required bool isPremium,
  required int sourceCount,
}) {
  final container = ProviderContainer(
    overrides: [
      isPremiumProvider.overrideWithValue(isPremium),
      userSourcesProvider.overrideWith(() => _FakeSourcesNotifier(sourceCount)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('free sous le cap : ajout possible, veille et serein verrouillés',
      () async {
    final container = _makeContainer(isPremium: false, sourceCount: 12);
    await container.read(userSourcesProvider.future);
    final gate = container.read(premiumGateProvider);

    expect(gate.followedSourcesCount, 12);
    expect(gate.sourceCapReached, isFalse);
    expect(gate.canCreateVeille, isFalse);
    expect(gate.canCustomizeSerein, isFalse);
  });

  test('free à 30 sources : cap atteint', () async {
    final container = _makeContainer(isPremium: false, sourceCount: 30);
    await container.read(userSourcesProvider.future);

    expect(container.read(premiumGateProvider).sourceCapReached, isTrue);
  });

  test('premium : jamais de cap, veille et serein débloqués', () async {
    final container = _makeContainer(isPremium: true, sourceCount: 45);
    await container.read(userSourcesProvider.future);
    final gate = container.read(premiumGateProvider);

    expect(gate.sourceCapReached, isFalse);
    expect(gate.canCreateVeille, isTrue);
    expect(gate.canCustomizeSerein, isTrue);
  });
}
