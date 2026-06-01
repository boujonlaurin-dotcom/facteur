import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/analytics_provider.dart';

part 'theme_provider.g.dart';

/// Modes de thème exposés par l'application Facteur.
/// Distinct du `ThemeMode` de Flutter pour permettre 3 palettes
/// indépendantes (Papier Dessin / Encre & Nuit / Encre Pure).
enum AppThemeMode { light, dark, oled }

@riverpod
class ThemeNotifier extends _$ThemeNotifier {
  static const String _boxName = 'settings';
  static const String _keyThemeMode = 'theme_mode';

  @override
  AppThemeMode build() {
    final box = Hive.box(_boxName);
    final saved = box.get(_keyThemeMode) as String?;
    if (saved == null) return AppThemeMode.light;
    return _parseThemeMode(saved);
  }

  /// Met à jour la palette affichée sans la persister — utilisé pour la
  /// prévisualisation pendant le choix du thème (bottom sheet onboarding
  /// + profil). Si l'utilisateur annule, l'appelant ré-appelle
  /// `previewThemeMode` avec le mode initial pour revenir à l'état d'avant.
  void previewThemeMode(AppThemeMode mode) {
    state = mode;
  }

  /// Persiste le choix final et déclenche l'analytics si le mode a
  /// effectivement changé par rapport au `initial` (état au moment où
  /// l'utilisateur a ouvert la sheet — résiste aux previews intermédiaires).
  void commitThemeMode({
    required AppThemeMode initial,
    required AppThemeMode chosen,
  }) {
    state = chosen;
    Hive.box(_boxName).put(_keyThemeMode, chosen.name);
    if (initial != chosen) {
      unawaited(ref.read(analyticsServiceProvider).trackPreferenceChanged(
            key: 'theme_mode',
            oldValue: initial.name,
            newValue: chosen.name,
          ));
    }
  }

  /// Tolère l'ancien format `ThemeMode.light` / `ThemeMode.dark` persisté
  /// avant l'ajout du 3ᵉ thème — réécrit au prochain `commitThemeMode`.
  AppThemeMode _parseThemeMode(String raw) {
    final normalized =
        raw.startsWith('ThemeMode.') ? raw.substring('ThemeMode.'.length) : raw;
    return AppThemeMode.values.firstWhere(
      (e) => e.name == normalized,
      orElse: () => AppThemeMode.light,
    );
  }
}
