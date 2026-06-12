import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';

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

  test('defaults to DisplayMode.normal', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(displayModeNotifierProvider), DisplayMode.normal);
    expect(container.read(displayModeSpecProvider), DisplayModeSpec.normal);
  });

  test('commitDisplayMode persists and survives restart', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(displayModeNotifierProvider.notifier).commitDisplayMode(
          initial: DisplayMode.normal,
          chosen: DisplayMode.minimal,
        );
    expect(container.read(displayModeNotifierProvider), DisplayMode.minimal);
    expect(Hive.box<dynamic>('settings').get('display_mode'), 'minimal');

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    expect(container2.read(displayModeNotifierProvider), DisplayMode.minimal);
  });

  test('previewDisplayMode updates state without persisting', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(displayModeNotifierProvider.notifier)
        .previewDisplayMode(DisplayMode.playful);
    expect(container.read(displayModeNotifierProvider), DisplayMode.playful);
    expect(container.read(displayModeSpecProvider), DisplayModeSpec.playful);
    expect(Hive.box<dynamic>('settings').get('display_mode'), isNull);

    // Restore (annulation de la sheet) : retour au mode initial.
    container
        .read(displayModeNotifierProvider.notifier)
        .previewDisplayMode(DisplayMode.normal);
    expect(container.read(displayModeNotifierProvider), DisplayMode.normal);
  });

  test('unknown persisted value falls back to normal', () {
    Hive.box<dynamic>('settings').put('display_mode', 'hologram');
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(displayModeNotifierProvider), DisplayMode.normal);
  });
}
