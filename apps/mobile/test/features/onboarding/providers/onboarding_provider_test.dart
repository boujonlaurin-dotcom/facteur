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
  // Ordre des enums — garde-fou contre la réindexation (v8) qui casserait la
  // reprise Hive et le routage des questions.
  // ──────────────────────────────────────────────────────────────────────
  group('Enum order (v8)', () {
    test('Section2Question = {approach, independence}', () {
      expect(Section2Question.values, hasLength(2));
      expect(Section2Question.approach.index, 0);
      expect(Section2Question.independence.index, 1);
    });

    test('Section3Question : digestMode retiré (v8), finalize à l\'index 4', () {
      expect(Section3Question.values, hasLength(5));
      expect(Section3Question.themes.index, 0);
      expect(Section3Question.subtopics.index, 1);
      expect(Section3Question.swipe.index, 2);
      expect(Section3Question.sources.index, 3);
      expect(Section3Question.finalize.index, 4);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // Séquence Section 3 : plus aucune branche conditionnelle (v8, mode serein
  // déplacé vers le tour guidé). Toujours 5 questions, quels que soient les
  // objectifs (y compris « anxiety »).
  // ──────────────────────────────────────────────────────────────────────
  group('Section 3 sequence (constante v8)', () {
    OnboardingState stateWith(List<String> objectives) => OnboardingState(
      currentSection: OnboardingSection.sourcePreferences,
      answers: OnboardingAnswers(objectives: objectives),
    );

    test('séquence complète, swipe présent, sans digestMode (5)', () {
      final s = stateWith(['noise']);
      expect(
        s.section3Sequence,
        equals(const [
          Section3Question.themes,
          Section3Question.subtopics,
          Section3Question.swipe,
          Section3Question.sources,
          Section3Question.finalize,
        ]),
      );
      expect(s.section3QuestionCount, 5);
      // total = section1(5) + section2(2) + section3(5)
      expect(s.totalSteps, 12);
    });

    test('objectif anxiety : séquence identique (pas de digestMode)', () {
      final s = stateWith(['anxiety']);
      expect(s.section3QuestionCount, 5);
      expect(s.totalSteps, 12);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // isSkippable : aucun écran n'expose plus le bouton « Passer ».
  // ──────────────────────────────────────────────────────────────────────
  group('isSkippable', () {
    test('overview: intros, objective et réaction non skippables', () {
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
        isFalse,
      );
      expect(
        OnboardingState(
          currentQuestionIndex: Section1Question.objectiveReaction.index,
          showReaction: true,
        ).isSkippable,
        isFalse,
      );
    });

    test('approach et independence non skippables', () {
      expect(
        OnboardingState(
          currentSection: OnboardingSection.appPreferences,
          currentQuestionIndex: Section2Question.approach.index,
        ).isSkippable,
        isFalse,
      );
      expect(
        OnboardingState(
          currentSection: OnboardingSection.appPreferences,
          currentQuestionIndex: Section2Question.independence.index,
        ).isSkippable,
        isFalse,
      );
    });

    test(
      'Section 3: themes/subtopics/swipe/sources/finalize non skippables',
      () {
        OnboardingState s3(Section3Question q) => OnboardingState(
          currentSection: OnboardingSection.sourcePreferences,
          currentQuestionIndex: q.index,
        );
        // Décision PO : thèmes + sous-thèmes ne sont plus skippables ; le swipe
        // est désormais obligatoire (« tout le monde swipe »).
        expect(s3(Section3Question.themes).isSkippable, isFalse);
        expect(s3(Section3Question.subtopics).isSkippable, isFalse);
        expect(s3(Section3Question.swipe).isSkippable, isFalse);
        expect(s3(Section3Question.sources).isSkippable, isFalse);
        expect(s3(Section3Question.finalize).isSkippable, isFalse);
      },
    );
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

    test('approach → independence avec défaut detailed', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueAfterReaction(); // → Section 2 approach
      n.skipCurrentQuestion();

      final s = c.read(onboardingProvider);
      expect(s.currentSection, OnboardingSection.appPreferences);
      expect(s.currentQuestionIndex, Section2Question.independence.index);
      expect(s.answers.approach, 'detailed');
    });

    test('independence → Section 3 (themes) avec défaut established', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueAfterReaction();
      n.skipCurrentQuestion(); // approach → independence
      n.skipCurrentQuestion(); // independence → _transitionToSection3 (sync)

      final s = c.read(onboardingProvider);
      expect(s.currentSection, OnboardingSection.sourcePreferences);
      expect(s.currentQuestionIndex, Section3Question.themes.index);
      expect(s.answers.independencePref, 'established');
    });

    test('themes → swipe (saute subtopics) avec thèmes vides', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueAfterReaction();
      n.skipCurrentQuestion(); // → independence
      n.skipCurrentQuestion(); // → Section 3 themes
      n.skipCurrentQuestion(); // themes → swipe

      final s = c.read(onboardingProvider);
      expect(s.currentQuestionIndex, Section3Question.swipe.index);
      expect(s.answers.themes, isEmpty);
    });

  });

  // ──────────────────────────────────────────────────────────────────────
  // selectSubtopics : enchaîne directement sur le swipe (v7).
  // ──────────────────────────────────────────────────────────────────────
  group('selectSubtopics', () {
    test('subtopics → swipe', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.continueAfterReaction();
      n.skipCurrentQuestion(); // → independence
      n.skipCurrentQuestion(); // → Section 3 themes
      n.selectThemes(['tech']);
      await _settle();
      n.selectSubtopics(['ai']);
      await _settle();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.swipe.index,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // completeSwipe : enregistre les votes et enchaîne sur la page sources.
  // ──────────────────────────────────────────────────────────────────────
  group('completeSwipe', () {
    test(
      'enregistre les votes likés/rejetés puis avance vers sources',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await _settle();
        final n = c.read(onboardingProvider.notifier);

        n.continueAfterReaction();
        n.skipCurrentQuestion(); // → independence
        n.skipCurrentQuestion(); // → Section 3 themes
        n.skipCurrentQuestion(); // themes → swipe

        n.completeSwipe(['liked-1', 'liked-2'], ['disliked-1']);
        expect(
          c.read(onboardingProvider).answers.swipeLiked,
          equals(['liked-1', 'liked-2']),
        );
        expect(
          c.read(onboardingProvider).answers.swipeDisliked,
          equals(['disliked-1']),
        );

        await _settle();
        expect(
          c.read(onboardingProvider).currentQuestionIndex,
          Section3Question.sources.index,
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // selectSources : route toujours vers le final avec le défaut neutre
  // `pour_vous` (v8, mode serein retiré de l'onboarding).
  // ──────────────────────────────────────────────────────────────────────
  group('selectSources (constant v8)', () {
    test('pose pour_vous et saute au final, sans anxiety', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.selectObjectives(['noise']);
      n.continueAfterReaction();
      n.skipCurrentQuestion(); // approach → independence
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

    test('objectif anxiety : même routage vers le final (pas de digestMode)',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settle();
      final n = c.read(onboardingProvider.notifier);

      n.selectObjectives(['anxiety']);
      n.continueAfterReaction();
      n.skipCurrentQuestion(); // approach → independence
      n.skipCurrentQuestion(); // → Section 3 themes
      n.selectSources(['s1']);

      expect(c.read(onboardingProvider).answers.digestMode, 'pour_vous');

      await _settle();
      expect(
        c.read(onboardingProvider).currentQuestionIndex,
        Section3Question.finalize.index,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // goBack : navigation arrière sur la séquence active de la Section 3
  // (parcours curieux → le swipe est dans la séquence).
  // ──────────────────────────────────────────────────────────────────────
  group('goBack (Section 3)', () {
    test(
      'depuis sources, goBack remonte la séquence avec swipe, sans digestMode',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await _settle();
        final n = c.read(onboardingProvider.notifier);

        n.selectObjectives(['noise']);
        n.continueAfterReaction();
        n.skipCurrentQuestion(); // approach → independence
        n.skipCurrentQuestion(); // → Section 3 themes
        n.skipCurrentQuestion(); // themes → swipe
        n.completeSwipe(const [], const []); // swipe → sources
        await _settle();
        expect(
          c.read(onboardingProvider).currentQuestionIndex,
          Section3Question.sources.index,
        );

        n.goBack();
        expect(
          c.read(onboardingProvider).currentQuestionIndex,
          Section3Question.swipe.index,
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
      },
    );
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

    test('toJson/fromJson roundtrip préserve les axes profondeur (v6)', () {
      const answers = OnboardingAnswers(
        approach: 'detailed',
        independencePref: 'independent',
        swipeLiked: ['s1', 's2'],
        swipeDisliked: ['s3'],
      );

      final restored = OnboardingAnswers.fromJson(answers.toJson());

      expect(restored.approach, 'detailed');
      expect(restored.independencePref, 'independent');
      expect(restored.swipeLiked, equals(['s1', 's2']));
      expect(restored.swipeDisliked, equals(['s3']));
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
