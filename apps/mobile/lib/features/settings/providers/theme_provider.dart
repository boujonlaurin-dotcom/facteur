import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'theme_provider.g.dart';

@riverpod
class ThemeNotifier extends _$ThemeNotifier {
  static const String _boxName = 'settings';
  static const String _keyThemeMode = 'theme_mode';

  @override
  ThemeMode build() {
    // Lire la valeur persistée ou utiliser la logique par défaut
    final box = Hive.box(_boxName);
    final savedMode = box.get(_keyThemeMode) as String?;

    if (savedMode != null) {
      return _parseThemeMode(savedMode);
    }

    return ThemeMode.light; // Défaut : Papier Dessin
  }

  /// Change le mode et persiste le choix
  void setThemeMode(ThemeMode mode) {
    state = mode;
    final box = Hive.box(_boxName);
    box.put(_keyThemeMode, mode.toString());
  }

  /// Helper pour parser la string persistée
  ThemeMode _parseThemeMode(String modeStr) {
    return ThemeMode.values.firstWhere(
      (e) => e.toString() == modeStr,
      orElse: () => ThemeMode.light,
    );
  }
}
