import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/veille_mock_data.dart';
import '../models/veille_config.dart';

/// État du flow de configuration de la veille (4 étapes).
///
/// `step` est de 1..4. Quand `loadingFrom` est non-null, on affiche l'écran
/// de transition LLM entre `loadingFrom` et `loadingFrom + 1`.
@immutable
class VeilleConfigState {
  final int step;
  final int? loadingFrom;

  final String? selectedTheme;
  final Set<String> selectedTopics;
  final Set<String> selectedSuggestions;
  final Set<String> followedSources;
  final Set<String> nicheSources;
  final VeilleFrequency frequency;
  final VeilleDay day;

  const VeilleConfigState({
    required this.step,
    required this.loadingFrom,
    required this.selectedTheme,
    required this.selectedTopics,
    required this.selectedSuggestions,
    required this.followedSources,
    required this.nicheSources,
    required this.frequency,
    required this.day,
  });

  factory VeilleConfigState.initial() => const VeilleConfigState(
        step: 1,
        loadingFrom: null,
        selectedTheme: null,
        selectedTopics: <String>{},
        selectedSuggestions: VeilleMockData.defaultSuggestions,
        followedSources: VeilleMockData.defaultFollowedSources,
        nicheSources: VeilleMockData.defaultNicheSources,
        frequency: VeilleFrequency.weekly,
        day: VeilleDay.mon,
      );

  bool get isLoading => loadingFrom != null;

  int get totalSelectedAngles =>
      selectedTopics.length + selectedSuggestions.length;
  int get totalSelectedSources => followedSources.length + nicheSources.length;
  int get totalSelectedTopics => selectedTopics.length;

  VeilleConfigState copyWith({
    int? step,
    Object? loadingFrom = _Sentinel.value,
    Object? selectedTheme = _Sentinel.value,
    Set<String>? selectedTopics,
    Set<String>? selectedSuggestions,
    Set<String>? followedSources,
    Set<String>? nicheSources,
    VeilleFrequency? frequency,
    VeilleDay? day,
  }) =>
      VeilleConfigState(
        step: step ?? this.step,
        loadingFrom: loadingFrom == _Sentinel.value
            ? this.loadingFrom
            : loadingFrom as int?,
        selectedTheme: selectedTheme == _Sentinel.value
            ? this.selectedTheme
            : selectedTheme as String?,
        selectedTopics: selectedTopics ?? this.selectedTopics,
        selectedSuggestions: selectedSuggestions ?? this.selectedSuggestions,
        followedSources: followedSources ?? this.followedSources,
        nicheSources: nicheSources ?? this.nicheSources,
        frequency: frequency ?? this.frequency,
        day: day ?? this.day,
      );
}

enum _Sentinel { value }

class VeilleConfigNotifier extends StateNotifier<VeilleConfigState> {
  VeilleConfigNotifier() : super(VeilleConfigState.initial());

  static const Duration _loadingDuration = Duration(milliseconds: 2500);

  Timer? _loadingTimer;

  void selectTheme(String id) {
    final shouldSeedTopics =
        state.selectedTheme == null && state.selectedTopics.isEmpty;
    state = state.copyWith(
      selectedTheme: id,
      selectedTopics:
          shouldSeedTopics ? VeilleMockData.defaultTopics : null,
    );
  }

  void toggleTopic(String id) =>
      state = state.copyWith(selectedTopics: _toggle(state.selectedTopics, id));

  void toggleSuggestion(String id) => state = state.copyWith(
        selectedSuggestions: _toggle(state.selectedSuggestions, id),
      );

  void toggleFollowedSource(String id) => state = state.copyWith(
        followedSources: _toggle(state.followedSources, id),
      );

  void toggleNicheSource(String id) =>
      state = state.copyWith(nicheSources: _toggle(state.nicheSources, id));

  void setFrequency(VeilleFrequency f) => state = state.copyWith(frequency: f);
  void setDay(VeilleDay d) => state = state.copyWith(day: d);

  /// Avance d'une étape, en passant par un loading screen IA (sauf si on est
  /// déjà sur la dernière étape — auquel cas `submit()` doit être appelé).
  void goNext() {
    if (state.isLoading || state.step >= 4) return;
    final from = state.step;
    state = state.copyWith(loadingFrom: from);
    _loadingTimer?.cancel();
    _loadingTimer = Timer(_loadingDuration, () {
      if (!mounted) return;
      state = state.copyWith(step: from + 1, loadingFrom: null);
    });
  }

  /// Recul instantané (pas de loading).
  void goBack() {
    if (state.isLoading) return;
    if (state.step <= 1) return;
    state = state.copyWith(step: state.step - 1);
  }

  /// Sortie de la 4e étape — pour l'instant pas d'appel API.
  Future<void> submit() async {
    // TODO(veille): brancher POST /veille/config quand backend dispo.
  }

  Set<String> _toggle(Set<String> set, String id) {
    final next = Set<String>.from(set);
    if (!next.add(id)) next.remove(id);
    return next;
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }
}

final veilleConfigProvider =
    StateNotifierProvider.autoDispose<VeilleConfigNotifier, VeilleConfigState>(
  (ref) => VeilleConfigNotifier(),
);
