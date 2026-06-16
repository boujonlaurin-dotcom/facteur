import 'dart:io';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/settings/providers/language_preference_provider.dart';
import 'package:facteur/features/settings/screens/source_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

class _FakeLanguagePreferenceNotifier
    extends StateNotifier<LanguagePreferenceState>
    implements LanguagePreferenceNotifier {
  _FakeLanguagePreferenceNotifier()
      : super(const LanguagePreferenceState(
          hideNonFr: true,
          userSet: true,
          synced: true,
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  testWidgets('groups subscriptions, paid content and language settings',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          languagePreferenceProvider.overrideWith(
            (ref) => _FakeLanguagePreferenceNotifier(),
          ),
        ],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: const SourceSettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Paramètres des sources'), findsOneWidget);
    expect(find.text('Mes abonnements'), findsOneWidget);
    expect(find.text('Masquer les articles payants'), findsOneWidget);
    expect(find.text('Masquer les sources non françaises'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(2));
    expect(switches.every((toggle) => toggle.value), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
