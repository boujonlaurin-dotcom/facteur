import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/features/onboarding/providers/onboarding_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive/hive.dart';

/// Laisse passer les transitions `Future.delayed(300ms)` des sélections.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 350));

void main() {
  setUp(() async {
    Hive.init('.');
    // Repartir d'un onboarding vierge : éviter qu'une position sauvegardée par
    // un test précédent ne soit restaurée par _loadSavedAnswers.
    try {
      final box = await Hive.openBox<dynamic>('onboarding');
      await box.clear();
    } catch (_) {}
  });

  // ──────────────────────────────────────────────────────────────────────
  // Ordre des enums — garde-fou contre la réindexation (v5) qui casserait la
  // reprise Hive et le routage des questions.
  // ──────────────────────────────────────────────────────────────────────
  group('Enum order (v5)', () {
    test('Section2Question = {approach, responseStyle}', () {
      expect(Section2Question.values, hasLength(2));
      expect(Section2Question.approach.index, 0);
      expect(Section2Question.responseStyle.index, 1);
    });

    test('Section3Question : sourcesIntent avant sources, digestMode avant finalize',
        () {
      expect(Section3Question.values, hasLength(6));
      expect(Section3Question.themes.index, 0);
      expect(Section3Question.subtopics.index, 1);
      expect(Section3Question.sourcesIntent.index, 2);
      expect(Section3Question.sources.index, 3);
      expect(Section3Question.digestMode.index, 4);
      expect(Section3Question.finalize.index, 5);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // Mode serein conditionnel : la séquence Section 3 et la progression
  // dépendent de l'objectif « anxiety ».
  // ──────────────────────────────────────────────────────────────────────
  group('Section 3 sequence (gating anxiety)', () {
    OnboardingState stateWith(List<String> objectives) => OnboardingState(
          currentSection: OnboardingSection.sourcePreferences,
          answers: OnboardingAnswers(objectives: objectives),
        );

    test('sans anxiety : digestMode est retiré (5 étapes)', () {
      final s = stateWith(['noise']);
      expect(s.hasAnxietyObjective, isFalse);
      expect(s.section3Sequence, isNot(contains(Section3Question.digestMode)));
      expect(s.section3QuestionCount, 5);
      // total = section1(5) + section2(2) + section3(5)
      expect(s.totalSteps, 12);
    });

    test('avec anxiety : digestMode inclus (6 étapes)', () {
      final s = stateWith(['anxiety']);
      expect(s.hasAnxietyObjective, isTrue);
      expect(s.section3Sequence, contains(Section3Question.digestMode));
      expect(s.section3QuestionCount, 6);
      expect(s.totalSteps, 13);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // isSkippable : quelles questions exposent le bouton « Passer ».
  // ──────────────────────────────────────────────────────────────────────
  group('isSkippable', () {
    test('objective skippable, pas les intros ni la réaction', () {
      expect(
        const OnboardingState(
          currentQuestionIndex: 0, // intro1
        ).isSkippable,
        isFalse,
      );
      expect(
        OnboardingState(
          currentQuestionIndex: Section1Question.objective.index,
        ).isSkippable,
        isTrue,
      );
      expect(
        OnboardingState(
          currentQuestionIndex: Section1Question.objectiveReaction.index,
          showReaction: true,
        ).isSkippable,
        isFalse,
      );
    });

    test('approach et responseStyle skippables', () {
      expect(
        OnboardingState(
          currentSection: OnboardingSection.appPreferences,
          currentQuestionIndex: Section2Question.approach.index,
        ).isSkippable,
        isTrue,
      );
      expect(
        OnboardingState(
          currentSection: OnboardingSection.appPreferences,
          currentQuestionIndex: Section2Question.responseStyle.index,
        ).isSkippable,
        isTrue,
      );
    });

    test('themes/subtopics/sourcesIntent/digestMode skippables, pas sources/finalize',
        () {
      OnboardingState s3(Section3Question q) => OnboardingState(
            currentSection: OnboardingSection.sourcePreferences,
            currentQuestionIndex: q.index,
          );
      expect(s3(Section3Question.themes).isSkippable, isTrue);
      expect(s3(Section3Question.subtopics).isSkippable, isTrue);
      expect(s3(Section3Question.sourcesIntent).isSkippable, isTrue);
      expect(s3(Section3Question.digestMode).isSkippable, isTrue);
      expect(s3(Section3Question.sources).isSkippable, isFalse);
      expect(s3(Section3Question.finalize).isSkippable, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // skipCurrentQuestion : défauts sains + sauts.
  // ──────────────────────────────────────────────────────────────────────
  group('skipCurrentQuestion', () {
    test('objective → Section 2 (approach) avec objectifs vides', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueToIntro2();
      n.continueAfterIntro();
      n.continueAfterMediaConcentration(); // → objective
      n.skipCurrentQuestion();

      final s = c.read(onboardingProvider);
      expect(s.currentSection, OnboardingSection.appPreferences);
      expect(s.currentQuestionIndex, Section2Question.approach.index);
      expect(s.answers.objectives, isEmpty);
      expect(s.showReaction, isFalse);
    });

    test('approach → responseStyle avec défaut detailed', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueAfterReaction(); // → Section 2 approach
      n.skipCurrentQuestion();

      final s = c.read(onboardingProvider);
      expect(s.currentSection, OnboardingSection.appPreferences);
      expect(s.currentQuestionIndex, Section2Question.responseStyle.index);
      expect(s.answers.approach, 'detailed');
    });

    test('responseStyle → Section 3 (themes) avec défaut nuanced', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueAfterReaction();
      n.skipCurrentQuestion(); // approach → responseStyle
      n.skipCurrentQuestion(); // responseStyle → _transitionToSection3 (sync)

      final s = c.read(onboardingProvider);
      expect(s.currentSection, OnboardingSection.sourcePreferences);
      expect(s.currentQuestionIndex, Section3Question.themes.index);
      expect(s.answers.responseStyle, 'nuanced');
    });

    test('themes → sourcesIntent (saute subtopics) avec thèmes vides',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueAfterReaction();
      n.skipCurrentQuestion(); // → responseStyle
      n.skipCurrentQuestion(); // → Section 3 themes
      n.skipCurrentQuestion(); // themes → sourcesIntent

      final s = c.read(onboardingProvider);
      expect(s.currentQuestionIndex, Section3Question.sourcesIntent.index);
      expect(s.answers.themes, isEmpty);
    });

    test('sourcesIntent → sources avec défaut curious', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueAfterReaction();
      n.skipCurrentQuestion(); // → responseStyle
      n.skipCurrentQuestion(); // → Section 3 themes
      n.skipCurrentQuestion(); // themes → sourcesIntent
      n.skipCurrentQuestion(); // sourcesIntent → sources

      final s = c.read(onboardingProvider);
      expect(s.currentQuestionIndex, Section3Question.sources.index);
      expect(s.answers.sourcesIntent, 'curious');
    });

    test('digestMode → finalize avec défaut pour_vous', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.selectObjectives(['anxiety']);
      n.continueAfterReaction();
      n.skipCurrentQuestion(); // → responseStyle
      n.skipCurrentQuestion(); // → Section 3 themes (anxiety préservé)
      n.selectSources(['s1']); // anxiety → digestMode
      await _settle();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.digestMode.index,
      );

      n.skipCurrentQuestion(); // digestMode → finalize

      final s = c.read(onboardingProvider);
      expect(s.currentQuestionIndex, Section3Question.finalize.index);
      expect(s.answers.digestMode, 'pour_vous');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // selectSourcesIntent : routage vers la page sources + réponse persistée.
  // ──────────────────────────────────────────────────────────────────────
  group('selectSourcesIntent', () {
    test('subtopics → sourcesIntent → sources, intent enregistré', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueAfterReaction();
      n.skipCurrentQuestion(); // → responseStyle
      n.skipCurrentQuestion(); // → Section 3 themes
      n.selectThemes(['tech']);
      await _settle();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.subtopics.index,
      );

      n.selectSubtopics(['ai']);
      await _settle();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.sourcesIntent.index,
      );

      n.selectSourcesIntent('knows');
      expect(c.read(onboardingProvider).answers.sourcesIntent, 'knows');
      await _settle();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.sources.index,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // selectSources : routage de fin de parcours selon l'objectif anxiety
  // (logique reprise de l'ex-continueFromSourcesPage2).
  // ──────────────────────────────────────────────────────────────────────
  group('selectSources (gating anxiety)', () {
    test('sans anxiety : pose pour_vous et saute au final', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.selectObjectives(['noise']);
      n.continueAfterReaction();
      n.skipCurrentQuestion();
      n.skipCurrentQuestion(); // → Section 3 themes
      n.selectSources(['s1']);

      // digestMode posé immédiatement (synchrone)
      expect(c.read(onboardingProvider).answers.digestMode, 'pour_vous');

      await _settle();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.finalize.index,
      );
    });

    test('avec anxiety : route vers digestMode, sans défaut imposé', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.selectObjectives(['anxiety']);
      n.continueAfterReaction();
      n.skipCurrentQuestion();
      n.skipCurrentQuestion(); // → Section 3 themes
      n.selectSources(['s1']);

      // digestMode pas forcé : laissé au choix de l'utilisateur
      expect(c.read(onboardingProvider).answers.digestMode, isNull);

      await _settle();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.digestMode.index,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // goBack : navigation arrière sur la séquence active de la Section 3.
  // ──────────────────────────────────────────────────────────────────────
  group('goBack (Section 3)', () {
    test('depuis sources, goBack remonte la séquence sans digestMode',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.selectObjectives(['noise']);
      n.continueAfterReaction();
      n.skipCurrentQuestion();
      n.skipCurrentQuestion(); // → Section 3 themes
      n.skipCurrentQuestion(); // themes → sourcesIntent
      n.skipCurrentQuestion(); // sourcesIntent → sources
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.sources.index,
      );

      n.goBack();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.sourcesIntent.index,
      );

      n.goBack();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.subtopics.index,
      );

      n.goBack();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.themes.index,
      );
    });
  });

  group('OnboardingAnswers', () {
    test('toJson/fromJson roundtrip préserve themes et subtopics', () {
      const answers = OnboardingAnswers(
        themes: ['tech', 'science'],
        subtopics: ['ai', 'climate'],
        preferredSources: ['source-1', 'source-2'],
      );

      final restored = OnboardingAnswers.fromJson(answers.toJson());

      expect(restored.themes, equals(['tech', 'science']));
      expect(restored.subtopics, equals(['ai', 'climate']));
      expect(restored.preferredSources, equals(['source-1', 'source-2']));
    });

    test('toJson (payload API) n\'expose pas sources_intent', () {
      const answers = OnboardingAnswers(sourcesIntent: 'knows');
      expect(answers.toJson().containsKey('sources_intent'), isFalse);
    });

    test('toLocalJson/fromJson roundtrip préserve sourcesIntent', () {
      const answers = OnboardingAnswers(
        sourcesIntent: 'knows',
        themes: ['tech'],
      );
      final restored = OnboardingAnswers.fromJson(answers.toLocalJson());
      expect(restored.sourcesIntent, 'knows');
      expect(restored.themes, equals(['tech']));
    });
  });
}
