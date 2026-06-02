import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_config_provider.dart';
import 'package:facteur/features/veille/providers/veille_repository_provider.dart';
import 'package:facteur/features/veille/providers/veille_themes_provider.dart';
import 'package:facteur/features/veille/repositories/veille_repository.dart';

/// Repo factice qui capture le body d'`upsertConfig` (pour tester le mapping
/// `_buildUpsertRequest`). Toute autre méthode throw → instrumentation à fixer.
class _CaptureRepo implements VeilleRepository {
  VeilleConfigUpsertRequest? captured;

  @override
  Future<VeilleConfigDto> upsertConfig(VeilleConfigUpsertRequest body) async {
    captured = body;
    return VeilleConfigDto(
      id: 'cfg-1',
      userId: 'user-1',
      themeId: body.themeId,
      themeLabel: body.themeLabel,
      status: 'active',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      topics: const [],
      sources: const [],
      keywords: const [],
    );
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non mocké');
}

/// Tests business-logic du `VeilleConfigNotifier` après le drop des suggesters
/// LLM (PR-4, Story 23.3). On vérifie surtout les transitions d'état et le
/// payload envoyé au backend.
void main() {
  late ProviderContainer container;
  late VeilleConfigNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(veilleConfigProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('selectTheme reset customThemeLabel quand on quitte "other"', () {
    notifier.selectTheme(kVeilleOtherThemeSlug);
    notifier.setCustomThemeLabel('Musées contemporains');
    expect(container.read(veilleConfigProvider).customThemeLabel,
        'Musées contemporains');

    notifier.selectTheme('tech');
    expect(container.read(veilleConfigProvider).customThemeLabel, isNull);
  });

  test('addKeyword normalise + dédupe + respecte le cap maxKeywords', () {
    for (var i = 0; i < VeilleConfigNotifier.maxKeywords + 5; i++) {
      notifier.addKeyword('kw-$i');
    }
    final keywords = container.read(veilleConfigProvider).keywords;
    expect(keywords.length, VeilleConfigNotifier.maxKeywords);

    notifier.addKeyword('  KW-0  '); // doublon normalisé
    expect(container.read(veilleConfigProvider).keywords.length,
        VeilleConfigNotifier.maxKeywords);
  });

  test('addKeyword rejette les inputs trop courts ou trop longs', () {
    notifier.addKeyword('a'); // 1 char → rejeté
    notifier.addKeyword('ok');
    notifier.addKeyword('x' * 61); // > 60 → rejeté
    expect(container.read(veilleConfigProvider).keywords, {'ok'});
  });

  test('skipStep2 avance à step 3 et clear les signaux optionnels', () {
    notifier.selectTheme('tech');
    notifier.goNext(); // step 2
    notifier.addKeyword('foo');
    notifier.setEditorialBrief('Focus PME');

    notifier.skipStep2();

    final s = container.read(veilleConfigProvider);
    expect(s.step, 3);
    expect(s.skippedStep2, isTrue);
    expect(s.keywords, isEmpty);
    expect(s.editorialBrief, isNull);
  });

  test('skipStep2 est no-op si on n\'est pas en step 2', () {
    notifier.selectTheme('tech');
    notifier.skipStep2();
    expect(container.read(veilleConfigProvider).step, 1);
    expect(container.read(veilleConfigProvider).skippedStep2, isFalse);
  });

  test('addCustomTopic ajoute + coche, doublon idempotent', () {
    notifier.addCustomTopic('IA générative');
    final s1 = container.read(veilleConfigProvider);
    expect(s1.customTopics.length, 1);
    expect(s1.selectedTopics.length, 1);

    notifier.addCustomTopic('  IA Générative  ');
    final s2 = container.read(veilleConfigProvider);
    expect(s2.customTopics.length, 1, reason: 'doublon ignoré');
    expect(s2.selectedTopics.length, 1);
  });

  test('addCustomTopic re-coche un topic déjà présent mais décoché', () {
    notifier.addCustomTopic('IA générative');
    final id = container.read(veilleConfigProvider).customTopics.first.id;
    notifier.toggleTopic(id); // décoche
    expect(container.read(veilleConfigProvider).selectedTopics, isEmpty);

    notifier.addCustomTopic('IA générative');
    expect(container.read(veilleConfigProvider).selectedTopics, {id});
  });

  test('setAdvancedMode ne touche pas aux valeurs déjà saisies', () {
    notifier.addKeyword('foo');
    notifier.setEditorialBrief('brief');
    notifier.setAdvancedMode(true);
    notifier.setAdvancedMode(false);
    final s = container.read(veilleConfigProvider);
    expect(s.keywords, {'foo'});
    expect(s.editorialBrief, 'brief');
  });

  test('resolvedThemeLabel utilise customThemeLabel quand thème = other', () {
    notifier.selectTheme(kVeilleOtherThemeSlug);
    notifier.setCustomThemeLabel('Musées');
    expect(container.read(veilleConfigProvider).resolvedThemeLabel('Autre'),
        'Musées');
  });

  test('resolvedThemeLabel fallback quand customThemeLabel vide en mode other',
      () {
    notifier.selectTheme(kVeilleOtherThemeSlug);
    expect(container.read(veilleConfigProvider).resolvedThemeLabel('Autre'),
        'Autre');
  });

  test('goNext cap à step 3 / goBack cap à step 1', () {
    expect(container.read(veilleConfigProvider).step, 1);
    notifier.goNext();
    notifier.goNext();
    notifier.goNext(); // tentative au-delà
    expect(container.read(veilleConfigProvider).step, 3);

    notifier.goBack();
    notifier.goBack();
    notifier.goBack(); // tentative en-dessous
    expect(container.read(veilleConfigProvider).step, 1);
  });

  test('realSelectedSourceCount ignore les sources sans apiSourceId', () {
    notifier.addCustomSourceToVeille(
      sourceId: 'src-1',
      name: 'Le Monde',
      url: 'https://lemonde.fr',
    );
    expect(container.read(veilleConfigProvider).realSelectedSourceCount, 1);
  });

  // ─── Angles LLM (PR-3) ──────────────────────────────────────────────────

  const angle = VeilleAngleSuggestionDto(
    title: 'IA générative',
    keywords: ['IA Générative', 'llm', 'chatgpt'],
    reason: 'Impact sur les workflows',
  );

  test('toggleAngle sélectionne (slug angle-, label, grappe normalisée seedée)',
      () {
    notifier.toggleAngle(angle);
    final s = container.read(veilleConfigProvider);
    final slug = VeilleConfigNotifier.angleSlug('IA générative');

    expect(slug, 'angle-ia-generative');
    expect(s.selectedSuggestions, {slug});
    expect(s.topicLabels[slug], 'IA générative');
    // Grappe normalisée : lowercase + dédupe (accents conservés, comme
    // `addKeyword` — seul le slug strippe les diacritiques).
    expect(s.angleKeywords[slug], ['ia générative', 'llm', 'chatgpt']);
  });

  test('toggleAngle re-toggle désélectionne mais conserve la grappe éditée', () {
    notifier.toggleAngle(angle);
    final slug = VeilleConfigNotifier.angleSlug(angle.title);
    notifier.addAngleKeyword(slug, 'gpt-5');

    notifier.toggleAngle(angle); // désélection
    final s = container.read(veilleConfigProvider);
    expect(s.selectedSuggestions, isEmpty);
    expect(s.angleKeywords[slug], contains('gpt-5'),
        reason: 'edits préservés pour un re-toggle');

    // Re-sélection : la grappe éditée n'est PAS écrasée par le seed initial.
    notifier.toggleAngle(angle);
    expect(container.read(veilleConfigProvider).angleKeywords[slug],
        contains('gpt-5'));
  });

  test('addAngleKeyword dédupe + cap maxAngleKeywords, removeAngleKeyword', () {
    notifier.toggleAngle(
      const VeilleAngleSuggestionDto(title: 'Vide', keywords: []),
    );
    final slug = VeilleConfigNotifier.angleSlug('Vide');

    for (var i = 0; i < VeilleConfigNotifier.maxAngleKeywords + 5; i++) {
      notifier.addAngleKeyword(slug, 'kw-$i');
    }
    expect(container.read(veilleConfigProvider).angleKeywords[slug]!.length,
        VeilleConfigNotifier.maxAngleKeywords);

    notifier.addAngleKeyword(slug, '  KW-0 '); // doublon normalisé
    expect(container.read(veilleConfigProvider).angleKeywords[slug]!.length,
        VeilleConfigNotifier.maxAngleKeywords);

    notifier.removeAngleKeyword(slug, 'kw-0');
    expect(container.read(veilleConfigProvider).angleKeywords[slug],
        isNot(contains('kw-0')));
  });

  test('_buildUpsertRequest peuple keywords sur le topic suggested de l\'angle',
      () async {
    final repo = _CaptureRepo();
    final c = ProviderContainer(
      overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    final n = c.read(veilleConfigProvider.notifier);

    n.selectTheme('tech');
    n.toggleAngle(angle);
    await n.submit();

    final slug = VeilleConfigNotifier.angleSlug(angle.title);
    final topic =
        repo.captured!.topics.firstWhere((t) => t.topicId == slug);
    expect(topic.kind, 'suggested');
    expect(topic.keywords, ['ia générative', 'llm', 'chatgpt']);
    final json = topic.toJson();
    expect(json['keywords'], ['ia générative', 'llm', 'chatgpt']);
  });

  // ─── Sujet principal granulaire (Story 23.4) ────────────────────────────

  test('selectMainTopic émet le sujet principal en position 0 (kind preset)',
      () async {
    final repo = _CaptureRepo();
    final c = ProviderContainer(
      overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    final n = c.read(veilleConfigProvider.notifier);

    n.selectTheme('tech');
    n.selectMainTopic('ai', 'Intelligence artificielle');
    // Un angle optionnel à côté, pour vérifier que le main reste en tête.
    n.toggleAngle(angle);
    await n.submit();

    final topics = repo.captured!.topics;
    expect(topics.first.topicId, 'ai');
    expect(topics.first.kind, 'preset', reason: 'slug canonique → Content.topics');
    expect(topics.first.position, 0);
    // Pas de doublon du main dans les angles.
    expect(topics.where((t) => t.topicId == 'ai').length, 1);
  });

  test('selectTheme reset le sujet principal au changement de macro', () {
    notifier.selectTheme('tech');
    notifier.selectMainTopic('ai', 'IA');
    expect(container.read(veilleConfigProvider).mainTopicSlug, 'ai');

    notifier.selectTheme('science');
    final s = container.read(veilleConfigProvider);
    expect(s.mainTopicSlug, isNull);
    expect(s.mainTopicLabel, isNull);
  });

  test('selectMainTopic re-tap désélectionne', () {
    notifier.selectTheme('tech');
    notifier.selectMainTopic('ai', 'IA');
    notifier.selectMainTopic('ai', 'IA');
    expect(container.read(veilleConfigProvider).mainTopicSlug, isNull);
  });

  test('hydrateFromActiveConfig restaure macro + sujet principal (position 0)',
      () {
    final cfg = VeilleConfigDto(
      id: 'cfg-1',
      userId: 'user-1',
      themeId: 'tech',
      themeLabel: 'Tech',
      status: 'active',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      topics: const [
        VeilleTopicDto(
          id: 't0',
          topicId: 'ai',
          label: 'IA',
          kind: 'preset',
          reason: null,
          position: 0,
          keywords: [],
        ),
        VeilleTopicDto(
          id: 't1',
          topicId: 'angle-x',
          label: 'Angle X',
          kind: 'suggested',
          reason: null,
          position: 1,
          keywords: ['gpt'],
        ),
      ],
      sources: const [],
      keywords: const [],
    );

    notifier.hydrateFromActiveConfig(cfg);
    final s = container.read(veilleConfigProvider);
    expect(s.selectedTheme, 'tech', reason: 'macro restauré');
    expect(s.mainTopicSlug, 'ai', reason: 'granulaire = topic position 0');
    expect(s.mainTopicLabel, 'IA');
    // Le sujet principal n'est PAS rejoué comme topic optionnel (sinon doublon).
    expect(s.selectedTopics, isNot(contains('ai')));
    expect(s.selectedSuggestions, contains('angle-x'));
  });
}
