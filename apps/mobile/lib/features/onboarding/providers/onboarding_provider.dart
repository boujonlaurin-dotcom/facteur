import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../onboarding_strings.dart';

/// Modèle pour les réponses de l'onboarding
class OnboardingAnswers {
  final List<String>? objectives; // multi-select: noise, bias, anxiety
  final String? ageRange; // 18-24, 25-34, 35-44, 45+
  final String? gender; // male, female, other, prefer_not_to_say
  final String? approach; // direct, detailed

  // Section 2
  final String? perspective; // big_picture, details
  final String? responseStyle; // decisive, nuanced
  final String? contentRecency; // kept nullable for backward compat (deprecated)
  final bool? gamificationEnabled;
  final int? dailyArticleCount; // 3, 5, 7
  final String? digestMode; // pour_vous, serein, perspective

  // Section 3
  final List<String>? themes;
  final List<String>? subtopics;
  final List<String>? preferredSources;
  final String? formatPreference; // short, long, audio, video
  final String? personalGoal; // culture, work, conversations, learning

  const OnboardingAnswers({
    this.objectives,
    this.ageRange,
    this.gender,
    this.approach,
    this.perspective,
    this.responseStyle,
    this.contentRecency,
    this.gamificationEnabled,
    this.dailyArticleCount,
    this.digestMode,
    this.themes,
    this.subtopics,
    this.preferredSources,
    this.formatPreference,
    this.personalGoal,
  });

  OnboardingAnswers copyWith({
    List<String>? objectives,
    String? ageRange,
    String? gender,
    String? approach,
    String? perspective,
    String? responseStyle,
    String? contentRecency,
    bool? gamificationEnabled,
    int? dailyArticleCount,
    String? digestMode,
    List<String>? themes,
    List<String>? subtopics,
    List<String>? preferredSources,
    String? formatPreference,
    String? personalGoal,
  }) {
    return OnboardingAnswers(
      objectives: objectives ?? this.objectives,
      ageRange: ageRange ?? this.ageRange,
      gender: gender ?? this.gender,
      approach: approach ?? this.approach,
      perspective: perspective ?? this.perspective,
      responseStyle: responseStyle ?? this.responseStyle,
      contentRecency: contentRecency ?? this.contentRecency,
      gamificationEnabled: gamificationEnabled ?? this.gamificationEnabled,
      dailyArticleCount: dailyArticleCount ?? this.dailyArticleCount,
      digestMode: digestMode ?? this.digestMode,
      themes: themes ?? this.themes,
      subtopics: subtopics ?? this.subtopics,
      preferredSources: preferredSources ?? this.preferredSources,
      formatPreference: formatPreference ?? this.formatPreference,
      personalGoal: personalGoal ?? this.personalGoal,
    );
  }

  Map<String, dynamic> toJson() => {
        'objective': objectives?.join(','),
        'age_range': ageRange,
        'gender': gender,
        'approach': approach,
        'perspective': perspective,
        'response_style': responseStyle,
        'content_recency': contentRecency,
        'gamification_enabled': gamificationEnabled,
        'weekly_goal': dailyArticleCount,
        'digest_mode': digestMode,
        'themes': themes,
        'subtopics': subtopics,
        'preferred_sources': preferredSources,
        'format_preference': formatPreference,
        'personal_goal': personalGoal,
      };

  factory OnboardingAnswers.fromJson(Map<String, dynamic> json) {
    // Parse objective: could be comma-separated string (new) or single string (old)
    List<String>? objectives;
    final rawObjective = json['objective'];
    if (rawObjective is String && rawObjective.isNotEmpty) {
      objectives = rawObjective.split(',');
    }

    return OnboardingAnswers(
      objectives: objectives,
      ageRange: json['age_range'] as String?,
      gender: json['gender'] as String?,
      approach: json['approach'] as String?,
      perspective: json['perspective'] as String?,
      responseStyle: json['response_style'] as String?,
      contentRecency: json['content_recency'] as String?,
      gamificationEnabled: json['gamification_enabled'] as bool?,
      dailyArticleCount: json['weekly_goal'] as int?,
      digestMode: json['digest_mode'] as String?,
      themes: (json['themes'] as List<dynamic>?)?.cast<String>(),
      subtopics: (json['subtopics'] as List<dynamic>?)?.cast<String>(),
      preferredSources:
          (json['preferred_sources'] as List<dynamic>?)?.cast<String>(),
      formatPreference: json['format_preference'] as String?,
      personalGoal: json['personal_goal'] as String?,
    );
  }
}

