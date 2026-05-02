import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/push_notification_service.dart';
import '../data/veille_mock_data.dart';
import '../models/veille_config.dart';
import '../models/veille_config_dto.dart';
import '../models/veille_suggestion.dart';
import '../repositories/veille_repository.dart';
import 'veille_active_config_provider.dart';
import 'veille_repository_provider.dart';

/// Métadonnées attachées à une source dans le state du flow. Permet de
/// distinguer les sources catalogue (UUID API) des sources mock-only ; au
/// submit on filtre les mock-only et on envoie un `source_id` (UUID) ou un
/// `niche_candidate{name, url}` selon ce qui est dispo.
@immutable
class VeilleSourceMeta {
  final String slug;
  final String name;
  final String kind; // "followed" | "niche"
  final String? apiSourceId; // UUID si la source vient du catalogue
  final String? url;
  final String? why;

  const VeilleSourceMeta({
    required this.slug,
    required this.name,
    required this.kind,
    this.apiSourceId,
    this.url,
    this.why,
  });
}

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

  /// Mapping slug → label pour topics (mock défauts + override API).
  final Map<String, String> topicLabels;

  /// Mapping slug → metadata pour sources (mock défauts + override API).
  final Map<String, VeilleSourceMeta> sourcesMeta;

  /// Submit en cours — empêche les double-tap.
  final bool isSubmitting;

  /// Dernier message d'erreur API. UI le pop dans un Snackbar puis le clear.
  final String? lastError;

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
    required this.topicLabels,
    required this.sourcesMeta,
    required this.isSubmitting,
    required this.lastError,
  });

  factory VeilleConfigState.initial() => VeilleConfigState(
        step: 1,
        loadingFrom: null,
        selectedTheme: null,
        selectedTopics: VeilleMockData.defaultTopics,
        selectedSuggestions: VeilleMockData.defaultSuggestions,
        followedSources: VeilleMockData.defaultFollowedSources,
        nicheSources: VeilleMockData.defaultNicheSources,
        frequency: VeilleFrequency.weekly,
        day: VeilleDay.mon,
        topicLabels: _initialTopicLabels(),
        sourcesMeta: const {},
        isSubmitting: false,
        lastError: null,
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
    Map<String, String>? topicLabels,
    Map<String, VeilleSourceMeta>? sourcesMeta,
    bool? isSubmitting,
    Object? lastError = _Sentinel.value,
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
        topicLabels: topicLabels ?? this.topicLabels,
        sourcesMeta: sourcesMeta ?? this.sourcesMeta,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        lastError:
            lastError == _Sentinel.value ? this.lastError : lastError as String?,
      );

  static Map<String, String> _initialTopicLabels() {
    final out = <String, String>{};
    for (final t in VeilleMockData.presetTopics) {
      out[t.id] = t.label;
    }
    for (final t in VeilleMockData.suggestedTopics) {
      out[t.id] = t.label;
    }
    return out;
  }

}

enum _Sentinel { value }

class VeilleConfigNotifier extends StateNotifier<VeilleConfigState> {
  VeilleConfigNotifier(this._ref) : super(VeilleConfigState.initial());

  final Ref _ref;

  static const Duration _loadingDuration = Duration(milliseconds: 2500);
  static const Duration _veilleNotificationLeadTime = Duration(minutes: 30);

  Timer? _loadingTimer;

