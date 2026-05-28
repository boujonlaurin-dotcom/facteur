import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/veille_config.dart';
import '../models/veille_config_dto.dart';
import '../repositories/veille_repository.dart';
import 'veille_active_config_provider.dart';
import 'veille_repository_provider.dart';
import 'veille_themes_provider.dart';

/// Métadonnées attachées à une source dans le state du flow.
///
/// Permet de distinguer les sources catalogue (UUID API) des sources mock-only ;
/// au submit on filtre les mock-only et on envoie un `source_id` (UUID) ou un
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

/// État du flow de configuration de la veille.
///
/// Flow : intro → step1 (thème + brief) → step1.5 (preset preview, optionnel)
/// → step2 (sujets, skippable) → step3 (sources). PR-4 (Story 23.3) :
/// suggesters LLM dropés — la curation se fait en temps réel côté backend
/// via les keywords + topics + brief.
@immutable
class VeilleConfigState {
  /// Step courant (1..3).
  final int step;

  /// Vrai après que l'utilisateur a passé l'écran d'introduction. Tant que
  /// `false` et qu'il n'y a pas de config active, le host rend
  /// `VeilleIntroScreen` au lieu de Step1.
  final bool introCompleted;

  /// Slug du pré-set en cours de prévisualisation (Step 1.5). Quand non-null,
  /// `veille_config_screen` rend `Step1_5PresetPreviewScreen` au lieu du
  /// step courant.
  final String? previewPresetId;

  final String? selectedTheme;
  final Set<String> selectedTopics;
  final Set<String> selectedSuggestions;

  /// Sources sélectionnées par le user pour cette veille (liste unique).
  /// `sourcesMeta[id].kind` distingue 'followed' / 'niche' pour le wire backend.
  final Set<String> selectedSourceIds;

  /// Topics « custom » saisis par le user (input libre). Matérialisés en
  /// `VeilleTopic` côté front pour l'affichage, puis envoyés au backend avec
  /// `kind='custom'` dans `selectedTopics`.
  final List<VeilleTopic> customTopics;

  /// Mapping slug → label pour topics (mock défauts + override API).
  final Map<String, String> topicLabels;

  /// Mapping slug → metadata pour sources.
  final Map<String, VeilleSourceMeta> sourcesMeta;

  /// Angles libres / mots-clés saisis en mode advanced (step2). Normalisés
  /// lowercase, max 60 chars, dédupliqués. Mappés sur `VeilleKeywordSelection`
  /// backend.
  final Set<String> keywords;

  /// Toggle "Configuration avancée" sur step2/step3. Quand `true`, révèle les
  /// champs free-text (keywords + brief éditorial step2, source URL step3).
  final bool advancedMode;

  /// Vrai si l'utilisateur a tapé "Passer cette étape" sur step2. Persiste
  /// la décision pour la durée du flow (re-back en step2 ne re-déclenche pas
  /// l'écran avec ses champs vides).
  final bool skippedStep2;

  /// V1 personalization. `purpose` = slug court ("apprendre"/"transmettre"/…)
  /// hydraté depuis un preset.
  final String? purpose;
  final String? editorialBrief;
  final String? presetId;

  /// Quand `selectedTheme == 'other'`, label libre saisi par le user
  /// (ex : "Musées contemporains Barcelone"). Envoyé comme `theme_label` au
  /// backend pour l'upsert config.
  final String? customThemeLabel;

  /// Submit en cours — empêche les double-tap.
  final bool isSubmitting;

  /// Dernier message d'erreur API. UI le pop dans un Snackbar puis le clear.
  final String? lastError;

  const VeilleConfigState({
    required this.step,
    required this.introCompleted,
    required this.previewPresetId,
    required this.selectedTheme,
    required this.selectedTopics,
    required this.selectedSuggestions,
    required this.selectedSourceIds,
    required this.customTopics,
    required this.topicLabels,
    required this.sourcesMeta,
    required this.keywords,
    required this.advancedMode,
    required this.skippedStep2,
    required this.purpose,
    required this.editorialBrief,
    required this.presetId,
    required this.isSubmitting,
    required this.lastError,
    required this.customThemeLabel,
  });

