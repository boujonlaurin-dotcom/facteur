import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/lettres/widgets/progress_toast.dart';

Widget _harness({required void Function(BuildContext) onReady}) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Builder(
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onReady(context));
        return const Scaffold(body: SizedBox.shrink());
      },
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('niveau micro affiche le label + compteur puis disparaît',
      (tester) async {
    await tester.pumpWidget(_harness(
      onReady: (ctx) => showProgressToast(
        ctx,
        level: ProgressToastLevel.micro,
        current: 1,
        total: 3,
        label: 'Premier rendez-vous tenu.',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Premier rendez-vous tenu.'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Premier rendez-vous tenu.'), findsNothing);
  });

  testWidgets('niveau étape est cliquable et invoque onOpen', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_harness(
      onReady: (ctx) => showProgressToast(
        ctx,
        level: ProgressToastLevel.step,
        stepNum: '01',
        stepTitle: 'Tes premières sources',
        onOpen: () => opened++,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Tes premières sources'), findsOneWidget);
    expect(find.text('Ouvrir le cachet'), findsOneWidget);

    await tester.tap(find.text('Tes premières sources'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(opened, 1);
  });

  testWidgets('niveau section affiche titre Fraunces + sous-titre 100%',
      (tester) async {
    await tester.pumpWidget(_harness(
      onReady: (ctx) => showProgressToast(
        ctx,
        level: ProgressToastLevel.section,
        sectionTitle: 'Bonne nouvelle du jour',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Bonne nouvelle du jour'), findsOneWidget);
    expect(find.text('Lue de bout en bout · 100%'), findsOneWidget);
  });
}