  void selectTheme(String id) {
    state = state.copyWith(selectedTheme: id);
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

  /// Hydrate l'état avec des suggestions topics venues de l'API (étape 2).
  /// Le mapping slug → label est mis à jour ; les sélections existantes ne
  /// sont pas touchées.
  void applyTopicSuggestions(List<VeilleTopicSuggestion> apiTopics) {
    if (apiTopics.isEmpty) return;
    final next = Map<String, String>.from(state.topicLabels);
    for (final t in apiTopics) {
      next[t.topicId] = t.label;
    }
    state = state.copyWith(topicLabels: next);
  }

  /// Hydrate l'état avec des suggestions sources venues de l'API (étape 3).
  ///
  /// Les sources API alimentent toujours `sourcesMeta`. Pour les sélections
  /// par défaut, on ne pré-coche que lors de la 1ère hydratation API (quand
  /// aucune sélection user ne référence un UUID API). Une invalidation ulté-
  /// rieure (« Proposer plus de sources ») ne doit pas wipe les choix user.
  void applySourceSuggestions(VeilleSourceSuggestionsResponse apiSources) {
    final nextMeta = Map<String, VeilleSourceMeta>.from(state.sourcesMeta);

    for (final s in apiSources.followed) {
      nextMeta[s.sourceId] = VeilleSourceMeta(
        slug: s.sourceId,
        name: s.name,
        kind: 'followed',
        apiSourceId: s.sourceId,
        url: s.url,
        why: s.why,
      );
    }
    for (final s in apiSources.niche) {
      nextMeta[s.sourceId] = VeilleSourceMeta(
        slug: s.sourceId,
        name: s.name,
        kind: 'niche',
        apiSourceId: s.sourceId,
        url: s.url,
        why: s.why,
      );
    }

    final hasUserApiSelection = state.followedSources
            .any((slug) => state.sourcesMeta[slug]?.apiSourceId != null) ||
        state.nicheSources
            .any((slug) => state.sourcesMeta[slug]?.apiSourceId != null);

    if (hasUserApiSelection) {
      state = state.copyWith(sourcesMeta: nextMeta);
      return;
    }

    state = state.copyWith(
      sourcesMeta: nextMeta,
      followedSources: apiSources.followed.map((s) => s.sourceId).toSet(),
      nicheSources: apiSources.niche.map((s) => s.sourceId).toSet(),
    );
  }

  /// Sortie de la 4e étape — POST /api/veille/config + planification de la
  /// notif locale à `next_scheduled_at + 30 min`.
  ///
  /// Les sources mock-only (sans `apiSourceId`) sont filtrées : seules les
  /// sources catalogue (UUID API) sont envoyées, sinon le backend rejette.
  Future<void> submit() async {
    if (state.isSubmitting) return;
    state = state.copyWith(isSubmitting: true, lastError: null);

    try {
      final body = _buildUpsertRequest(state);
      final repo = _ref.read(veilleRepositoryProvider);
      final cfg = await repo.upsertConfig(body);

      // Best-effort — un échec de planification ne doit pas bloquer la
      // soumission. La notif locale est rejouée à l'open.
      try {
        if (cfg.nextScheduledAt != null) {
          final scheduledAt =
              cfg.nextScheduledAt!.add(_veilleNotificationLeadTime);
          await PushNotificationService()
              .scheduleVeilleNotification(scheduledAt: scheduledAt);
        }
      } catch (e) {
        debugPrint('VeilleConfigNotifier: schedule notif failed: $e');
      }

      _ref
          .read(veilleActiveConfigProvider.notifier)
          .hydrateFromServer(cfg);
      state = state.copyWith(isSubmitting: false);
    } on VeilleApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        lastError: e.message,
      );
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        lastError: e.toString(),
      );
      rethrow;
    }
  }

  void clearError() => state = state.copyWith(lastError: null);

  /// Réinitialise le flow (utilisé après suppression / pour repartir d'une
  /// nouvelle config depuis le dashboard).
  void reset() {
    _loadingTimer?.cancel();
    state = VeilleConfigState.initial();
  }

  Set<String> _toggle(Set<String> set, String id) {
    final next = Set<String>.from(set);
    if (!next.add(id)) next.remove(id);
    return next;
  }

  VeilleConfigUpsertRequest _buildUpsertRequest(VeilleConfigState s) {
    final themeId = s.selectedTheme ?? VeilleMockData.defaultTheme;
    final themeLabel = VeilleMockData.themes
            .firstWhere(
              (t) => t.id == themeId,
              orElse: () => VeilleMockData.themes.first,
            )
            .label;

    final topics = <VeilleTopicSelectionRequest>[];
    var pos = 0;
    for (final slug in s.selectedTopics) {
      topics.add(
        VeilleTopicSelectionRequest(
          topicId: slug,
          label: s.topicLabels[slug] ?? slug,
          kind: 'preset',
          position: pos++,
        ),
      );
    }
    for (final slug in s.selectedSuggestions) {
      topics.add(
        VeilleTopicSelectionRequest(
          topicId: slug,
          label: s.topicLabels[slug] ?? slug,
          kind: 'suggested',
          position: pos++,
        ),
      );
    }

    final sourceSelections = <VeilleSourceSelectionRequest>[];
    var spos = 0;
    for (final slug in s.followedSources) {
      final meta = s.sourcesMeta[slug];
      if (meta?.apiSourceId == null) continue; // mock-only — drop
      sourceSelections.add(
        VeilleSourceSelectionRequest(
          kind: 'followed',
          sourceId: meta!.apiSourceId,
          why: meta.why,
          position: spos++,
        ),
      );
    }
    for (final slug in s.nicheSources) {
      final meta = s.sourcesMeta[slug];
      if (meta?.apiSourceId == null) continue;
      sourceSelections.add(
        VeilleSourceSelectionRequest(
          kind: 'niche',
          sourceId: meta!.apiSourceId,
          why: meta.why,
          position: spos++,
        ),
      );
    }

    return VeilleConfigUpsertRequest(
      themeId: themeId,
      themeLabel: themeLabel,
      topics: topics,
      sourceSelections: sourceSelections,
      frequency: _frequencyToWire(s.frequency),
      dayOfWeek: _dayToWire(s.day, s.frequency),
    );
  }

  static String _frequencyToWire(VeilleFrequency f) => switch (f) {
        VeilleFrequency.weekly => 'weekly',
        VeilleFrequency.biweekly => 'biweekly',
        VeilleFrequency.monthly => 'monthly',
      };

  static int? _dayToWire(VeilleDay d, VeilleFrequency f) {
    if (f == VeilleFrequency.monthly) return null;
    return switch (d) {
      VeilleDay.mon => 0,
      VeilleDay.tue => 1,
      VeilleDay.wed => 2,
      VeilleDay.thu => 3,
      VeilleDay.fri => 4,
      VeilleDay.sat => 5,
      VeilleDay.sun => 6,
    };
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }
}

final veilleConfigProvider =
    StateNotifierProvider.autoDispose<VeilleConfigNotifier, VeilleConfigState>(
  (ref) => VeilleConfigNotifier(ref),
);