  factory VeilleConfigState.initial() => const VeilleConfigState(
        step: 1,
        introCompleted: false,
        previewPresetId: null,
        selectedTheme: null,
        selectedTopics: <String>{},
        selectedSuggestions: <String>{},
        selectedSourceIds: <String>{},
        customTopics: [],
        topicLabels: {},
        sourcesMeta: {},
        keywords: <String>{},
        advancedMode: false,
        skippedStep2: false,
        purpose: null,
        editorialBrief: null,
        presetId: null,
        isSubmitting: false,
        lastError: null,
        customThemeLabel: null,
      );

  /// Nombre de sources réellement persistables (avec `apiSourceId`).
  /// Une source mock sans `apiSourceId` est filtrée par `_buildUpsertRequest`,
  /// donc elle ne compte pas pour autoriser le passage à step suivant.
  int get realSelectedSourceCount =>
      selectedSourceIds.where((id) => sourcesMeta[id]?.apiSourceId != null).length;

  VeilleConfigState copyWith({
    int? step,
    bool? introCompleted,
    Object? previewPresetId = _Sentinel.value,
    Object? selectedTheme = _Sentinel.value,
    Set<String>? selectedTopics,
    Set<String>? selectedSuggestions,
    Set<String>? selectedSourceIds,
    List<VeilleTopic>? customTopics,
    Map<String, String>? topicLabels,
    Map<String, VeilleSourceMeta>? sourcesMeta,
    Set<String>? keywords,
    bool? advancedMode,
    bool? skippedStep2,
    Object? purpose = _Sentinel.value,
    Object? editorialBrief = _Sentinel.value,
    Object? presetId = _Sentinel.value,
    bool? isSubmitting,
    Object? lastError = _Sentinel.value,
    Object? customThemeLabel = _Sentinel.value,
  }) =>
      VeilleConfigState(
        step: step ?? this.step,
        introCompleted: introCompleted ?? this.introCompleted,
        previewPresetId: previewPresetId == _Sentinel.value
            ? this.previewPresetId
            : previewPresetId as String?,
        selectedTheme: selectedTheme == _Sentinel.value
            ? this.selectedTheme
            : selectedTheme as String?,
        selectedTopics: selectedTopics ?? this.selectedTopics,
        selectedSuggestions: selectedSuggestions ?? this.selectedSuggestions,
        selectedSourceIds: selectedSourceIds ?? this.selectedSourceIds,
        customTopics: customTopics ?? this.customTopics,
        topicLabels: topicLabels ?? this.topicLabels,
        sourcesMeta: sourcesMeta ?? this.sourcesMeta,
        keywords: keywords ?? this.keywords,
        advancedMode: advancedMode ?? this.advancedMode,
        skippedStep2: skippedStep2 ?? this.skippedStep2,
        purpose:
            purpose == _Sentinel.value ? this.purpose : purpose as String?,
        editorialBrief: editorialBrief == _Sentinel.value
            ? this.editorialBrief
            : editorialBrief as String?,
        presetId:
            presetId == _Sentinel.value ? this.presetId : presetId as String?,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        lastError:
            lastError == _Sentinel.value ? this.lastError : lastError as String?,
        customThemeLabel: customThemeLabel == _Sentinel.value
            ? this.customThemeLabel
            : customThemeLabel as String?,
      );

  /// `theme_label` final pour le backend — utilise `customThemeLabel` quand
  /// le thème est "other", sinon le label canonique du slug.
  String resolvedThemeLabel(String fallback) {
    if (selectedTheme == kVeilleOtherThemeSlug) {
      final t = (customThemeLabel ?? '').trim();
      return t.isEmpty ? fallback : t;
    }
    return fallback;
  }
}

