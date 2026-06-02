import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../onboarding/data/available_subtopics.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../models/veille_config.dart';
import '../models/veille_config_dto.dart';
import '../repositories/veille_repository.dart';
import 'veille_active_config_provider.dart';
import 'veille_repository_provider.dart';
import 'veille_themes_provider.dart';

/// Métadonnées attachées à une source dans le state du flow.
///
/// Permet de distinguer les sources catalogue (UUID API) des candidats niche ;
/// au submit on envoie un `source_id` ou un `niche_candidate{name, url}`.
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

  /// Story 23.4 — sujet principal **obligatoire** (drill macro→granulaire en
  /// Step 1). Slug canonique (`AvailableSubtopics`, ex. `ai`) qui matche
  /// `Content.topics` côté scoring. Émis en position 0 (`kind:'preset'`) à
  /// l'upsert ; devient le gate principal de la curation. Null pour le thème
  /// "Autre" (chemin free-text/mots-clés).
  final String? mainTopicSlug;
  final String? mainTopicLabel;

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

  /// Grappe de mots-clés par angle LLM sélectionné (slug `angle-…` →
  /// liste éditable). Seedée depuis la suggestion LLM à la sélection, puis
  /// éditable (add/remove chip). Injectée dans `VeilleTopicSelection.keywords`
  /// au submit pour les angles `suggested`. Vide = aucun angle activé.
  final Map<String, List<String>> angleKeywords;

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
    required this.mainTopicSlug,
    required this.mainTopicLabel,
    required this.selectedTopics,
    required this.selectedSuggestions,
    required this.selectedSourceIds,
    required this.customTopics,
    required this.topicLabels,
    required this.sourcesMeta,
    required this.keywords,
    required this.angleKeywords,
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
    mainTopicSlug: null,
    mainTopicLabel: null,
    selectedTopics: <String>{},
    selectedSuggestions: <String>{},
    selectedSourceIds: <String>{},
    customTopics: [],
    topicLabels: {},
    sourcesMeta: {},
    keywords: <String>{},
    angleKeywords: {},
    advancedMode: false,
    skippedStep2: false,
    purpose: null,
    editorialBrief: null,
    presetId: null,
    isSubmitting: false,
    lastError: null,
    customThemeLabel: null,
  );

  /// Nombre de sources réellement persistables : source catalogue avec
  /// `apiSourceId`, ou candidat niche avec URL valide.
  int get realSelectedSourceCount => selectedSourceIds.where((id) {
    final meta = sourcesMeta[id];
    if (meta == null) return false;
    return meta.apiSourceId != null || _isValidHttpUrl(meta.url);
  }).length;

  VeilleConfigState copyWith({
    int? step,
    bool? introCompleted,
    Object? previewPresetId = _Sentinel.value,
    Object? selectedTheme = _Sentinel.value,
    Object? mainTopicSlug = _Sentinel.value,
    Object? mainTopicLabel = _Sentinel.value,
    Set<String>? selectedTopics,
    Set<String>? selectedSuggestions,
    Set<String>? selectedSourceIds,
    List<VeilleTopic>? customTopics,
    Map<String, String>? topicLabels,
    Map<String, VeilleSourceMeta>? sourcesMeta,
    Set<String>? keywords,
    Map<String, List<String>>? angleKeywords,
    bool? advancedMode,
    bool? skippedStep2,
    Object? purpose = _Sentinel.value,
    Object? editorialBrief = _Sentinel.value,
    Object? presetId = _Sentinel.value,
    bool? isSubmitting,
    Object? lastError = _Sentinel.value,
    Object? customThemeLabel = _Sentinel.value,
  }) => VeilleConfigState(
    step: step ?? this.step,
    introCompleted: introCompleted ?? this.introCompleted,
    previewPresetId: previewPresetId == _Sentinel.value
        ? this.previewPresetId
        : previewPresetId as String?,
    selectedTheme: selectedTheme == _Sentinel.value
        ? this.selectedTheme
        : selectedTheme as String?,
    mainTopicSlug: mainTopicSlug == _Sentinel.value
        ? this.mainTopicSlug
        : mainTopicSlug as String?,
    mainTopicLabel: mainTopicLabel == _Sentinel.value
        ? this.mainTopicLabel
        : mainTopicLabel as String?,
    selectedTopics: selectedTopics ?? this.selectedTopics,
    selectedSuggestions: selectedSuggestions ?? this.selectedSuggestions,
    selectedSourceIds: selectedSourceIds ?? this.selectedSourceIds,
    customTopics: customTopics ?? this.customTopics,
    topicLabels: topicLabels ?? this.topicLabels,
    sourcesMeta: sourcesMeta ?? this.sourcesMeta,
    keywords: keywords ?? this.keywords,
    angleKeywords: angleKeywords ?? this.angleKeywords,
    advancedMode: advancedMode ?? this.advancedMode,
    skippedStep2: skippedStep2 ?? this.skippedStep2,
    purpose: purpose == _Sentinel.value ? this.purpose : purpose as String?,
    editorialBrief: editorialBrief == _Sentinel.value
        ? this.editorialBrief
        : editorialBrief as String?,
    presetId: presetId == _Sentinel.value ? this.presetId : presetId as String?,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    lastError: lastError == _Sentinel.value
        ? this.lastError
        : lastError as String?,
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

  /// Limite backend par angle (`VeilleTopicSelection.keywords` max_length=10).
  static const int maxAngleKeywords = 10;

  /// Limite backend des angles envoyés au suggester de sources.
  static const int maxSuggestAngles = 20;

  /// Limite backend des mots-clés envoyés au suggester de sources.
  static const int maxSuggestKeywords = 40;

  void selectTheme(String id) {
    // Changer de thème reset les topics pré-sélectionnés (les preset topics
    // dépendent du thème) ET le sujet principal granulaire (Story 23.4 — la
    // grille granulaire dépend du macro). Les customTopics persistent.
    if (state.selectedTheme == id) return;
    state = state.copyWith(
      selectedTheme: id,
      mainTopicSlug: null,
      mainTopicLabel: null,
      selectedTopics: const {},
      // Reset customThemeLabel quand on quitte 'other'.
      customThemeLabel: id == kVeilleOtherThemeSlug
          ? state.customThemeLabel
          : null,
    );
  }

  /// Story 23.4 — sélectionne le sujet principal granulaire (gate obligatoire).
  /// `slug` est canonique (`AvailableSubtopics`, ex. `ai`) → matche
  /// `Content.topics`. Re-tap sur le même sujet le désélectionne.
  void selectMainTopic(String slug, String label) {
    if (state.mainTopicSlug == slug) {
      state = state.copyWith(mainTopicSlug: null, mainTopicLabel: null);
      return;
    }
    final nextLabels = Map<String, String>.from(state.topicLabels)
      ..[slug] = label;
    state = state.copyWith(
      mainTopicSlug: slug,
      mainTopicLabel: label,
      topicLabels: nextLabels,
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
        state = state.copyWith(selectedTopics: {...state.selectedTopics, id});
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

  /// Slug normalisé (sans préfixe) : lowercase, diacritiques → ASCII, capé à
  /// 60 chars (confort backend, max 80). Vide → "sujet".
  static String _slugifyBase(String input) {
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
    return base.length > 60 ? base.substring(0, 60) : base;
  }

  static String _slugifyCustom(String input) => 'custom-${_slugifyBase(input)}';

  /// Mapping inverse granulaire→macro (Story 23.4). Le macro est stocké dans
  /// `VeilleConfig.theme_id`, mais en fallback (configs legacy / theme_id non
  /// canonique) on retrouve le macro qui contient ce sujet granulaire.
  static String? _macroForSubtopic(String slug) {
    for (final entry in AvailableSubtopics.byTheme.entries) {
      if (entry.value.any((o) => o.slug == slug)) return entry.key;
    }
    return null;
  }

  /// Slug d'un angle LLM (préfixe dédié `angle-`) — distinct des sujets custom
  /// (`custom-`) pour ne pas collisionner dans `topicLabels`/`angleKeywords`.
  static String angleSlug(String title) => 'angle-${_slugifyBase(title)}';

  static String sourceSuggestionSlug(String name, String url) {
    final uri = Uri.tryParse(url);
    final host = (uri?.host.isNotEmpty ?? false) ? uri!.host : url;
    return 'niche-${_slugifyBase('$host-$name')}';
  }

  /// Normalise un mot-clé : trim + lowercase, longueur 2..60 sinon `null`.
  static String? _normalizeKeyword(String raw) {
    final kw = raw.trim().toLowerCase();
    if (kw.length < 2 || kw.length > 60) return null;
    return kw;
  }

  /// Normalise/dédupe une grappe d'angle, capée à `maxAngleKeywords`.
  static List<String> _normalizeAngleKeywords(Iterable<String> raw) {
    final out = <String>[];
    for (final r in raw) {
      final kw = _normalizeKeyword(r);
      if (kw == null || out.contains(kw)) continue;
      out.add(kw);
      if (out.length >= maxAngleKeywords) break;
    }
    return out;
  }

  void toggleTopic(String id) =>
      state = state.copyWith(selectedTopics: _toggle(state.selectedTopics, id));

  void toggleSuggestion(String id) => state = state.copyWith(
    selectedSuggestions: _toggle(state.selectedSuggestions, id),
  );

  // ─── Angles LLM (Step 2) ────────────────────────────────────────────────

  /// Active / désactive un angle suggéré par le LLM (sélection opt-in). À
  /// l'activation : l'angle entre dans `selectedSuggestions` (kind `suggested`),
  /// son label est enregistré, et sa grappe est seedée dans `angleKeywords`
  /// (préservée si déjà éditée → re-toggle ne perd pas les edits). À la
  /// désactivation : retiré de `selectedSuggestions` (la grappe éditée reste
  /// mémorisée mais n'est plus envoyée au submit).
  void toggleAngle(VeilleAngleSuggestionDto angle) {
    final slug = angleSlug(angle.title);
    if (state.selectedSuggestions.contains(slug)) {
      final nextSel = Set<String>.from(state.selectedSuggestions)..remove(slug);
      state = state.copyWith(selectedSuggestions: nextSel);
      return;
    }
    final nextLabels = Map<String, String>.from(state.topicLabels)
      ..[slug] = angle.title;
    final nextAngleKw = Map<String, List<String>>.from(state.angleKeywords);
    nextAngleKw.putIfAbsent(
      slug,
      () => _normalizeAngleKeywords(angle.keywords),
    );
    state = state.copyWith(
      selectedSuggestions: {...state.selectedSuggestions, slug},
      topicLabels: nextLabels,
      angleKeywords: nextAngleKw,
    );
  }

  /// Remplace la grappe d'un angle (normalisée + capée).
  void setAngleKeywords(String slug, List<String> keywords) {
    final next = Map<String, List<String>>.from(state.angleKeywords)
      ..[slug] = _normalizeAngleKeywords(keywords);
    state = state.copyWith(angleKeywords: next);
  }

  /// Ajoute un mot-clé à la grappe d'un angle (dédupe, cap `maxAngleKeywords`).
  void addAngleKeyword(String slug, String raw) {
    final kw = _normalizeKeyword(raw);
    if (kw == null) return;
    final current = state.angleKeywords[slug] ?? const <String>[];
    if (current.contains(kw) || current.length >= maxAngleKeywords) return;
    final next = Map<String, List<String>>.from(state.angleKeywords)
      ..[slug] = [...current, kw];
    state = state.copyWith(angleKeywords: next);
  }

  /// Retire un mot-clé de la grappe d'un angle.
  void removeAngleKeyword(String slug, String kw) {
    final current = state.angleKeywords[slug];
    if (current == null || !current.contains(kw)) return;
    final next = Map<String, List<String>>.from(state.angleKeywords)
      ..[slug] = current.where((k) => k != kw).toList();
    state = state.copyWith(angleKeywords: next);
  }

  void toggleSource(String id) => state = state.copyWith(
    selectedSourceIds: _toggle(state.selectedSourceIds, id),
  );

  /// Enregistre les candidats LLM Step 3 sans les sélectionner. Ils restent
  /// locaux au flow et seront ingérés seulement si le user les coche.
  void registerSuggestedSources(List<VeilleSourceSuggestionDto> suggestions) {
    if (suggestions.isEmpty) return;
    final nextMeta = Map<String, VeilleSourceMeta>.from(state.sourcesMeta);
    var changed = false;
    for (final s in suggestions) {
      if (!_isValidHttpUrl(s.url)) continue;
      final slug = sourceSuggestionSlug(s.name, s.url);
      if (nextMeta.containsKey(slug)) continue;
      nextMeta[slug] = VeilleSourceMeta(
        slug: slug,
        name: s.name,
        kind: 'niche',
        url: s.url,
        why: s.why,
      );
      changed = true;
    }
    if (changed) state = state.copyWith(sourcesMeta: nextMeta);
  }

  /// Ajoute un mot-clé / angle libre (step2 advanced). Normalise lowercase,
  /// dédupe, respecte la cap backend (`maxKeywords`).
  void addKeyword(String raw) {
    final kw = _normalizeKeyword(raw);
    if (kw == null) return;
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
      angleKeywords: const {},
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
    state = state.copyWith(
      step: clamped,
      skippedStep2: skipStep2 || state.skippedStep2,
    );
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

  /// Ajoute une URL libre localement à la veille, sans trust global.
  ///
  /// Utilisé par le sheet Step 3 pour les flux niche hors catalogue. Le submit
  /// les sérialise ensuite en `niche_candidate`.
  void addUrlSourceToVeille({
    required String name,
    required String url,
    String? why,
  }) {
    final normalizedUrl = url.trim();
    if (!_isValidHttpUrl(normalizedUrl)) return;
    final trimmedName = name.trim();
    final sourceName = trimmedName.isEmpty
        ? _sourceNameFallback(normalizedUrl)
        : trimmedName;
    final slug = sourceSuggestionSlug(sourceName, normalizedUrl);
    final nextMeta = Map<String, VeilleSourceMeta>.from(state.sourcesMeta);
    nextMeta[slug] = VeilleSourceMeta(
      slug: slug,
      name: sourceName,
      kind: 'niche',
      url: normalizedUrl,
      why: _emptyToNull(why),
    );
    state = state.copyWith(
      sourcesMeta: nextMeta,
      selectedSourceIds: {...state.selectedSourceIds, slug},
    );
  }

  static String _sourceNameFallback(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host;
    if (host != null && host.isNotEmpty) return host;
    return 'Source ajoutée';
  }

  /// Résout un sujet libre saisi via la tuile "Autre" de Step 1. Le sujet
  /// devient le sujet principal de la veille, sans création d'intérêt global.
  Future<void> resolveCustomMainTopic(String rawLabel) async {
    final label = rawLabel.trim();
    if (label.length < 2) return;
    final repo = _ref.read(veilleRepositoryProvider);
    final theme = state.selectedTheme;
    final themeLabel = theme == null
        ? null
        : state.resolvedThemeLabel(veilleThemeLabelForSlug(theme));
    final resolved = await repo.resolveTopic(
      topic: label,
      themeId: theme,
      themeLabel: themeLabel,
    );
    final slug = resolved.topicId.isEmpty
        ? _slugifyCustom(resolved.label)
        : resolved.topicId;
    final topic = VeilleTopic(
      id: slug,
      label: resolved.label,
      reason: resolved.description.isEmpty
          ? 'sujet ajouté'
          : resolved.description,
    );
    final nextLabels = Map<String, String>.from(state.topicLabels)
      ..[slug] = resolved.label;
    final nextAngleKw = Map<String, List<String>>.from(state.angleKeywords);
    final normalizedKeywords = _normalizeAngleKeywords(resolved.keywords);
    if (normalizedKeywords.isNotEmpty) nextAngleKw[slug] = normalizedKeywords;
    final existing = state.customTopics.where((t) => t.id != slug);
    state = state.copyWith(
      mainTopicSlug: slug,
      mainTopicLabel: resolved.label,
      customTopics: [...existing, topic],
      topicLabels: nextLabels,
      angleKeywords: nextAngleKw,
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
          VeilleTopic(
            id: slug,
            label: label,
            reason: 'depuis « ${preset.label} »',
          ),
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
      editorialBrief: preset.editorialBrief.isEmpty
          ? null
          : preset.editorialBrief,
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

      _ref.read(veilleActiveConfigProvider.notifier).hydrateFromServer(cfg);
      // La veille est un favori d'intérêt : sans invalidation, la liste des
      // favoris reste périmée (sans VeilleFavoriteRef) et le CTA « Créer ma
      // veille » reste affiché → clic → redirection feed (bug navigation).
      // Le chemin archivage le fait déjà (my_interests_screen.dart).
      _ref.invalidate(userInterestsProvider);
      state = state.copyWith(isSubmitting: false);
    } on VeilleApiException catch (e) {
      state = state.copyWith(isSubmitting: false, lastError: e.message);
      rethrow;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, lastError: e.toString());
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
    final angleKeywords = <String, List<String>>{};
    // Story 23.4 — le topic position-0 'preset' est le sujet principal :
    // restauré séparément (gate Step 1, grille granulaire), jamais comme
    // topic optionnel (sinon doublon à l'upsert).
    String? mainSlug;
    String? mainLabel;
    for (var i = 0; i < cfg.topics.length; i++) {
      final t = cfg.topics[i];
      topicLabels[t.topicId] = t.label;
      if (t.keywords.isNotEmpty) angleKeywords[t.topicId] = t.keywords;
      if (i == 0 &&
          (t.kind == 'preset' || t.kind == 'custom') &&
          mainSlug == null) {
        mainSlug = t.topicId;
        mainLabel = t.label;
        if (t.kind == 'custom') {
          customTopics.add(
            VeilleTopic(
              id: t.topicId,
              label: t.label,
              reason: t.reason ?? 'sujet ajouté',
            ),
          );
        }
        continue;
      }
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

    // Macro : on privilégie le `theme_id` stocké ; fallback inverse-map si
    // ce n'est pas un macro canonique (legacy).
    final macro = AvailableSubtopics.byTheme.containsKey(cfg.themeId)
        ? cfg.themeId
        : (mainSlug != null ? _macroForSubtopic(mainSlug) : null) ??
              cfg.themeId;

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
      selectedTheme: macro,
      mainTopicSlug: mainSlug,
      mainTopicLabel: mainLabel,
      selectedTopics: selectedTopics,
      selectedSuggestions: selectedSuggestions,
      customTopics: customTopics,
      topicLabels: topicLabels,
      selectedSourceIds: selectedSourceIds,
      sourcesMeta: sourcesMeta,
      keywords: keywords,
      angleKeywords: angleKeywords,
      advancedMode:
          keywords.isNotEmpty || (cfg.editorialBrief?.isNotEmpty ?? false),
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
    // Story 23.4 — le sujet principal granulaire est émis en **position 0**
    // (`kind:'preset'`, slug canonique → matche `Content.topics`, gate
    // principal de la curation). Garantit ≥1 topic à l'upsert.
    final mainSlug = s.mainTopicSlug;
    final hasMain = mainSlug != null && mainSlug.isNotEmpty;
    if (hasMain) {
      topics.add(
        VeilleTopicSelectionRequest(
          topicId: mainSlug,
          label: s.mainTopicLabel ?? s.topicLabels[mainSlug] ?? mainSlug,
          kind: mainSlug.startsWith('custom-') ? 'custom' : 'preset',
          position: pos++,
          keywords: s.angleKeywords[mainSlug] ?? const <String>[],
        ),
      );
    }
    for (final slug in s.selectedTopics) {
      if (hasMain && slug == mainSlug) continue; // déjà émis en position 0
      topics.add(
        VeilleTopicSelectionRequest(
          topicId: slug,
          label: s.topicLabels[slug] ?? slug,
          kind: slug.startsWith('custom-') ? 'custom' : 'preset',
          position: pos++,
          keywords: s.angleKeywords[slug] ?? const <String>[],
        ),
      );
    }
    for (final slug in s.selectedSuggestions) {
      if (hasMain && slug == mainSlug) continue;
      topics.add(
        VeilleTopicSelectionRequest(
          topicId: slug,
          label: s.topicLabels[slug] ?? slug,
          kind: 'suggested',
          position: pos++,
          keywords: s.angleKeywords[slug] ?? const <String>[],
        ),
      );
    }

    final sourceSelections = <VeilleSourceSelectionRequest>[];
    var spos = 0;
    for (final slug in s.selectedSourceIds) {
      final meta = s.sourcesMeta[slug];
      if (meta == null) continue;
      final apiSourceId = meta.apiSourceId;
      if (apiSourceId != null) {
        sourceSelections.add(
          VeilleSourceSelectionRequest(
            kind: meta.kind, // 'followed' | 'niche'
            sourceId: apiSourceId,
            why: meta.why,
            position: spos++,
          ),
        );
        continue;
      }
      if (!_isValidHttpUrl(meta.url)) continue;
      sourceSelections.add(
        VeilleSourceSelectionRequest(
          kind: meta.kind,
          nicheCandidate: VeilleNicheCandidateRequest(
            name: meta.name,
            url: meta.url!,
            why: meta.why,
          ),
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

bool _isValidHttpUrl(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}
