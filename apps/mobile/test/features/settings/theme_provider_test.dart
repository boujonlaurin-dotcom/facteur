import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:facteur/features/settings/providers/theme_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  test('ThemeNotifier defaults to ThemeMode.light', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final themeMode = container.read(themeNotifierProvider);
    expect(themeMode, ThemeMode.light);
  });

  test('ThemeNotifier persists ThemeMode', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Initial state
    expect(container.read(themeNotifierProvider), ThemeMode.light);

    // Change to dark
    container.read(themeNotifierProvider.notifier).setThemeMode(ThemeMode.dark);
    expect(container.read(themeNotifierProvider), ThemeMode.dark);

    // Verify persistence
    final box = Hive.box('settings');
    expect(box.get('theme_mode'), 'ThemeMode.dark');

    // Recreate container to simulate app restart
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    expect(container2.read(themeNotifierProvider),
        ThemeMode.dark); // Should read from Hive
  });
}
