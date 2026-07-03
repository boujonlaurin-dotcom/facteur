import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/orchestration/first_impression_orchestrator.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/lettres/widgets/lettres_notification_banner.dart';
import 'package:facteur/features/notif_du_jour/providers/notif_du_jour_day_store.dart';
import 'package:facteur/features/notif_du_jour/providers/notif_du_jour_provider.dart';
import 'package:facteur/features/notif_du_jour/widgets/notif_du_jour_card.dart';

class _FakeSerein extends SereinToggleNotifier {
  _FakeSerein(super.ref) {
    initFromApi(false);
  }

  int toggleCount = 0;

  @override
  Future<void> toggle() async {
    toggleCount++;
    state = state.copyWith(enabled: !state.enabled);
  }
}

Widget _wrap({
  required List<String> queue,
  FirstImpressionSlot slot = FirstImpressionSlot.none,
  bool lettresVisible = false,
  bool disableAnimations = false,
  _FakeSerein Function(Ref)? sereinFactory,
}) {
  return ProviderScope(
    overrides: [
      firstImpressionSlotProvider.overrideWithValue(slot),
      lettresBannerVisibleThisSessionProvider
          .overrideWith((_) => lettresVisible),
      notifDuJourQueueProvider.overrideWithValue(queue),
      sereinToggleProvider.overrideWith(
        (ref) => (sereinFactory ?? _FakeSerein.new)(ref),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: const Scaffold(body: NotifDuJourCard()),
      ),
    ),
  );
}

Future<void> _dismissCurrent(WidgetTester tester) async {
  await tester.tap(find.byIcon(PhosphorIcons.x()));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const profileQueue = ['serein', 'tournee', 'veille', 'recommencer'];

  testWidgets('rien tant que les prefs jour ne sont pas chargées',
      (tester) async {
    await tester.pumpWidget(_wrap(queue: profileQueue));
    // 1er frame : day store pas encore chargé → aucun message (anti-flash).
    expect(find.text('Pas dans le mood pour l\'actu chaude ?'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Pas dans le mood pour l\'actu chaude ?'), findsOneWidget);
  });

  testWidgets('affiche le premier message de la file avec son CTA',
      (tester) async {
    await tester.pumpWidget(_wrap(queue: profileQueue));
    await tester.pumpAndSettle();
    expect(find.text('Pas dans le mood pour l\'actu chaude ?'), findsOneWidget);
    expect(find.text('Activer le mode Serein'), findsOneWidget);
    expect(find.byIcon(PhosphorIcons.arrowRight()), findsOneWidget);
    // Un seul message à la fois.
    expect(find.text('Ton flux ne te ressemble pas encore ?'), findsNothing);
  });

  testWidgets('X consomme (persisté) et révèle le message suivant',
      (tester) async {
    await tester.pumpWidget(_wrap(queue: profileQueue));
    await tester.pumpAndSettle();

    await _dismissCurrent(tester);
    expect(find.text('Pas dans le mood pour l\'actu chaude ?'), findsNothing);
    expect(
      find.text('Ton flux ne te ressemble pas encore ?'),
      findsOneWidget,
    );

    final prefs = await SharedPreferences.getInstance();
    final raw = jsonDecode(prefs.getString(kNotifDuJourStateKey)!)
        as Map<String, dynamic>;
    expect(raw['consumed'], ['serein']);
  });

  testWidgets('plafond 3/jour : le 4e message ne s\'affiche pas',
      (tester) async {
    await tester.pumpWidget(_wrap(queue: profileQueue));
    await tester.pumpAndSettle();

    await _dismissCurrent(tester); // serein
    await _dismissCurrent(tester); // tournee
    expect(find.text('Du mal à suivre un sujet précis ?'), findsOneWidget);
    await _dismissCurrent(tester); // veille → cap atteint
    expect(find.text('Envie de repartir de zéro ?'), findsNothing);
    expect(find.byIcon(PhosphorIcons.x()), findsNothing);
  });

  testWidgets('reset au changement de jour : les consommés d\'hier repartent',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      kNotifDuJourStateKey: jsonEncode({
        'day': '2020-01-01',
        'consumed': ['serein', 'tournee', 'veille'],
      }),
    });
    await tester.pumpWidget(_wrap(queue: profileQueue));
    await tester.pumpAndSettle();
    expect(find.text('Pas dans le mood pour l\'actu chaude ?'), findsOneWidget);
  });

  testWidgets('reduced motion : retrait immédiat sans animation',
      (tester) async {
    await tester.pumpWidget(
      _wrap(queue: profileQueue, disableAnimations: true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(PhosphorIcons.x()));
    await tester.pump();
    await tester.pump();
    expect(find.text('Pas dans le mood pour l\'actu chaude ?'), findsNothing);
    expect(
      find.text('Ton flux ne te ressemble pas encore ?'),
      findsOneWidget,
    );
  });

  testWidgets('tap CTA Serein : bascule in-place + message suivant',
      (tester) async {
    _FakeSerein? serein;
    await tester.pumpWidget(
      _wrap(
        queue: profileQueue,
        sereinFactory: (ref) => serein = _FakeSerein(ref),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pas dans le mood pour l\'actu chaude ?'));
    await tester.pumpAndSettle();

    expect(serein!.toggleCount, 1);
    expect(find.text('Pas dans le mood pour l\'actu chaude ?'), findsNothing);
    expect(
      find.text('Ton flux ne te ressemble pas encore ?'),
      findsOneWidget,
    );
  });

  testWidgets('well_informed : rendu custom NPS (scores 1..10) sans CTA',
      (tester) async {
    await tester.pumpWidget(_wrap(queue: const ['well_informed']));
    await tester.pumpAndSettle();
    expect(
      find.text('Te sens-tu bien informé·e en ce moment ?'),
      findsOneWidget,
    );
    for (var i = 1; i <= 10; i++) {
      expect(find.text('$i'), findsOneWidget);
    }
    expect(find.byIcon(PhosphorIcons.arrowRight()), findsNothing);
  });

  testWidgets('cède aux modales de l\'orchestrateur', (tester) async {
    await tester.pumpWidget(
      _wrap(queue: profileQueue, slot: FirstImpressionSlot.notifModal),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pas dans le mood pour l\'actu chaude ?'), findsNothing);
  });

  testWidgets('cède au bandeau Lettres affiché cette session', (tester) async {
    await tester.pumpWidget(_wrap(queue: profileQueue, lettresVisible: true));
    await tester.pumpAndSettle();
    expect(find.text('Pas dans le mood pour l\'actu chaude ?'), findsNothing);
  });

  testWidgets('file vide → rien', (tester) async {
    await tester.pumpWidget(_wrap(queue: const []));
    await tester.pumpAndSettle();
    expect(find.byIcon(PhosphorIcons.x()), findsNothing);
  });
}
