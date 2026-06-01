import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:facteur/features/settings/providers/theme_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  test('ThemeNotifier defaults to AppThemeMode.light', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final themeMode = container.read(themeNotifierProvider);
    expect(themeMode, AppThemeMode.light);
  });

  test('ThemeNotifier persists AppThemeMode', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Initial state
    expect(container.read(themeNotifierProvider), AppThemeMode.light);

    // Change to dark
    container.read(themeNotifierProvider.notifier).commitThemeMode(
          initial: AppThemeMode.light,
          chosen: AppThemeMode.dark,
        );
    expect(container.read(themeNotifierProvider), AppThemeMode.dark);

    // Verify persistence
    final box = Hive.box<dynamic>('settings');
    expect(box.get('theme_mode'), 'dark');

    // Recreate container to simulate app restart
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    expect(container2.read(themeNotifierProvider),
        AppThemeMode.dark); // Should read from Hive
  });
}