enum _Sentinel { value }

class VeilleConfigNotifier extends StateNotifier<VeilleConfigState> {
  VeilleConfigNotifier(this._ref) : super(VeilleConfigState.initial());

  final Ref _ref;

  /// Limite backend (`MAX_KEYWORDS_PER_CONFIG` dans `schemas/veille.py`).
  static const int maxKeywords = 20;

  void selectTheme(String id) {
    // Changer de thème reset les topics pré-sélectionnés (les preset topics
    // dépendent du thème). Les customTopics, eux, persistent (le user les
    // a saisis manuellement).
    if (state.selectedTheme == id) return;
    state = state.copyWith(
      selectedTheme: id,
      selectedTopics: const {},
      // Reset customThemeLabel quand on quitte 'other'.
      customThemeLabel: id == kVeilleOtherThemeSlug ? state.customThemeLabel : null,
    );
  }

  /// Label libre quand le user a choisi la tuile "Autre". Trim + cap 120 chars
  /// (aligné avec backend `VeilleConfigUpsert.theme_label`).
  void setCustomThemeLabel(String? raw) {
    final v = (raw ?? '').trim();
    final next = v.isEmpty ? null : (v.length > 120 ? v.substring(0, 120) : v);
    if (next == state.customThemeLabel) return;
    state = state.copyWith(customThemeLabel: next);
  }

  /// Hydrate `topicLabels` pour les preset topics rendus par Step 1 — sans
  /// quoi `_buildUpsertRequest` enverrait juste les slugs comme labels.
  void registerPresetTopicLabels(List<VeilleTopic> presetTopics) {
    if (presetTopics.isEmpty) return;
    final next = Map<String, String>.from(state.topicLabels);
    var changed = false;
    for (final t in presetTopics) {
      if (next[t.id] != t.label) {
        next[t.id] = t.label;
        changed = true;
      }
    }
    if (changed) state = state.copyWith(topicLabels: next);
  }

  /// Ajoute un sujet custom saisi par le user. Le slug est dérivé du
  /// label, préfixé `custom-` pour éviter toute collision avec un
  /// AvailableSubtopic. Idempotent : un même label normalisé n'ajoute
  /// pas de doublon. Le topic est immédiatement sélectionné.
  void addCustomTopic(String rawLabel) {
    final label = rawLabel.trim();
    if (label.isEmpty) return;
    final id = _slugifyCustom(label);
    if (state.customTopics.any((t) => t.id == id)) {
      // Déjà présent → s'assurer juste qu'il est coché.
      if (!state.selectedTopics.contains(id)) {
        state = state.copyWith(
          selectedTopics: {...state.selectedTopics, id},
        );
      }
      return;
    }
    final topic = VeilleTopic(id: id, label: label, reason: 'sujet ajouté');
    final nextLabels = Map<String, String>.from(state.topicLabels)
      ..[id] = label;
    state = state.copyWith(
      customTopics: [...state.customTopics, topic],
      selectedTopics: {...state.selectedTopics, id},
      topicLabels: nextLabels,
    );
  }

  void removeCustomTopic(String id) {
    final next = state.customTopics.where((t) => t.id != id).toList();
    final selection = Set<String>.from(state.selectedTopics)..remove(id);
    state = state.copyWith(customTopics: next, selectedTopics: selection);
  }