/// Sections de l'onboarding
enum OnboardingSection {
  overview(1, OnboardingStrings.section1Label),
  appPreferences(2, OnboardingStrings.section2Label),
  sourcePreferences(3, OnboardingStrings.section3Label);

  final int number;
  final String label;

  const OnboardingSection(this.number, this.label);
}

/// Questions de la Section 1 (Overview) — 7 étapes
enum Section1Question {
  intro1, // Intro: Welcome
  intro2, // Intro: Mission
  mediaConcentration, // NEW: Carte concentration médias
  objective, // Q1: Multi-select diagnostic
  objectiveReaction, // R1: Réaction personnalisée
  ageRange, // Q2: Tranche d'âge
  approach, // Q3: Tu préfères...
}

/// Questions de la Section 2 (App Preferences) — 5 étapes
enum Section2Question {
  perspective, // Q5: Big-picture vs details
  responseStyle, // Q6: Tranchées vs nuancées
  gamification, // Q8: Activer la gamification ?
  articleCount, // NEW: 3/5/7 articles par jour
  digestMode, // NEW: Pour vous / Serein / Ouvrir son point de vue
}

/// Questions de la Section 3 (Source Preferences)
/// Ordre : Thèmes → Sources → Réaction sources → Finalize
enum Section3Question {
  themes, // Q9: Vos thèmes préférés (premier)
  sources, // Q10: Vos sources préférées (avec pré-sélection basée sur thèmes)
  sourcesReaction, // Réaction: vous pourrez ajouter vos propres sources
  finalize, // Écran de finalisation
}

/// État global de l'onboarding
class OnboardingState {
  final OnboardingSection currentSection;
  final int currentQuestionIndex;
  final OnboardingAnswers answers;
  final bool isTransitioning;
  final bool showReaction;

  const OnboardingState({
    this.currentSection = OnboardingSection.overview,
    this.currentQuestionIndex = 0,
    this.answers = const OnboardingAnswers(),
    this.isTransitioning = false,
    this.showReaction = false,
  });

  /// Nombre total de questions dans la Section 1
  static const int section1QuestionCount = 7;

  /// Nombre total de questions dans la Section 2
  static const int section2QuestionCount = 5;

  /// Index de la question actuelle dans toutes les sections
  int get globalQuestionIndex {
    switch (currentSection) {
      case OnboardingSection.overview:
        return currentQuestionIndex;
      case OnboardingSection.appPreferences:
        return section1QuestionCount + currentQuestionIndex;
      case OnboardingSection.sourcePreferences:
        return section1QuestionCount +
            section2QuestionCount +
            currentQuestionIndex;
    }
  }

  /// Nombre total d'étapes estimées pour l'onboarding
  static const int totalSteps = 16; // 7 + 5 + 4

  /// Progression globale (0.0 à 1.0)
  double get progress => (globalQuestionIndex + 1) / totalSteps;

  /// Progression dans la section courante (0.0 à 1.0)
  double get sectionProgress {
    switch (currentSection) {
      case OnboardingSection.overview:
        return (currentQuestionIndex + 1) / section1QuestionCount;
      case OnboardingSection.appPreferences:
        return (currentQuestionIndex + 1) / section2QuestionCount;
      case OnboardingSection.sourcePreferences:
        return (currentQuestionIndex + 1) / 4;
    }
  }

  Section1Question get currentSection1Question =>
      Section1Question.values[currentQuestionIndex];

  Section2Question get currentSection2Question =>
      Section2Question.values[currentQuestionIndex];

  Section3Question get currentSection3Question =>
      Section3Question.values[currentQuestionIndex];

  /// Indique si l'onboarding est terminé (prêt pour animation finale)
  bool get isReadyToFinalize =>
      currentSection == OnboardingSection.sourcePreferences &&
      currentSection3Question == Section3Question.finalize;

  OnboardingState copyWith({
    OnboardingSection? currentSection,
    int? currentQuestionIndex,
    OnboardingAnswers? answers,
    bool? isTransitioning,
    bool? showReaction,
  }) {
    return OnboardingState(
      currentSection: currentSection ?? this.currentSection,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      answers: answers ?? this.answers,
      isTransitioning: isTransitioning ?? this.isTransitioning,
      showReaction: showReaction ?? this.showReaction,
    );
  }
}

