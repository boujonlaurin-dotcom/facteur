import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'digest_provider.dart';

/// Provider pour les sujets sensibles de l'utilisateur (mode serein).
/// Pattern fire-and-forget identique à SereinToggleNotifier.
final sensitiveThemesProvider =
    StateNotifierProvider<SensitiveThemesNotifier, List<String>>((ref) {
  return SensitiveThemesNotifier(ref);
});

class SensitiveThemesNotifier extends StateNotifier<List<String>> {
  final Ref _ref;
  bool _loaded = false;

  SensitiveThemesNotifier(this._ref) : super([]);

  /// Initialise depuis les préférences API.
  void initFromApi(List<String> themes) {
    state = themes;
    _loaded = true;
  }

  /// Charge les sensitive_themes depuis l'API si pas encore fait.
  Future<void> loadIfNeeded() async {
    if (_loaded) return;
    try {
      final repository = _ref.read(digestRepositoryProvider);
      final prefs = await repository.getPreferences();
      for (final pref in prefs) {
        if (pref['preference_key'] == 'sensitive_themes') {
          final raw = pref['preference_value'];
          if (raw != null) {
            final parsed =
                (jsonDecode(raw) as List<dynamic>).cast<String>();
            state = parsed;
          }
          break;
        }
      }
      _loaded = true; // Only mark loaded on success
    } catch (_) {
      // Silent fail — will retry next time
    }
  }

  /// Toggle un thème sensible — UI immédiat, sauvegarde en background.
  Future<void> toggle(String theme) async {
    final updated = List<String>.from(state);
    if (updated.contains(theme)) {
      updated.remove(theme);
    } else {
      updated.add(theme);
    }

    // 1. Immediate UI update
    state = updated;

    // 2. Haptic
    HapticFeedback.lightImpact();

    // 3. Persist preference (fire-and-forget)
    try {
      final repository = _ref.read(digestRepositoryProvider);
      await repository.updatePreference(
        key: 'sensitive_themes',
        value: jsonEncode(updated),
      );
    } catch (_) {
      // Silent fail — preference retried next session
    }
  }
}
