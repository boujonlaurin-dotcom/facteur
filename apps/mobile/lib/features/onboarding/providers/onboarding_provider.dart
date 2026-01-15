import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../onboarding_strings.dart';

/// Modèle pour les réponses de l'onboarding
class OnboardingAnswers {
  final String? objective; // learn, culture, work
  final String? ageRange; // 18-24, 25-34, 35-44, 45+
  final String? gender; // male, female, other, prefer_not_to_say
  final String? approach; // direct, detailed

  // Section 2
  final String? perspective; // big_picture, details
  final String? responseStyle; // decisive, nuanced
  final String? contentRecency; // recent, timeless
  final bool? gamificationEnabled;
  final int? weeklyGoal; // 5, 10, 15

  // Section 3
  final List<String>? themes;
  final List<String>? preferredSources;
  final String? formatPreference; // short, long, audio, video
  final String? personalGoal; // culture, work, conversations, learning

  const OnboardingAnswers({
    this.objective,
    this.ageRange,
    this.gender,
    this.approach,
    this.perspective,
    this.responseStyle,
    this.contentRecency,
    this.gamificationEnabled,
    this.weeklyGoal,
    this.themes,
    this.preferredSources,
    this.formatPreference,
    this.personalGoal,
  });

  OnboardingAnswers copyWith({
    String? objective,
    String? ageRange,
    String? gender,
    String? approach,
    String? perspective,
    String? responseStyle,
    String? contentRecency,
    bool? gamificationEnabled,
    int? weeklyGoal,
    List<String>? themes,
    List<String>? preferredSources,
    String? formatPreference,
    String? personalGoal,
  }) {
    return OnboardingAnswers(
      objective: objective ?? this.objective,
      ageRange: ageRange ?? this.ageRange,
      gender: gender ?? this.gender,
      approach: approach ?? this.approach,
      perspective: perspective ?? this.perspective,
      responseStyle: responseStyle ?? this.responseStyle,
      contentRecency: contentRecency ?? this.contentRecency,
      gamificationEnabled: gamificationEnabled ?? this.gamificationEnabled,
      weeklyGoal: weeklyGoal ?? this.weeklyGoal,
      themes: themes ?? this.themes,
      preferredSources: preferredSources ?? this.preferredSources,
      formatPreference: formatPreference ?? this.formatPreference,
      personalGoal: personalGoal ?? this.personalGoal,
    );
  }

  Map<String, dynamic> toJson() => {
        'objective': objective,
        'age_range': ageRange,
        'gender': gender,
        'approach': approach,
        'perspective': perspective,
        'response_style': responseStyle,
        'content_recency': contentRecency,
        'gamification_enabled': gamificationEnabled,
        'weekly_goal': weeklyGoal,
        'themes': themes,
        'preferred_sources': preferredSources,
        'format_preference': formatPreference,
        'personal_goal': personalGoal,
      };

