import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/lettres/widgets/palier_toast.dart';

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

  testWidgets('shows the message then auto-dismisses', (tester) async {
    await tester.pumpWidget(_harness(
      onReady: (ctx) => showPalierToast(ctx, 'Premier rendez-vous tenu.'),
    ));
    // Frame 1: postFrameCallback fires, Overlay inserts entry.
    await tester.pump();
    // Frame 2: fade-in starts.
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Premier rendez-vous tenu.'), findsOneWidget);

    // Hold (4s) + fade-out (250ms) → entry removed.
    await tester.pump(const Duration(milliseconds: 4000));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Premier rendez-vous tenu.'), findsNothing);
  });
}
