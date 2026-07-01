import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/widgets/reconnect_subscriptions_banner.dart';

Source _source(String id, String name) => Source(
      id: id,
      name: name,
      type: SourceType.article,
      url: 'https://$id.example',
      isTrusted: true,
      hasSubscription: true,
      hasPaywall: true,
    );

Widget _wrap({
  required List<Source> needing,
  required bool cooldownActive,
}) {
  return ProviderScope(
    overrides: [
      subscriptionsNeedingReconnectProvider.overrideWith(
        (ref) async => needing,
      ),
      reconnectBannerCooldownActiveProvider.overrideWith(
        (ref) async => cooldownActive,
      ),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: const Scaffold(body: ReconnectSubscriptionsBanner()),
    ),
  );
}

void main() {
  testWidgets('shows when sessions are missing and cooldown is inactive',
      (tester) async {
    await tester.pumpWidget(_wrap(
      needing: [_source('lemonde', 'Le Monde'), _source('mediapart', 'Mediapart')],
      cooldownActive: false,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Reconnecte tes abonnements'), findsOneWidget);
    expect(find.text('2 abonnements à reconnecter après la mise à jour.'),
        findsOneWidget);
    expect(find.text('Reconnecter'), findsOneWidget);
  });

  testWidgets('uses the singular copy for a single subscription',
      (tester) async {
    await tester.pumpWidget(_wrap(
      needing: [_source('lemonde', 'Le Monde')],
      cooldownActive: false,
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 abonnement à reconnecter après la mise à jour.'),
        findsOneWidget);
  });

  testWidgets('hides when nothing needs reconnecting (auto-clearing)',
      (tester) async {
    await tester.pumpWidget(_wrap(needing: const [], cooldownActive: false));
    await tester.pumpAndSettle();

    expect(find.text('Reconnecte tes abonnements'), findsNothing);
  });

  testWidgets('hides while the dismiss cooldown is active', (tester) async {
    await tester.pumpWidget(_wrap(
      needing: [_source('lemonde', 'Le Monde')],
      cooldownActive: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Reconnecte tes abonnements'), findsNothing);
  });
}