  static String _slugifyCustom(String input) {
    final lowered = input.toLowerCase().trim();
    final cleaned = lowered
        .replaceAll(RegExp(r'[àâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[ûüù]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final trimmed = cleaned.replaceAll(RegExp(r'^-|-$'), '');
    final base = trimmed.isEmpty ? 'sujet' : trimmed;
    // Cap à 60 chars pour rester confortable côté backend (max 80).
    final capped = base.length > 60 ? base.substring(0, 60) : base;
    return 'custom-$capped';
  }

  void toggleTopic(String id) =>
      state = state.copyWith(selectedTopics: _toggle(state.selectedTopics, id));

  void toggleSuggestion(String id) => state = state.copyWith(
        selectedSuggestions: _toggle(state.selectedSuggestions, id),
      );

  void toggleSource(String id) => state = state.copyWith(
        selectedSourceIds: _toggle(state.selectedSourceIds, id),
      );

  /// Ajoute un mot-clé / angle libre (step2 advanced). Normalise lowercase,
  /// dédupe, respecte la cap backend (`maxKeywords`).
  void addKeyword(String raw) {
    final kw = raw.trim().toLowerCase();
    if (kw.length < 2 || kw.length > 60) return;
    if (state.keywords.contains(kw)) return;
    if (state.keywords.length >= maxKeywords) return;
    state = state.copyWith(keywords: {...state.keywords, kw});
  }

  void removeKeyword(String kw) {
    if (!state.keywords.contains(kw)) return;
    final next = Set<String>.from(state.keywords)..remove(kw);
    state = state.copyWith(keywords: next);
  }

  /// Toggle "Configuration avancée" sur step2/step3. Quand `false`, on
  /// préserve les valeurs déjà saisies (keywords/brief) — l'utilisateur peut
  /// les ré-afficher sans les perdre.
  void setAdvancedMode(bool value) {
    if (state.advancedMode == value) return;
    state = state.copyWith(advancedMode: value);
  }

  /// L'utilisateur a tapé "Passer cette étape" sur step2 — on clear les
  /// signaux optionnels (keywords + brief restent vides pour ne pas envoyer
  /// une intention involontaire) et on bascule en step3.
  void skipStep2() {
    if (state.step != 2) return;
    state = state.copyWith(
      step: 3,
      skippedStep2: true,
      selectedSuggestions: const {},
      keywords: const {},
      editorialBrief: null,
    );
  }

  /// Quand on choisit un purpose autre que 'autre', on clear toute valeur
  /// orpheline. `purpose_other` a été drop du backend en PR-2 — le slug
  /// "autre" reste autorisé pour la rétrocompat user-side mais ne porte
  /// plus de free-text.
  void setPurpose(String? slug) {
    if (slug == state.purpose) return;
    state = state.copyWith(purpose: slug);
  }

  void setEditorialBrief(String? value) {
    final normalized = _emptyToNull(value);
    if (normalized == state.editorialBrief) return;
    state = state.copyWith(editorialBrief: normalized);
  }

  static String? _emptyToNull(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Avance d'une étape. Cap à 3.
  void goNext() {
    if (state.step >= 3) return;
    state = state.copyWith(step: state.step + 1);
  }

  /// Force un step donné (utilisé après la bifurcation fin Step 1 :
  /// "Passer aux sources" → goToStep(3) avec skippedStep2=true).
  void goToStep(int step, {bool skipStep2 = false}) {
    final clamped = step.clamp(1, 3);
    state = state.copyWith(step: clamped, skippedStep2: skipStep2 || state.skippedStep2);
  }

  /// Recul instantané.
  void goBack() {
    if (state.step <= 1) return;
    state = state.copyWith(step: state.step - 1);
  }

  /// Ajoute une source custom (ajoutée via le sheet "+ Ajouter une source")
  /// au state Step 3. La source est immédiatement sélectionnée pour la veille.
  /// `kind='followed'` : c'est une source explicitement adoptée par le user.
  void addCustomSourceToVeille({
    required String sourceId,
    required String name,
    required String url,
    String? why,
  }) {
    final nextMeta = Map<String, VeilleSourceMeta>.from(state.sourcesMeta);
    nextMeta[sourceId] = VeilleSourceMeta(
      slug: sourceId,
      name: name,
      kind: 'followed',
      apiSourceId: sourceId,
      url: url,
      why: why,
    );
    state = state.copyWith(
      sourcesMeta: nextMeta,
      selectedSourceIds: {...state.selectedSourceIds, sourceId},
    );
  }

  /// L'utilisateur a tapé « C'est parti » sur l'écran d'introduction —
  /// l'intro disparaît, on bascule sur Step1.
  void completeIntro() {
    if (state.introCompleted) return;
    state = state.copyWith(introCompleted: true);
  }

  /// Affiche l'écran preview pré-set (Step 1.5). Le step courant reste à 1
  /// sous le capot — le screen orchestrator détecte `previewPresetId != null`.
  void openPresetPreview(String presetSlug) {
    if (state.previewPresetId == presetSlug) return;
    state = state.copyWith(previewPresetId: presetSlug);
  }

  /// Ferme l'écran preview sans appliquer le pré-set (retour Step 1).
  void closePresetPreview() {
    if (state.previewPresetId == null) return;
    state = state.copyWith(previewPresetId: null);
  }

  /// Hydrate le state depuis un pré-set : thème, topics (matérialisés en
  /// custom topics + cochés), sources curées (followed + apiSourceId), purpose
  /// + brief éditorial. Le user retombe en Step 1 pour ajuster.
  void applyPreset(VeillePreset preset) {
    final topicSlugs = <String>{};
    final newCustomTopics = <VeilleTopic>[];
    final nextLabels = Map<String, String>.from(state.topicLabels);
    for (final label in preset.topics) {
      final slug = _slugifyCustom(label);
      topicSlugs.add(slug);
      nextLabels[slug] = label;
      if (!state.customTopics.any((t) => t.id == slug)) {
        newCustomTopics.add(
          VeilleTopic(id: slug, label: label, reason: 'depuis « ${preset.label} »'),
        );
      }
    }

    final nextMeta = Map<String, VeilleSourceMeta>.from(state.sourcesMeta);
    final followed = <String>{};
    for (final s in preset.sources) {
      nextMeta[s.id] = VeilleSourceMeta(
        slug: s.id,
        name: s.name,
        kind: 'followed',
        apiSourceId: s.id,
        url: s.url,
      );
      followed.add(s.id);
    }

    state = state.copyWith(
      step: 1,
      introCompleted: true,
      previewPresetId: null,
      selectedTheme: preset.themeId,
      selectedTopics: topicSlugs,
      selectedSuggestions: const <String>{},
      customTopics: [...state.customTopics, ...newCustomTopics],
      topicLabels: nextLabels,
      selectedSourceIds: followed,
      sourcesMeta: nextMeta,
      purpose: preset.purposes.isNotEmpty ? preset.purposes.first : null,
      editorialBrief: preset.editorialBrief.isEmpty ? null : preset.editorialBrief,
      presetId: preset.slug,
    );
  }

  void clearError() => state = state.copyWith(lastError: null);

  /// POST /api/veille/config — succès → hydrate `veilleActiveConfigProvider`
  /// pour que la home (Mes intérêts / Tournée) voie la veille immédiatement.
  Future<void> submit() async {
    if (state.isSubmitting) return;
    state = state.copyWith(isSubmitting: true, lastError: null);

    try {
      final body = _buildUpsertRequest(state);
      final repo = _ref.read(veilleRepositoryProvider);
      final cfg = await repo.upsertConfig(body);

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

  /// Hydrate l'état depuis une config existante (mode édition).
  ///
  /// Appelée par `VeilleConfigScreen` quand `editMode == true` et que le
  /// state notifier vient de naître (autoDispose) avec ses valeurs initiales.
  /// Idempotent : si le thème est déjà sélectionné, ne re-hydrate pas.
  void hydrateFromActiveConfig(VeilleConfigDto cfg) {
    if (state.selectedTheme != null) return;

    final selectedTopics = <String>{};
    final selectedSuggestions = <String>{};
    final customTopics = <VeilleTopic>[];
    final topicLabels = <String, String>{};
    for (final t in cfg.topics) {
      topicLabels[t.topicId] = t.label;
      switch (t.kind) {
        case 'custom':
          customTopics.add(
            VeilleTopic(
              id: t.topicId,
              label: t.label,
              reason: t.reason ?? 'sujet ajouté',
            ),
          );
          selectedTopics.add(t.topicId);
        case 'suggested':
          selectedSuggestions.add(t.topicId);
        default:
          selectedTopics.add(t.topicId);
      }
    }

    final selectedSourceIds = <String>{};
    final sourcesMeta = <String, VeilleSourceMeta>{};
    for (final s in cfg.sources) {
      sourcesMeta[s.source.id] = VeilleSourceMeta(
        slug: s.source.id,
        name: s.source.name,
        kind: s.kind,
        apiSourceId: s.source.id,
        url: s.source.url,
        why: s.why,
      );
      selectedSourceIds.add(s.source.id);
    }

    final keywords = cfg.keywords.map((k) => k.keyword).toSet();

    state = state.copyWith(
      step: 1,
      introCompleted: true,
      selectedTheme: cfg.themeId,
      selectedTopics: selectedTopics,
      selectedSuggestions: selectedSuggestions,
      customTopics: customTopics,
      topicLabels: topicLabels,
      selectedSourceIds: selectedSourceIds,
      sourcesMeta: sourcesMeta,
      keywords: keywords,
      advancedMode: keywords.isNotEmpty || (cfg.editorialBrief?.isNotEmpty ?? false),
      purpose: cfg.purpose,
      editorialBrief: cfg.editorialBrief,
      presetId: cfg.presetId,
    );
  }

  /// Réinitialise le flow (utilisé après suppression / pour repartir d'une
  /// nouvelle config).
  void reset() {
    state = VeilleConfigState.initial();
  }

  Set<String> _toggle(Set<String> set, String id) {
    final next = Set<String>.from(set);
    if (!next.add(id)) next.remove(id);
    return next;
  }

  VeilleConfigUpsertRequest _buildUpsertRequest(VeilleConfigState s) {
    // selectedTheme est garanti non-null avant l'appel à submit() (les
    // CTA Step 1→Step 2 sont gardés par `hasTheme`). On garde un fallback
    // défensif sur 'tech' pour ne jamais envoyer un slug vide au backend.
    final themeId = s.selectedTheme ?? 'tech';
    final themeLabel = s.resolvedThemeLabel(veilleThemeLabelForSlug(themeId));

    final topics = <VeilleTopicSelectionRequest>[];
    var pos = 0;
    for (final slug in s.selectedTopics) {
      topics.add(
        VeilleTopicSelectionRequest(
          topicId: slug,
          label: s.topicLabels[slug] ?? slug,
          kind: slug.startsWith('custom-') ? 'custom' : 'preset',
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
    for (final slug in s.selectedSourceIds) {
      final meta = s.sourcesMeta[slug];
      if (meta?.apiSourceId == null) continue; // mock-only — drop
      sourceSelections.add(
        VeilleSourceSelectionRequest(
          kind: meta!.kind, // 'followed' | 'niche'
          sourceId: meta.apiSourceId,
          why: meta.why,
          position: spos++,
        ),
      );
    }

    final keywords = <VeilleKeywordSelectionRequest>[];
    var kpos = 0;
    for (final kw in s.keywords.take(maxKeywords)) {
      keywords.add(
        VeilleKeywordSelectionRequest(keyword: kw, position: kpos++),
      );
    }

    return VeilleConfigUpsertRequest(
      themeId: themeId,
      themeLabel: themeLabel,
      topics: topics,
      sourceSelections: sourceSelections,
      keywords: keywords,
      purpose: s.purpose,
      editorialBrief: s.editorialBrief,
      presetId: s.presetId,
    );
  }
}

final veilleConfigProvider =
    StateNotifierProvider.autoDispose<VeilleConfigNotifier, VeilleConfigState>(
  (ref) => VeilleConfigNotifier(ref),
);
