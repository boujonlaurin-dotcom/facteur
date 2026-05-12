// Test : dashboard veille — visibilité de la CTA « Lancer ma première veille »
// selon l'état de la dernière livraison.
//
// Bug `bug-first-veille-no-retry.md` : tant qu'aucune livraison succeeded
// non-vide n'existe, on doit proposer une option de relance. Une livraison
// pending/running de moins de 15 min reste invisible (génération en cours).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/models/veille_delivery.dart';
import 'package:facteur/features/veille/providers/veille_active_config_provider.dart';
import 'package:facteur/features/veille/providers/veille_deliveries_provider.dart'
    show VeilleLastDeliveryNotifier, veilleLastDeliveryProvider;
import 'package:facteur/features/veille/screens/veille_dashboard_screen.dart';

VeilleConfigDto _fakeCfg() {
  final now = DateTime.now();
  return VeilleConfigDto(
    id: 'cfg-1',
    userId: 'user-1',
    themeId: 'tech',
    themeLabel: 'Tech',
    frequency: 'weekly',
    dayOfWeek: 0,
    deliveryHour: 7,
    timezone: 'Europe/Paris',
    status: 'active',
    lastDeliveredAt: null,
    nextScheduledAt: null,
    createdAt: now,
    updatedAt: now,
    topics: const [],
    sources: const [],
  );
}

VeilleDeliveryListItem _delivery({
  required VeilleGenerationState state,
  int itemCount = 0,
  Duration ageFromNow = Duration.zero,
}) {
  final now = DateTime.now();
  return VeilleDeliveryListItem(
    id: 'd-1',
    veilleConfigId: 'cfg-1',
    targetDate: now,
    generationState: state,
    itemCount: itemCount,
    generatedAt: state == VeilleGenerationState.succeeded ? now : null,
    createdAt: now.subtract(ageFromNow),
  );
}

class _FakeActiveCfgNotifier extends VeilleActiveConfigNotifier {
  final VeilleConfigDto? initial;
  _FakeActiveCfgNotifier(this.initial);
  @override
  Future<VeilleConfigDto?> build() async => initial;
}

class _FakeLastDeliveryNotifier extends VeilleLastDeliveryNotifier {
  final VeilleDeliveryListItem? initial;
  _FakeLastDeliveryNotifier(this.initial);
  @override
  Future<VeilleDeliveryListItem?> build() async => initial;
}

Widget _wrap({
  required VeilleConfigDto cfg,
  VeilleDeliveryListItem? lastDelivery,
}) {
  return ProviderScope(
    overrides: [
      veilleActiveConfigProvider.overrideWith(
        () => _FakeActiveCfgNotifier(cfg),
      ),
      veilleLastDeliveryProvider.overrideWith(
        () => _FakeLastDeliveryNotifier(lastDelivery),
      ),
    ],
    child: const MaterialApp(home: VeilleDashboardScreen()),
  );
}

const _ctaFirst = 'Lancer ma première veille';
const _ctaRetry = 'Relancer ma première veille';

void main() {
  testWidgets('aucune livraison → CTA "Lancer" visible', (tester) async {
    await tester.pumpWidget(_wrap(cfg: _fakeCfg()));
    await tester.pumpAndSettle();

    expect(find.text(_ctaFirst), findsOneWidget);
    expect(find.text(_ctaRetry), findsNothing);
  });

  testWidgets('dernière livraison failed → CTA "Relancer" visible',
      (tester) async {
    await tester.pumpWidget(_wrap(
      cfg: _fakeCfg(),
      lastDelivery: _delivery(state: VeilleGenerationState.failed),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_ctaRetry), findsOneWidget);
    expect(find.text(_ctaFirst), findsNothing);
  });

  testWidgets('dernière livraison succeeded mais vide → CTA "Relancer"',
      (tester) async {
    await tester.pumpWidget(_wrap(
      cfg: _fakeCfg(),
      lastDelivery:
          _delivery(state: VeilleGenerationState.succeeded, itemCount: 0),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_ctaRetry), findsOneWidget);
  });

  testWidgets('dernière livraison succeeded avec items → CTA cachée',
      (tester) async {
    await tester.pumpWidget(_wrap(
      cfg: _fakeCfg(),
      lastDelivery:
          _delivery(state: VeilleGenerationState.succeeded, itemCount: 3),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_ctaFirst), findsNothing);
    expect(find.text(_ctaRetry), findsNothing);
  });

  testWidgets('running récent (<15 min) → CTA cachée', (tester) async {
    await tester.pumpWidget(_wrap(
      cfg: _fakeCfg(),
      lastDelivery: _delivery(
        state: VeilleGenerationState.running,
        ageFromNow: const Duration(minutes: 2),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_ctaFirst), findsNothing);
    expect(find.text(_ctaRetry), findsNothing);
  });

  testWidgets('running stuck (>15 min) → CTA "Relancer" visible',
      (tester) async {
    await tester.pumpWidget(_wrap(
      cfg: _fakeCfg(),
      lastDelivery: _delivery(
        state: VeilleGenerationState.running,
        ageFromNow: const Duration(minutes: 30),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_ctaRetry), findsOneWidget);
  });
}
