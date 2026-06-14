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
  final String? responseStyle; // decisive, nuanced (deprecated v6 — plus demandé)
  final String? independencePref; // established, independent (axe v6)
  final String? contentRecency; // kept nullable for backward compat (deprecated)
  final bool? gamificationEnabled;
  final int? dailyArticleCount; // 3, 5, 7
  final String? digestMode; // pour_vous, serein, perspective

  // Section 3
  final List<String>? themes;
  final List<String>? subtopics;
  final String? sourcesIntent; // curious, knows (local uniquement, hors API)
  final List<String>? preferredSources;
  final String? formatPreference; // short, long, audio, video
  final String? personalGoal; // culture, work, conversations, learning

  // Swipe désambiguateur (v6) : IDs des sources triées d'un geste. Usage
  // client (pré-sélection + repondération au reveal Q10) ; agrégat persisté
  // côté API en compteurs.
  final List<String>? swipeLiked;
  final List<String>? swipeDisliked;

  const OnboardingAnswers({
    this.objectives,
    this.ageRange,
    this.gender,
    this.approach,
    this.perspective,
    this.responseStyle,
    this.independencePref,
    this.contentRecency,
    this.gamificationEnabled,
    this.dailyArticleCount,
    this.digestMode,
    this.themes,
    this.subtopics,
    this.sourcesIntent,
    this.preferredSources,
    this.formatPreference,
    this.personalGoal,
    this.swipeLiked,
    this.swipeDisliked,
  });

  OnboardingAnswers copyWith({
    List<String>? objectives,
    String? ageRange,
    String? gender,
    String? approach,
    String? perspective,
    String? responseStyle,
    String? independencePref,
    String? contentRecency,
    bool? gamificationEnabled,
    int? dailyArticleCount,
    String? digestMode,
    List<String>? themes,
    List<String>? subtopics,
    String? sourcesIntent,
    List<String>? preferredSources,
    String? formatPreference,
    String? personalGoal,
    List<String>? swipeLiked,
    List<String>? swipeDisliked,
  }) {
    return OnboardingAnswers(
      objectives: objectives ?? this.objectives,
      ageRange: ageRange ?? this.ageRange,
      gender: gender ?? this.gender,
      approach: approach ?? this.approach,
      perspective: perspective ?? this.perspective,
      responseStyle: responseStyle ?? this.responseStyle,
      independencePref: independencePref ?? this.independencePref,
      contentRecency: contentRecency ?? this.contentRecency,
      gamificationEnabled: gamificationEnabled ?? this.gamificationEnabled,
      dailyArticleCount: dailyArticleCount ?? this.dailyArticleCount,
      digestMode: digestMode ?? this.digestMode,
      themes: themes ?? this.themes,
      subtopics: subtopics ?? this.subtopics,
      sourcesIntent: sourcesIntent ?? this.sourcesIntent,
      preferredSources: preferredSources ?? this.preferredSources,
      formatPreference: formatPreference ?? this.formatPreference,
      personalGoal: personalGoal ?? this.personalGoal,
      swipeLiked: swipeLiked ?? this.swipeLiked,
      swipeDisliked: swipeDisliked ?? this.swipeDisliked,
    );
  }

  Map<String, dynamic> toJson() => {
        'objective': objectives?.join(','),
        'age_range': ageRange,
        'gender': gender,
        'approach': approach,
        'perspective': perspective,
        'response_style': responseStyle,
        'independence_pref': independencePref,
        'content_recency': contentRecency,
        'gamification_enabled': gamificationEnabled,
        'weekly_goal': dailyArticleCount,
        'digest_mode': digestMode,
        'themes': themes,
        'subtopics': subtopics,
        'preferred_sources': preferredSources,
        'format_preference': formatPreference,
        'personal_goal': personalGoal,
        'swipe_liked': swipeLiked,
        'swipe_disliked': swipeDisliked,
      };

  /// Sérialisation locale (Hive) : ajoute les champs hors payload API.
  /// `toJson()` reste le contrat exact de POST /users/onboarding.
  Map<String, dynamic> toLocalJson() => {
        ...toJson(),
        'sources_intent': sourcesIntent,
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
      independencePref: json['independence_pref'] as String?,
      contentRecency: json['content_recency'] as String?,
      gamificationEnabled: json['gamification_enabled'] as bool?,
      dailyArticleCount: json['weekly_goal'] as int?,
      digestMode: json['digest_mode'] as String?,
      themes: (json['themes'] as List<dynamic>?)?.cast<String>(),
      subtopics: (json['subtopics'] as List<dynamic>?)?.cast<String>(),
      sourcesIntent: json['sources_intent'] as String?,
      preferredSources:
          (json['preferred_sources'] as List<dynamic>?)?.cast<String>(),
      formatPreference: json['format_preference'] as String?,
      personalGoal: json['personal_goal'] as String?,
      swipeLiked: (json['swipe_liked'] as List<dynamic>?)?.cast<String>(),
      swipeDisliked:
          (json['swipe_disliked'] as List<dynamic>?)?.cast<String>(),
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

/// Questions de la Section 1 (Overview) — 5 étapes
enum Section1Question {
  intro1, // Intro: Welcome
  intro2, // Intro: Mission
  mediaConcentration, // Carte concentration médias
  objective, // Q1: Multi-select diagnostic
  objectiveReaction, // R1: Réaction personnalisée
}

/// Questions de la Section 2 (App Preferences) — 2 étapes
/// Axes "profondeur" ré-aiguillés (v6) : la posture (ex-`responseStyle`) a été
/// retirée du parcours ; à la place on demande l'axe Indépendance.
enum Section2Question {
  approach, // Q4: profondeur des sources (direct / detailed)
  independence, // Q5b: références établies / indépendants
}

/// Questions de la Section 3 (Source Preferences)
/// Ordre : Thèmes → Subtopics → Intent sources → Sources → [Mode serein] → Finalize
/// `digestMode` n'apparaît que si l'objectif « anxiety » est coché (mode serein
/// conditionnel, placé juste avant le final).
enum Section3Question {
  themes, // Q9: Vos thèmes préférés (cloud pur)
  subtopics, // Q9b: Affine tes centres d'intérêt (cards structurées)
  sourcesIntent, // Q9c: Avec quels médias préférez-vous partir ? (curious/knows)
  swipe, // Q9c bis: désambiguateur (conditionnel : parcours « curieux » seul)
  sources, // Q10: Page sources adaptative (suggestions / recherche selon intent)
  digestMode, // Mode serein (conditionnel : objectif « anxiety » uniquement)
  finalize, // Écran de finalisation
}

/// État global de l'onboarding
class OnboardingState {
  final OnboardingSection currentSection;
  final int currentQuestionIndex;
  final OnboardingAnswers answers;
  final bool isTransitioning;
  final bool showReaction;

  /// Thèmes personnalisés dont la sauvegarde API a échoué pendant Subtopics.
  /// Affiché en fin de parcours pour informer l'utilisateur qu'il pourra
  /// les ré-ajouter depuis Mes Intérêts.
  final List<String> failedCustomTopics;

  const OnboardingState({
    this.currentSection = OnboardingSection.overview,
    this.currentQuestionIndex = 0,
    this.answers = const OnboardingAnswers(),
    this.isTransitioning = false,
    this.showReaction = false,
    this.failedCustomTopics = const [],
  });

  /// Nombre total de questions dans la Section 1
  static const int section1QuestionCount = 5;

  /// Nombre total de questions dans la Section 2
  int get section2QuestionCount => 2;

  /// `true` si le mode serein doit être proposé (objectif « anxiety » coché).
  bool get hasAnxietyObjective =>
      answers.objectives?.contains('anxiety') ?? false;

  /// Séquence active des questions de la Section 3 :
  /// - `digestMode` est retiré quand le mode serein n'est pas proposé (pas
  ///   d'objectif anxiety) ;
  /// - `swipe` (désambiguateur) est retiré sur le parcours « je connais déjà »
  ///   (`sourcesIntent == 'knows'`) — il ne sert qu'au parcours « curieux ».
  List<Section3Question> get section3Sequence =>
      Section3Question.values.where((q) {
        if (q == Section3Question.digestMode && !hasAnxietyObjective) {
          return false;
        }
        if (q == Section3Question.swipe && answers.sourcesIntent == 'knows') {
          return false;
        }
        return true;
      }).toList();

  /// Nombre de questions effectives de la Section 3 (varie avec le mode serein
  /// et le parcours sources, via [section3Sequence]).
  int get section3QuestionCount => section3Sequence.length;

  /// Position (0-based) de la question Section 3 courante dans la séquence
  /// active — gère le saut de `digestMode` pour le calcul de progression.
  int get _section3StepIndex {
    final pos = section3Sequence.indexOf(currentSection3Question);
    return pos < 0 ? currentQuestionIndex : pos;
  }

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
            _section3StepIndex;
    }
  }

  /// Nombre total d'étapes estimées pour l'onboarding (dynamique selon le mode)
  int get totalSteps =>
      section1QuestionCount + section2QuestionCount + section3QuestionCount;

  /// Progression globale (0.0 à 1.0)
  double get progress => (globalQuestionIndex + 1) / totalSteps;

  /// Progression dans la section courante (0.0 à 1.0)
  double get sectionProgress {
    switch (currentSection) {
      case OnboardingSection.overview:
        return currentQuestionIndex / section1QuestionCount;
      case OnboardingSection.appPreferences:
        return currentQuestionIndex / section2QuestionCount;
      case OnboardingSection.sourcePreferences:
        return _section3StepIndex / section3QuestionCount;
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

  /// Indique si la question courante peut être passée (« Passer ») avec un
  /// défaut sain. Les écrans d'intro / réaction / sources / finalize ne le sont
  /// pas. Voir [OnboardingNotifier.skipCurrentQuestion].
  bool get isSkippable {
    switch (currentSection) {
      case OnboardingSection.overview:
        return currentSection1Question == Section1Question.objective &&
            !showReaction;
      case OnboardingSection.appPreferences:
        return currentSection2Question == Section2Question.approach ||
            currentSection2Question == Section2Question.independence;
      case OnboardingSection.sourcePreferences:
        // Thèmes + sous-thèmes ne sont plus skippables (décision PO) : ces deux
        // étapes structurent toute la perso et ont déjà un gate « >=1 sélection »
        // côté bouton Continuer. L'intent sources, le swipe désambiguateur et le
        // mode digest gardent un défaut sain et restent passables.
        final q = currentSection3Question;
        return q == Section3Question.sourcesIntent ||
            q == Section3Question.swipe ||
            q == Section3Question.digestMode;
    }
  }

  OnboardingState copyWith({
    OnboardingSection? currentSection,
    int? currentQuestionIndex,
    OnboardingAnswers? answers,
    bool? isTransitioning,
    bool? showReaction,
    List<String>? failedCustomTopics,
  }) {
    return OnboardingState(
      currentSection: currentSection ?? this.currentSection,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      answers: answers ?? this.answers,
      isTransitioning: isTransitioning ?? this.isTransitioning,
      showReaction: showReaction ?? this.showReaction,
      failedCustomTopics: failedCustomTopics ?? this.failedCustomTopics,
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
  // v5 : sourcesReaction (page 2 sources) supprimé, sourcesIntent inséré →
  // les index d'enum changent, on doit wiper les positions sauvegardées
  // (sinon reprise Hive sur un index invalide).
  // v6 : posture (responseStyle) retirée de la Section 2 → remplacée par
  // l'axe Indépendance ; étape `swipe` insérée en Section 3. Les index d'enum
  // changent à nouveau → bump obligatoire pour wiper les positions sauvegardées.
  static const int _currentVersion = 6;

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

      // Restore answers if available
      if (savedAnswers != null) {
        final answers = OnboardingAnswers.fromJson(
          Map<String, dynamic>.from(savedAnswers as Map),
        );
        state = state.copyWith(answers: answers);
      }

      // Always restore navigation position (needed for restart pre-config
      // written by auth_state._checkOnboardingStatus which sets section/question
      // without setting answers)
      if (savedSection != null || savedQuestion != null) {
        state = state.copyWith(
          currentSection: savedSection != null && savedSection is int
              ? OnboardingSection.values[savedSection]
              : state.currentSection,
          currentQuestionIndex:
              savedQuestion is int ? savedQuestion : state.currentQuestionIndex,
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
      await box.put(_answersKey, state.answers.toLocalJson());
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

  /// Continue après la réaction (après R1) → transition vers Section 2
  void continueAfterReaction() {
    state = state.copyWith(
      currentSection: OnboardingSection.appPreferences,
      currentQuestionIndex: Section2Question.approach.index,
      showReaction: false,
      isTransitioning: false,
    );
  }

  /// Sélectionne l'approche / profondeur (Q4) - première question Section 2
  void selectApproach(String approach) {
    state = state.copyWith(
      answers: state.answers.copyWith(approach: approach),
      isTransitioning: true,
    );
    _saveAnswers();

    // Passe à la question suivante dans Section 2 (Indépendance)
    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section2Question.independence.index,
        isTransitioning: false,
      );
    });
  }

  /// Revient à la question précédente
  void goBack() {
    // Section 3 : navigation selon la séquence active (digestMode conditionnel,
    // donc on ne peut pas se contenter d'un index - 1 qui retomberait sur une
    // question sautée).
    if (state.currentSection == OnboardingSection.sourcePreferences) {
      final seq = state.section3Sequence;
      final pos = seq.indexOf(state.currentSection3Question);
      if (pos > 0) {
        state = state.copyWith(currentQuestionIndex: seq[pos - 1].index);
      } else {
        // themes (1ère question) → retour Section 2 (dernière = independence)
        state = state.copyWith(
          currentSection: OnboardingSection.appPreferences,
          currentQuestionIndex: Section2Question.independence.index,
        );
      }
      return;
    }

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
      // currentQuestionIndex == 0 : revenir à la section précédente
      if (state.currentSection == OnboardingSection.appPreferences) {
        state = state.copyWith(
          currentSection: OnboardingSection.overview,
          currentQuestionIndex: Section1Question.objectiveReaction.index,
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

  /// Sélectionne l'axe Indépendance (Q5b) — dernière question de la Section 2 →
  /// transition vers la Section 3. Valeurs : established / independent.
  void selectIndependence(String independencePref) {
    state = state.copyWith(
      answers: state.answers.copyWith(independencePref: independencePref),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      _transitionToSection3();
    });
  }

  /// Sélectionne le mode digest (Section 3, mode serein conditionnel) → finalize
  void selectDigestMode(String mode) {
    state = state.copyWith(
      answers: state.answers.copyWith(digestMode: mode),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section3Question.finalize.index,
        isTransitioning: false,
      );
    });
  }

  /// Pré-sélectionne un mode digest SANS enchaîner vers la section 3.
  /// Utilisé par le CTA "Personnaliser mon mode serein" : on marque le choix,
  /// on ouvre la page Mes Intérêts, et au retour l'utilisateur retrouve la
  /// question "Rester serein ?" avec "Oui" déjà coché — prêt à continuer.
  void markDigestMode(String mode) {
    state = state.copyWith(
      answers: state.answers.copyWith(digestMode: mode),
    );
    _saveAnswers();
  }

  /// Passe la question courante en appliquant un défaut sain, puis avance.
  /// Branché sur le bouton « Passer » de [OnboardingScreen] (visible quand
  /// [OnboardingState.isSkippable]).
  void skipCurrentQuestion() {
    switch (state.currentSection) {
      case OnboardingSection.overview:
        // objective → aucun objectif + saut direct Section 2 (pas de réaction)
        state = state.copyWith(
          answers: state.answers.copyWith(objectives: const []),
          currentSection: OnboardingSection.appPreferences,
          currentQuestionIndex: Section2Question.approach.index,
          showReaction: false,
        );
        _saveAnswers();
      case OnboardingSection.appPreferences:
        switch (state.currentSection2Question) {
          case Section2Question.approach:
            state = state.copyWith(
              answers: state.answers.copyWith(approach: 'detailed'),
              currentQuestionIndex: Section2Question.independence.index,
            );
            _saveAnswers();
          case Section2Question.independence:
            // Défaut neutre : « références établies » (le catalogue est large).
            state = state.copyWith(
              answers: state.answers.copyWith(independencePref: 'established'),
            );
            _saveAnswers();
            _transitionToSection3();
        }
      case OnboardingSection.sourcePreferences:
        switch (state.currentSection3Question) {
          case Section3Question.themes:
            // pas de thèmes → saut direct intent (pas de subtopics sans thème)
            state = state.copyWith(
              answers: state.answers.copyWith(themes: const []),
              currentQuestionIndex: Section3Question.sourcesIntent.index,
            );
            _saveAnswers();
          case Section3Question.subtopics:
            state = state.copyWith(
              answers: state.answers.copyWith(subtopics: const []),
              currentQuestionIndex: Section3Question.sourcesIntent.index,
            );
            _saveAnswers();
          case Section3Question.sourcesIntent:
            // défaut PO : variante « curieux » (suggestions guidées) → le
            // parcours curieux passe par le swipe désambiguateur.
            state = state.copyWith(
              answers: state.answers.copyWith(sourcesIntent: 'curious'),
              currentQuestionIndex: Section3Question.swipe.index,
            );
            _saveAnswers();
          case Section3Question.swipe:
            // Passer le swipe : aucun vote, on enchaîne sur la page sources.
            state = state.copyWith(
              answers: state.answers.copyWith(
                swipeLiked: const [],
                swipeDisliked: const [],
              ),
              currentQuestionIndex: Section3Question.sources.index,
            );
            _saveAnswers();
          case Section3Question.digestMode:
            state = state.copyWith(
              answers: state.answers.copyWith(digestMode: 'pour_vous'),
              currentQuestionIndex: Section3Question.finalize.index,
            );
            _saveAnswers();
          case Section3Question.sources:
          case Section3Question.finalize:
            break;
        }
    }
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
  /// Thèmes → Subtopics → Sources → Finalize
  void selectThemes(List<String> themes) {
    state = state.copyWith(
      answers: state.answers.copyWith(themes: themes),
      isTransitioning: true,
    );
    _saveAnswers();

    // Aller vers Subtopics (écran B)
    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section3Question.subtopics.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne les sous-thèmes (Q9b) → Intent sources
  void selectSubtopics(List<String> subtopics) {
    state = state.copyWith(
      answers: state.answers.copyWith(subtopics: subtopics),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section3Question.sourcesIntent.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne l'intent sources (Q9c : curious / knows).
  /// - `curious` → étape swipe désambiguateur (puis page sources) ;
  /// - `knows` → directement la page sources (le swipe est sauté, l'utilisateur
  ///   part de ses propres médias).
  void selectSourcesIntent(String intent) {
    state = state.copyWith(
      answers: state.answers.copyWith(sourcesIntent: intent),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: intent == 'knows'
            ? Section3Question.sources.index
            : Section3Question.swipe.index,
        isTransitioning: false,
      );
    });
  }

  /// Termine le swipe désambiguateur : enregistre les sources triées (likées /
  /// rejetées) puis enchaîne sur la page sources (Q10). Les likes seront
  /// boostés et pré-sélectionnés au reveal via [SourceRecommender].
  void completeSwipe(List<String> liked, List<String> disliked) {
    state = state.copyWith(
      answers: state.answers.copyWith(
        swipeLiked: liked,
        swipeDisliked: disliked,
      ),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: Section3Question.sources.index,
        isTransitioning: false,
      );
    });
  }

  /// Sélectionne les sources (Q10) puis route vers la fin de parcours.
  /// Mode serein conditionnel : si l'objectif « anxiety » est coché → on insère
  /// la question digestMode juste avant le final ; sinon on pose le défaut
  /// neutre `pour_vous` et on saute directement au final.
  void selectSources(List<String> sources) {
    final hasAnxiety = state.hasAnxietyObjective;
    state = state.copyWith(
      answers: state.answers.copyWith(
        preferredSources: sources,
        digestMode: hasAnxiety ? state.answers.digestMode : 'pour_vous',
      ),
      isTransitioning: true,
    );
    _saveAnswers();

    Future.delayed(const Duration(milliseconds: 300), () {
      state = state.copyWith(
        currentQuestionIndex: hasAnxiety
            ? Section3Question.digestMode.index
            : Section3Question.finalize.index,
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

  /// Enregistre les noms des thèmes personnalisés dont la création API a échoué
  /// pendant Subtopics. Non-bloquant — affiché en résumé après la conclusion.
  void recordFailedCustomTopics(List<String> names) {
    if (names.isEmpty) return;
    state = state.copyWith(
      failedCustomTopics: [...state.failedCustomTopics, ...names],
    );
  }

  /// Reset la liste des échecs (après affichage du résumé post-onboarding).
  void clearFailedCustomTopics() {
    state = state.copyWith(failedCustomTopics: const []);
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
        independencePref: 'independent',
        gamificationEnabled: true,
        dailyArticleCount: 5,
        digestMode: 'pour_vous',
        themes: ['tech', 'international'],
        sourcesIntent: 'curious',
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
      answers.approach != null;
});

/// Provider pour vérifier si Section 2 est complète.
/// Section 2 = axes "profondeur" (approach) + Indépendance (independencePref).
/// La posture (ex-responseStyle) a été retirée du parcours (v6).
final isSection2CompleteProvider = Provider<bool>((ref) {
  final state = ref.watch(onboardingProvider);
  final answers = state.answers;
  return answers.approach != null && answers.independencePref != null;
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

/// Liste des thèmes disponibles.
/// Les couleurs sont alignées sur [themeMap] (theme_color_mapping.dart) pour
/// une cohérence visuelle entre l'onboarding et le Flux Continu.
class AvailableThemes {
  static final List<ThemeOption> all = [
    const ThemeOption(
      slug: 'tech',
      label: OnboardingStrings.themeTech,
      emoji: '💻',
      color: Color(0xFF1565C0),
    ),
    const ThemeOption(
      slug: 'international',
      label: OnboardingStrings.themeInternational,
      emoji: '🌍',
      color: Color(0xFF0288D1),
    ),
    const ThemeOption(
      slug: 'science',
      label: OnboardingStrings.themeScience,
      emoji: '🔬',
      color: Color(0xFF0097A7),
    ),
    const ThemeOption(
      slug: 'culture',
      label: OnboardingStrings.themeCulture,
      emoji: '🎨',
      color: Color(0xFFAD1457),
    ),
    const ThemeOption(
      slug: 'politics',
      label: OnboardingStrings.themePolitics,
      emoji: '🏛️',
      color: Color(0xFFB71C1C),
    ),
    const ThemeOption(
      slug: 'society',
      label: OnboardingStrings.themeSociety,
      emoji: '👥',
      color: Color(0xFF6A1B9A),
    ),
    const ThemeOption(
      slug: 'environment',
      label: OnboardingStrings.themeEnvironment,
      emoji: '🌿',
      color: Color(0xFF00695C),
    ),
    const ThemeOption(
      slug: 'economy',
      label: OnboardingStrings.themeEconomy,
      emoji: '📈',
      color: Color(0xFFF57F17),
    ),
    const ThemeOption(
      slug: 'sport',
      label: OnboardingStrings.themeSport,
      emoji: '⚽',
      color: Color(0xFFE64A19),
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