  factory OnboardingAnswers.fromJson(Map<String, dynamic> json) {
    return OnboardingAnswers(
      objective: json['objective'] as String?,
      ageRange: json['age_range'] as String?,
      gender: json['gender'] as String?,
      approach: json['approach'] as String?,
      perspective: json['perspective'] as String?,
      responseStyle: json['response_style'] as String?,
      contentRecency: json['content_recency'] as String?,
      gamificationEnabled: json['gamification_enabled'] as bool?,
      weeklyGoal: json['weekly_goal'] as int?,
      themes: (json['themes'] as List<dynamic>?)?.cast<String>(),
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

/// Questions de la Section 1 (Overview)
enum Section1Question {
  intro1, // Intro: L'info est aujourd'hui un champ de bataille
  intro2, // Intro: Facteur vise à être un outil de résistance
  objective, // Q1: Diagnostic
  objectiveReaction, // R1: Réaction personnalisée
  ageRange, // Q2: Tranche d'âge
  approach, // Q3: Tu préfères...
}

/// Questions de la Section 2 (App Preferences)
enum Section2Question {
  perspective, // Q5: Big-picture vs details
  responseStyle, // Q6: Tranchées vs nuancées
  contentRecency, // Q7: Récent vs intemporel
  preferencesReaction, // R2: Réaction personnalisée
  gamification, // Q8: Activer la gamification ?
  weeklyGoal, // Q8b: Objectif hebdo (conditionnel)
}

/// Questions de la Section 3 (Source Preferences)
enum Section3Question {
  sources, // Q9: Vos sources préférées
  themes, // Q10: Vos thèmes préférés
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
  static const int section1QuestionCount = 6;

  /// Nombre total de questions dans la Section 2 (sans Q8b conditionnel)
  static const int section2QuestionCount =
      5; // 4 questions + 1 réaction (Q8b est en plus)

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
  static const int totalSteps = 15; // 6 + 6 + 3

  /// Progression globale (0.0 à 1.0)
  double get progress => (globalQuestionIndex + 1) / totalSteps;

  /// Progression dans la section courante (0.0 à 1.0)
  double get sectionProgress {
    switch (currentSection) {
      case OnboardingSection.overview:
        return (currentQuestionIndex + 1) / section1QuestionCount;
      case OnboardingSection.appPreferences:
        // Max 6 questions si gamification activée
        final maxQuestions = answers.gamificationEnabled == true ? 6 : 5;
        return (currentQuestionIndex + 1) / maxQuestions;
      case OnboardingSection.sourcePreferences:
        return (currentQuestionIndex + 1) / 3;
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

  /// Charge les réponses sauvegardées en cas de reprise
  Future<void> _loadSavedAnswers() async {
    try {
      final box = await Hive.openBox(_hiveBoxName);
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

  /// Continue après l'intro 2 (vers Q1 - Diagnostic)
  void continueAfterIntro() {
    state = state.copyWith(
      currentQuestionIndex: Section1Question.objective.index,
      isTransitioning: false,
    );
  }

  /// Sélectionne un objectif (Q1 - Diagnostic)
  void selectObjective(String objective) {
    state = state.copyWith(
      answers: state.answers.copyWith(objective: objective),
      isTransitioning: true,
    );
    _saveAnswers();

    // Après un délai, montrer la réaction
    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section1Question.objectiveReaction.index,
        isTransitioning: false,
        showReaction: true,
      );
    });
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
            currentQuestionIndex: Section2Question.contentRecency.index,
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
        final lastSection2Index = state.answers.gamificationEnabled == true
            ? Section2Question.weeklyGoal.index
            : Section2Question.gamification.index;
        state = state.copyWith(
          currentSection: OnboardingSection.appPreferences,
          currentQuestionIndex: lastSection2Index,
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

  /// Sélectionne le style de réponse (Q6)
  void selectResponseStyle(String responseStyle) {
    state = state.copyWith(
      answers: state.answers.copyWith(responseStyle: responseStyle),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section2Question.contentRecency.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne la récence du contenu (Q7)
  void selectContentRecency(String contentRecency) {
    state = state.copyWith(
      answers: state.answers.copyWith(contentRecency: contentRecency),
      isTransitioning: true,
    );
    _saveAnswers();

    // Après Q7, montrer la réaction
    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section2Question.preferencesReaction.index,
        isTransitioning: false,
        showReaction: true,
      );
    });
  }

  /// Continue après la réaction Section 2 (après R2)
  void continueAfterSection2Reaction() {
    state = state.copyWith(
      currentQuestionIndex: Section2Question.gamification.index,
      showReaction: false,
      isTransitioning: false,
    );
  }

  /// Sélectionne l'activation de la gamification (Q8)
  void selectGamification(bool enabled) {
    state = state.copyWith(
      answers: state.answers.copyWith(gamificationEnabled: enabled),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (enabled) {
        // Si gamification activée, aller à Q8b
        state = state.copyWith(
          currentQuestionIndex: Section2Question.weeklyGoal.index,
          isTransitioning: false,
        );
      } else {
        // Sinon, transition vers Section 3
        _transitionToSection3();
      }
    });
  }

  /// Sélectionne l'objectif hebdomadaire (Q8b)
  void selectWeeklyGoal(int goal) {
    state = state.copyWith(
      answers: state.answers.copyWith(weeklyGoal: goal),
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

  /// Sélectionne les sources (Q9) - multi-sélection
  void selectSources(List<String> sources) {
    state = state.copyWith(
      answers: state.answers.copyWith(preferredSources: sources),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section3Question.themes.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne les thèmes (Q10) - multi-sélection
  void selectThemes(List<String> themes) {
    state = state.copyWith(
      answers: state.answers.copyWith(themes: themes),
      isTransitioning: true,
    );
    _saveAnswers();

    // Go directly to finalize
    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section3Question.finalize.index,
        isTransitioning: false,
      );
    });
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
        objective: 'learn',
        ageRange: '25-34',
        gender: 'male',
        approach: 'direct',
        perspective: 'big_picture',
        responseStyle: 'decisive',
        contentRecency: 'recent',
        gamificationEnabled: true,
        weeklyGoal: 10,
        themes: ['tech', 'business'],
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
  return answers.objective != null &&
      answers.ageRange != null &&
      answers.approach != null;
});

/// Provider pour vérifier si Section 2 est complète
final isSection2CompleteProvider = Provider<bool>((ref) {
  final state = ref.watch(onboardingProvider);
  final answers = state.answers;
  final baseComplete = answers.perspective != null &&
      answers.responseStyle != null &&
      answers.contentRecency != null &&
      answers.gamificationEnabled != null;

  // Si gamification activée, weeklyGoal doit aussi être défini
  if (answers.gamificationEnabled == true) {
    return baseComplete && answers.weeklyGoal != null;
  }
  return baseComplete;
});

/// Provider pour vérifier si Section 3 est complète
final isSection3CompleteProvider = Provider<bool>((ref) {
  final state = ref.watch(onboardingProvider);
  final answers = state.answers;
  return answers.themes != null &&
      answers.themes!.isNotEmpty &&
      answers.formatPreference != null;
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
    ThemeOption(
      slug: 'tech',
      label: OnboardingStrings.themeTech,
      icon: PhosphorIcons.cpu(PhosphorIconsStyle.bold),
      color: Colors.blue,
    ),
    ThemeOption(
      slug: 'business',
      label: OnboardingStrings.themeBusiness,
      icon: PhosphorIcons.briefcase(PhosphorIconsStyle.bold),
      color: Colors.blueGrey,
    ),
    ThemeOption(
      slug: 'science',
      label: OnboardingStrings.themeScience,
      icon: PhosphorIcons.atom(PhosphorIconsStyle.bold),
      color: Colors.purple,
    ),
    ThemeOption(
      slug: 'culture',
      label: OnboardingStrings.themeCulture,
      icon: PhosphorIcons.palette(PhosphorIconsStyle.bold),
      color: Colors.pink,
    ),
    ThemeOption(
      slug: 'politics',
      label: OnboardingStrings.themePolitics,
      icon: PhosphorIcons.bank(PhosphorIconsStyle.bold),
      color: Colors.brown,
    ),
    ThemeOption(
      slug: 'society',
      label: OnboardingStrings.themeSociety,
      icon: PhosphorIcons.users(PhosphorIconsStyle.bold),
      color: Colors.teal,
    ),
    ThemeOption(
      slug: 'environment',
      label: OnboardingStrings.themeEnvironment,
      icon: PhosphorIcons.leaf(PhosphorIconsStyle.bold),
      color: Colors.green,
    ),
    ThemeOption(
      slug: 'economy',
      label: OnboardingStrings.themeEconomy,
      icon: PhosphorIcons.trendUp(PhosphorIconsStyle.bold),
      color: Colors.indigo,
    ),
  ];
}

class ThemeOption {
  final String slug;
  final String label;
  final IconData icon;
  final Color color;

  const ThemeOption({
    required this.slug,
    required this.label,
    required this.icon,
    required this.color,
  });
}
