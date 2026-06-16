import 'dart:io';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/settings/screens/appearance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  Widget buildScreen() {
    return ProviderScope(
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: const AppearanceScreen(),
      ),
    );
  }

  testWidgets('opens theme and article display selectors', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildScreen());

    expect(find.text('Apparence'), findsOneWidget);
    expect(find.text('Thème'), findsOneWidget);
    expect(find.text('Affichage des articles'), findsOneWidget);

    await tester.tap(find.text('Thème'));
    await tester.pumpAndSettle();
    expect(find.text('Comment préférez-vous lire ?'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Affichage des articles'));
    await tester.pumpAndSettle();
    expect(find.text('Comment veux-tu voir tes articles ?'), findsOneWidget);
  });
}
