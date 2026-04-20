import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../digest/providers/digest_provider.dart';

/// Default themes excluded in serein mode when the user has not personalised.
/// Must stay in sync with `SEREIN_EXCLUDED_THEMES` in
/// `packages/api/app/services/recommendation/filter_presets.py`.
const List<String> defaultSereinExcludedThemes = <String>[
  'society',
  'international',
  'economy',
  'politics',
];

/// Snapshot of the user's serein theme-level exclusions.
///
/// Topic-level exclusions live on [UserTopicProfile.excludedFromSerein] and
/// are managed via [customTopicsProvider] — this provider only covers the
/// theme dimension stored in `user_preferences`.
class SereinExclusionsState {
  final Set<String> excludedThemeSlugs;

  /// `true` once the user has explicitly toggled anything. When `false`, the
  /// effective exclusions are [defaultSereinExcludedThemes] (server applies
  /// the same logic; we mirror it here only for UI preview).
  final bool personalized;
  final bool loaded;

  const SereinExclusionsState({
    required this.excludedThemeSlugs,
    required this.personalized,
    required this.loaded,
  });

  const SereinExclusionsState.initial()
      : excludedThemeSlugs = const <String>{},
        personalized = false,
        loaded = false;

  /// Effective theme exclusions applied by the backend.
  Set<String> get effectiveExclusions =>
      personalized ? excludedThemeSlugs : defaultSereinExcludedThemes.toSet();

  SereinExclusionsState copyWith({
    Set<String>? excludedThemeSlugs,
    bool? personalized,
    bool? loaded,
  }) {
    return SereinExclusionsState(
      excludedThemeSlugs: excludedThemeSlugs ?? this.excludedThemeSlugs,
      personalized: personalized ?? this.personalized,
      loaded: loaded ?? this.loaded,
    );
  }
}

/// Provider managing theme-level serein exclusions (checked = shown).
///
/// Fire-and-forget persistence via `users/preferences`: UI updates
/// optimistically, server errors are swallowed (silent retry on next load).
final sereinExclusionsProvider = StateNotifierProvider<
    SereinExclusionsNotifier, SereinExclusionsState>((ref) {
  return SereinExclusionsNotifier(ref);
});

class SereinExclusionsNotifier extends StateNotifier<SereinExclusionsState> {
  final Ref _ref;
  bool _loading = false;

  SereinExclusionsNotifier(this._ref)
      : super(const SereinExclusionsState.initial());

  /// Fetch `sensitive_themes` + `serein_personalized` from the API on first
  /// access. Safe to call multiple times.
  Future<void> loadIfNeeded() async {
    if (state.loaded || _loading) return;
    _loading = true;
    try {
      final repository = _ref.read(digestRepositoryProvider);
      final prefs = await repository.getPreferences();
      final excluded = <String>{};
      var personalized = false;
      for (final pref in prefs) {
        final key = pref['preference_key'];
        final value = pref['preference_value'];
        if (value == null) continue;
        if (key == 'sensitive_themes') {
          try {
            final parsed = (jsonDecode(value) as List<dynamic>).cast<String>();
            excluded
              ..clear()
              ..addAll(parsed);
          } catch (_) {
            // Ignore malformed JSON — treat as empty.
          }
        } else if (key == 'serein_personalized' && value == 'true') {
          personalized = true;
        }
      }
      state = SereinExclusionsState(
        excludedThemeSlugs: excluded,
        personalized: personalized,
        loaded: true,
      );
    } catch (_) {
      // Silent fail — UI falls back to defaults; next call retries.
    } finally {
      _loading = false;
    }
  }

  /// Toggle whether a theme is *shown* in serein mode.
  /// `shown=true`  → remove from exclusions.
  /// `shown=false` → add to exclusions.
  Future<void> setThemeShown(String themeSlug, bool shown) async {
    final base =
        state.personalized ? state.excludedThemeSlugs : state.effectiveExclusions;
    final updated = Set<String>.from(base);
    if (shown) {
      updated.remove(themeSlug);
    } else {
      updated.add(themeSlug);
    }
    await _persist(updated);
  }

  /// Bulk helper used by the theme-header tri-state checkbox. Cascades to the
  /// given topic IDs so the user sees a coherent check/uncheck for the
  /// entire section.
  Future<void> setThemeShownCascade({
    required String themeSlug,
    required bool shown,
  }) async {
    await setThemeShown(themeSlug, shown);
  }

  Future<void> _persist(Set<String> excluded) async {
    HapticFeedback.lightImpact();

    final previousState = state;
    final wasPersonalized = state.personalized;
    state = SereinExclusionsState(
      excludedThemeSlugs: excluded,
      personalized: true,
      loaded: true,
    );

    final repository = _ref.read(digestRepositoryProvider);
    try {
      await repository.updatePreference(
        key: 'sensitive_themes',
        value: jsonEncode(excluded.toList()),
      );
      if (!wasPersonalized) {
        await repository.updatePreference(
          key: 'serein_personalized',
          value: 'true',
        );
      }
    } catch (e) {
      // Rollback so the UI doesn't claim a change the server rejected.
      state = previousState;
      rethrow;
    }
  }
}
