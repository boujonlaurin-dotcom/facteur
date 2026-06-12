import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/analytics_provider.dart';
import '../models/display_mode_spec.dart';

part 'display_mode_provider.g.dart';

/// Modes d'affichage des cartes d'articles, choisis par l'utilisateur depuis
/// le profil (ou la modal d'intro). Chaque mode mappe vers un
/// [DisplayModeSpec] — cf. [displayModeSpec].
enum DisplayMode { normal, minimal, playful }

extension DisplayModeSpecX on DisplayMode {
  DisplayModeSpec get spec => switch (this) {
        DisplayMode.normal => DisplayModeSpec.normal,
        DisplayMode.minimal => DisplayModeSpec.minimal,
        DisplayMode.playful => DisplayModeSpec.playful,
      };

  String get label => switch (this) {
        DisplayMode.normal => 'Normal',
        DisplayMode.minimal => 'Minimaliste',
        DisplayMode.playful => 'Lisible',
      };
}

@riverpod
class DisplayModeNotifier extends _$DisplayModeNotifier {
  static const String _boxName = 'settings';
  static const String _keyDisplayMode = 'display_mode';

  @override
  DisplayMode build() {
    final box = Hive.box(_boxName);
    final saved = box.get(_keyDisplayMode) as String?;
    if (saved == null) return DisplayMode.normal;
    return DisplayMode.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => DisplayMode.normal,
    );
  }

  /// Met à jour le mode affiché sans le persister — preview live pendant le
  /// choix (bottom sheet profil / modal d'intro). Si l'utilisateur annule,
  /// l'appelant ré-appelle `previewDisplayMode` avec le mode initial.
  void previewDisplayMode(DisplayMode mode) {
    state = mode;
  }

  /// Persiste le choix final et déclenche l'analytics si le mode a
  /// effectivement changé par rapport au `initial` (état au moment où
  /// l'utilisateur a ouvert la sheet — résiste aux previews intermédiaires).
  void commitDisplayMode({
    required DisplayMode initial,
    required DisplayMode chosen,
  }) {
    state = chosen;
    Hive.box(_boxName).put(_keyDisplayMode, chosen.name);
    if (initial != chosen) {
      unawaited(ref.read(analyticsServiceProvider).trackPreferenceChanged(
            key: 'display_mode',
            oldValue: initial.name,
            newValue: chosen.name,
          ));
    }
  }
}

/// Spec du mode courant — c'est ce provider que les cartes et le provider
/// Flux Continu watchent (recomposition automatique au changement de mode).
@riverpod
DisplayModeSpec displayModeSpec(DisplayModeSpecRef ref) =>
    ref.watch(displayModeNotifierProvider).spec;