/// Notifier pour gérer l'état de l'onboarding
class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier() : super(const OnboardingState()) {
    _loadSavedAnswers();
  }

  static const String _hiveBoxName = 'onboarding';
  static const String _answersKey = 'answers';
  static const String _sectionKey = 'section';
  static const String _questionKey = 'question';
  static const String _versionKey = 'onboarding_version';
  static const int _currentVersion = 2;

  /// Charge les réponses sauvegardées en cas de reprise
  Future<void> _loadSavedAnswers() async {
    try {
      final box = await Hive.openBox(_hiveBoxName);
      final savedVersion = box.get(_versionKey) as int?;

      // Version mismatch: restart onboarding to avoid enum index crash
      if (savedVersion != null && savedVersion != _currentVersion) {
        await box.clear();
        return;
      }

      final savedAnswers = box.get(_answersKey);
      final savedSection = box.get(_sectionKey);
      final savedQuestion = box.get(_questionKey);

      if (savedAnswers != null) {
        final answers = OnboardingAnswers.fromJson(
          Map<String, dynamic>.from(savedAnswers as Map),
        );
        state = state.copyWith(
          answers: answers,
          currentSection: savedSection != null && savedSection is int
              ? OnboardingSection.values[savedSection]
              : OnboardingSection.overview,
          currentQuestionIndex: savedQuestion is int ? savedQuestion : 0,
        );
      }
    } catch (e) {
      // Ignorer les erreurs de chargement
    }
  }

  /// Reset l'onboarding pour le recommencer (garde les réponses actuelles comme base)
  void restartOnboarding() {
    state = state.copyWith(
      currentSection: OnboardingSection.overview,
      currentQuestionIndex: 0,
      showReaction: false,
      isTransitioning: false,
    );
    _saveAnswers();
  }

  /// Sauvegarde les réponses localement
  Future<void> _saveAnswers() async {
    try {
      final box = await Hive.openBox(_hiveBoxName);
      await box.put(_answersKey, state.answers.toJson());
      await box.put(_sectionKey, state.currentSection.index);
      await box.put(_questionKey, state.currentQuestionIndex);
      await box.put(_versionKey, _currentVersion);
    } catch (e) {
      // Ignorer les erreurs de sauvegarde
    }
  }

  /// Efface les données sauvegardées
  Future<void> clearSavedData() async {
    try {
      final box = await Hive.openBox(_hiveBoxName);
      await box.clear();
    } catch (e) {
      // Ignorer
    }
  }

  /// Continue de l'intro 1 vers l'intro 2
  void continueToIntro2() {
    state = state.copyWith(
      currentQuestionIndex: Section1Question.intro2.index,
      isTransitioning: false,
    );
  }

  /// Continue après l'intro 2 (vers MediaConcentration)
  void continueAfterIntro() {
    state = state.copyWith(
      currentQuestionIndex: Section1Question.mediaConcentration.index,
      isTransitioning: false,
    );
  }

  /// Continue après MediaConcentration (vers Q1 - Objective)
  void continueAfterMediaConcentration() {
    state = state.copyWith(
      currentQuestionIndex: Section1Question.objective.index,
      isTransitioning: false,
    );
  }

  /// Sélectionne les objectifs (Q1 - Diagnostic multi-select)
  /// Does NOT auto-advance; user must tap Continue button
  void selectObjectives(List<String> objectives) {
    state = state.copyWith(
      answers: state.answers.copyWith(objectives: objectives),
    );
    _saveAnswers();
  }

  /// Continue après sélection des objectifs → objectiveReaction
  void continueAfterObjectives() {
    state = state.copyWith(
      currentQuestionIndex: Section1Question.objectiveReaction.index,
      isTransitioning: false,
      showReaction: true,
    );
  }

  /// Continue après la réaction (après R1)
  void continueAfterReaction() {
    state = state.copyWith(
      currentQuestionIndex: Section1Question.ageRange.index,
      showReaction: false,
      isTransitioning: false,
    );
  }

  /// Sélectionne la tranche d'âge (Q2)
  void selectAgeRange(String ageRange) {
    state = state.copyWith(
      answers: state.answers.copyWith(ageRange: ageRange),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section1Question.approach.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne l'approche (Q3) - dernière question Section 1
  void selectApproach(String approach) {
    state = state.copyWith(
      answers: state.answers.copyWith(approach: approach),
      isTransitioning: true,
    );
    _saveAnswers();

    // Transition vers Section 2
    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentSection: OnboardingSection.appPreferences,
        currentQuestionIndex: 0,
        isTransitioning: false,
      );
    });
  }

  /// Revient à la question précédente
  void goBack() {
    if (state.currentQuestionIndex > 0) {
      if (state.showReaction) {
        if (state.currentSection == OnboardingSection.overview) {
          state = state.copyWith(
            currentQuestionIndex: Section1Question.objective.index,
            showReaction: false,
          );
        } else {
          state = state.copyWith(
            currentQuestionIndex: state.currentQuestionIndex - 1,
            showReaction: false,
          );
        }
      } else {
        state = state.copyWith(
          currentQuestionIndex: state.currentQuestionIndex - 1,
        );
      }
    } else {
      // Revenir à la section précédente
      if (state.currentSection == OnboardingSection.sourcePreferences) {
        state = state.copyWith(
          currentSection: OnboardingSection.appPreferences,
          currentQuestionIndex: Section2Question.digestMode.index,
        );
      } else if (state.currentSection == OnboardingSection.appPreferences) {
        state = state.copyWith(
          currentSection: OnboardingSection.overview,
          currentQuestionIndex: Section1Question.approach.index,
        );
      }
    }
  }

  /// Vérifie si on peut revenir en arrière
  bool get canGoBack {
    if (state.currentSection == OnboardingSection.overview &&
        state.currentQuestionIndex == 0) {
      return false;
    }
    return true;
  }

  // ============================================================
  // SECTION 2 : App Preferences
  // ============================================================

  /// Sélectionne la perspective (Q5)
  void selectPerspective(String perspective) {
    state = state.copyWith(
      answers: state.answers.copyWith(perspective: perspective),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section2Question.responseStyle.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne le style de réponse (Q6) → gamification
  void selectResponseStyle(String responseStyle) {
    state = state.copyWith(
      answers: state.answers.copyWith(responseStyle: responseStyle),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section2Question.gamification.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne l'activation de la gamification (Q8)
  /// Always goes to articleCount next (no conditional branch)
  void selectGamification(bool enabled) {
    state = state.copyWith(
      answers: state.answers.copyWith(gamificationEnabled: enabled),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section2Question.articleCount.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne le nombre d'articles par jour (3/5/7)
  void selectDailyArticleCount(int count) {
    state = state.copyWith(
      answers: state.answers.copyWith(dailyArticleCount: count),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section2Question.digestMode.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne le mode digest
  void selectDigestMode(String mode) {
    state = state.copyWith(
      answers: state.answers.copyWith(digestMode: mode),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      _transitionToSection3();
    });
  }

  /// Transition vers Section 3
  void _transitionToSection3() {
    state = state.copyWith(
      currentSection: OnboardingSection.sourcePreferences,
      currentQuestionIndex: 0,
      isTransitioning: false,
    );
  }

  // ============================================================
  // SECTION 3 : Source Preferences
  // ============================================================

  /// Sélectionne les thèmes (Q9) - multi-sélection
  /// Nouvel ordre: Thèmes → Sources → Finalize
  void selectThemes(List<String> themes) {
    state = state.copyWith(
      answers: state.answers.copyWith(themes: themes),
      isTransitioning: true,
    );
    _saveAnswers();

    // Aller vers Sources (Q10) avec pré-sélection
    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section3Question.sources.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne les thèmes et sous-thèmes (Q9)
  /// Nouvel ordre: Thèmes → Sources → Finalize
  void selectThemesAndSubtopics(List<String> themes, List<String> subtopics) {
    state = state.copyWith(
      answers: state.answers.copyWith(
        themes: themes,
        subtopics: subtopics,
      ),
      isTransitioning: true,
    );
    _saveAnswers();

    // Aller vers Sources (Q10) avec pré-sélection
    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section3Question.sources.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne les sources (Q10) - multi-sélection
  /// Nouvel ordre: Thèmes → Sources → Sources Reaction → Finalize
  void selectSources(List<String> sources) {
    state = state.copyWith(
      answers: state.answers.copyWith(preferredSources: sources),
      isTransitioning: true,
    );
    _saveAnswers();

    // Aller vers Sources Reaction
    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section3Question.sourcesReaction.index,
        isTransitioning: false,
      );
    });
  }

  /// Continue après la réaction sources → Finalize
  void continueAfterSourcesReaction() {
    state = state.copyWith(
      currentQuestionIndex: Section3Question.finalize.index,
      isTransitioning: false,
    );
  }

  /// Finalise l'onboarding - appelé depuis l'écran de finalisation
  void finalizeOnboarding() {
    // Cette méthode est appelée avant la transition vers l'animation finale
    // Les données seront envoyées à l'API dans l'écran d'animation
    _saveAnswers();
  }

  /// BYPASS TEMPORAIRE POUR TEST (A supprimer plus tard)
  void bypassOnboarding() {
    state = state.copyWith(
      answers: const OnboardingAnswers(
        objectives: ['noise'],
        ageRange: '25-34',
        gender: 'male',
        approach: 'direct',
        perspective: 'big_picture',
        responseStyle: 'decisive',
        gamificationEnabled: true,
        dailyArticleCount: 5,
        digestMode: 'pour_vous',
        themes: ['tech', 'international'],
        formatPreference: 'short',
        personalGoal: 'learning',
      ),
      currentSection: OnboardingSection.sourcePreferences,
      currentQuestionIndex: Section3Question.finalize.index,
      showReaction: false,
    );
    _saveAnswers();
  }
}

/// Provider de l'état d'onboarding
final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>((ref) {
  return OnboardingNotifier();
});

/// Provider pour vérifier si Section 1 est complète
final isSection1CompleteProvider = Provider<bool>((ref) {
  final state = ref.watch(onboardingProvider);
  final answers = state.answers;
  return answers.objectives != null &&
      answers.objectives!.isNotEmpty &&
      answers.ageRange != null &&
      answers.approach != null;
});

/// Provider pour vérifier si Section 2 est complète
final isSection2CompleteProvider = Provider<bool>((ref) {
  final state = ref.watch(onboardingProvider);
  final answers = state.answers;
  return answers.perspective != null &&
      answers.responseStyle != null &&
      answers.gamificationEnabled != null &&
      answers.dailyArticleCount != null &&
      answers.digestMode != null;
});

/// Provider pour vérifier si Section 3 est complète
final isSection3CompleteProvider = Provider<bool>((ref) {
  final state = ref.watch(onboardingProvider);
  final answers = state.answers;
  return answers.themes != null &&
      answers.themes!.isNotEmpty;
});

/// Provider pour vérifier si l'onboarding est complet
final isOnboardingCompleteProvider = Provider<bool>((ref) {
  final section1 = ref.watch(isSection1CompleteProvider);
  final section2 = ref.watch(isSection2CompleteProvider);
  final section3 = ref.watch(isSection3CompleteProvider);
  return section1 && section2 && section3;
});

/// Liste des thèmes disponibles
class AvailableThemes {
  static final List<ThemeOption> all = [
    const ThemeOption(
      slug: 'tech',
      label: OnboardingStrings.themeTech,
      emoji: '💻',
      color: Colors.blue,
    ),
    const ThemeOption(
      slug: 'international',
      label: OnboardingStrings.themeInternational,
      emoji: '🌍',
      color: Colors.cyan,
    ),
    const ThemeOption(
      slug: 'science',
      label: OnboardingStrings.themeScience,
      emoji: '🔬',
      color: Colors.purple,
    ),
    const ThemeOption(
      slug: 'culture',
      label: OnboardingStrings.themeCulture,
      emoji: '🎨',
      color: Colors.pink,
    ),
    const ThemeOption(
      slug: 'politics',
      label: OnboardingStrings.themePolitics,
      emoji: '🏛️',
      color: Colors.brown,
    ),
    const ThemeOption(
      slug: 'society',
      label: OnboardingStrings.themeSociety,
      emoji: '👥',
      color: Colors.teal,
    ),
    const ThemeOption(
      slug: 'environment',
      label: OnboardingStrings.themeEnvironment,
      emoji: '🌿',
      color: Colors.green,
    ),
    const ThemeOption(
      slug: 'economy',
      label: OnboardingStrings.themeEconomy,
      emoji: '📈',
      color: Colors.indigo,
    ),
    const ThemeOption(
      slug: 'sport',
      label: OnboardingStrings.themeSport,
      emoji: '⚽',
      color: Colors.orange,
    ),
  ];
}

class ThemeOption {
  final String slug;
  final String label;
  final String emoji;
  final Color color;
  const ThemeOption({
    required this.slug,
    required this.label,
    required this.emoji,
    required this.color,
  });
}
