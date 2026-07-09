import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_config_provider.dart';
import 'package:facteur/features/veille/providers/veille_repository_provider.dart';
import 'package:facteur/features/veille/providers/veille_themes_provider.dart';
import 'package:facteur/features/veille/repositories/veille_repository.dart';
import 'package:facteur/features/veille/screens/steps/step3_sources_screen.dart';

/// Repo factice qui capture le body d'`upsertConfig` (pour tester le mapping
/// `_buildUpsertRequest`). Toute autre méthode throw → instrumentation à fixer.
class _CaptureRepo implements VeilleRepository {
  VeilleConfigUpsertRequest? captured;
  List<VeilleResolveSourceCandidateRequest>? capturedResolveCandidates;
  VeilleResolveSourceCandidatesResponseDto resolveResponse =
      const VeilleResolveSourceCandidatesResponseDto();
  VeilleResolvedTopicDto resolvedTopic = const VeilleResolvedTopicDto(
    label: 'Musées contemporains de Barcelone',
    topicId: 'custom-musees-contemporains-de-barcelone',
    keywords: ['macba', 'exposition'],
    description: 'Suivi des expositions',
  );

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
  Future<VeilleResolvedTopicDto> resolveTopic({
    required String topic,
    String? themeId,
    String? themeLabel,
  }) async => resolvedTopic;

  @override
  Future<VeilleResolveSourceCandidatesResponseDto> resolveSourceCandidates(
    List<VeilleResolveSourceCandidateRequest> candidates,
  ) async {
    capturedResolveCandidates = candidates;
    return resolveResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
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
    expect(
      container.read(veilleConfigProvider).customThemeLabel,
      'Musées contemporains',
    );

    notifier.selectTheme('tech');
    expect(container.read(veilleConfigProvider).customThemeLabel, isNull);
  });

  test(
    'setCustomThemeLabel dérive un sujet principal (thème "Autre" sans grille)',
    () {
      notifier.selectTheme(kVeilleOtherThemeSlug);
      notifier.setCustomThemeLabel('Concert Coldplay Lyon');

      final s = container.read(veilleConfigProvider);
      expect(s.mainTopicSlug, 'custom-concert-coldplay-lyon');
      expect(s.mainTopicLabel, 'Concert Coldplay Lyon');
      expect(s.topicLabels['custom-concert-coldplay-lyon'], 'Concert Coldplay Lyon');
      expect(s.angleKeywords[s.mainTopicSlug], ['concert coldplay lyon']);

      notifier.setCustomThemeLabel(null);
      final cleared = container.read(veilleConfigProvider);
      expect(cleared.mainTopicSlug, isNull);
      expect(cleared.mainTopicLabel, isNull);
    },
  );

  test(
    'submit émet le sujet dérivé du thème "Autre" en position 0 (kind custom)',
    () async {
      final repo = _CaptureRepo();
      final c = ProviderContainer(
        overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final n = c.read(veilleConfigProvider.notifier);

      n.selectTheme(kVeilleOtherThemeSlug);
      n.setCustomThemeLabel('Concert Coldplay Lyon');
      await n.submit();

      final topics = repo.captured!.topics;
      expect(topics.first.topicId, 'custom-concert-coldplay-lyon');
      expect(topics.first.kind, 'custom');
      expect(topics.first.position, 0);
      expect(topics.first.keywords, ['concert coldplay lyon']);
    },
  );

  test('addKeyword normalise + dédupe + respecte le cap maxKeywords', () {
    for (var i = 0; i < VeilleConfigNotifier.maxKeywords + 5; i++) {
      notifier.addKeyword('kw-$i');
    }
    final keywords = container.read(veilleConfigProvider).keywords;
    expect(keywords.length, VeilleConfigNotifier.maxKeywords);

    notifier.addKeyword('  KW-0  '); // doublon normalisé
    expect(
      container.read(veilleConfigProvider).keywords.length,
      VeilleConfigNotifier.maxKeywords,
    );
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
    expect(
      container.read(veilleConfigProvider).resolvedThemeLabel('Autre'),
      'Musées',
    );
  });

  test(
    'resolvedThemeLabel fallback quand customThemeLabel vide en mode other',
    () {
      notifier.selectTheme(kVeilleOtherThemeSlug);
      expect(
        container.read(veilleConfigProvider).resolvedThemeLabel('Autre'),
        'Autre',
      );
    },
  );

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

  test('source suggérée est présélectionnée pending et ne compte pas CTA', () {
    notifier.addCustomSourceToVeille(
      sourceId: 'src-1',
      name: 'Le Monde',
      url: 'https://lemonde.fr',
    );
    notifier.registerSuggestedSources(const [
      VeilleSourceSuggestionDto(
        name: 'MACBA',
        url: 'https://www.macba.cat',
        why: 'Musée officiel',
        relevanceScore: 1,
      ),
    ]);
    final slug = VeilleConfigNotifier.sourceSuggestionSlug(
      'MACBA',
      'https://www.macba.cat',
    );
    final s = container.read(veilleConfigProvider);

    expect(s.selectedSourceIds, contains(slug));
    expect(
      s.sourcesMeta[slug]!.connectionStatus,
      VeilleSourceConnectionStatus.pending,
    );
    expect(s.realSelectedSourceCount, 1);
  });

  test(
    'resolvePendingSources marque les candidats résolus connected',
    () async {
      final repo = _CaptureRepo();
      repo.resolveResponse = const VeilleResolveSourceCandidatesResponseDto(
        resolved: [
          VeilleResolvedSourceCandidateDto(
            clientSlug: 'niche-wwwmacbacat-macba',
            sourceId: 'src-macba',
            name: 'MACBA',
            url: 'https://www.macba.cat',
            feedUrl: 'https://www.macba.cat/feed.xml',
            logoUrl: 'https://logo.test/macba.png',
          ),
        ],
      );
      final c = ProviderContainer(
        overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final n = c.read(veilleConfigProvider.notifier);

      n.registerSuggestedSources(const [
        VeilleSourceSuggestionDto(
          name: 'MACBA',
          url: 'https://www.macba.cat',
          why: 'Musée officiel',
          relevanceScore: 1,
        ),
      ]);
      final slug = VeilleConfigNotifier.sourceSuggestionSlug(
        'MACBA',
        'https://www.macba.cat',
      );
      await n.resolvePendingSources();

      final s = c.read(veilleConfigProvider);
      expect(repo.capturedResolveCandidates!.single.clientSlug, slug);
      expect(s.sourcesMeta[slug]!.apiSourceId, 'src-macba');
      expect(
        s.sourcesMeta[slug]!.connectionStatus,
        VeilleSourceConnectionStatus.connected,
      );
      expect(s.realSelectedSourceCount, 1);
    },
  );

  test('resolvePendingSources désélectionne les candidats KO', () async {
    final repo = _CaptureRepo();
    final slug = VeilleConfigNotifier.sourceSuggestionSlug(
      'MACBA',
      'https://www.macba.cat',
    );
    repo.resolveResponse = VeilleResolveSourceCandidatesResponseDto(
      failed: [
        VeilleFailedSourceCandidateDto(
          clientSlug: slug,
          name: 'MACBA',
          url: 'https://www.macba.cat',
          reason: 'Aucun flux RSS.',
        ),
      ],
    );
    final c = ProviderContainer(
      overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    final n = c.read(veilleConfigProvider.notifier);

    n.registerSuggestedSources(const [
      VeilleSourceSuggestionDto(
        name: 'MACBA',
        url: 'https://www.macba.cat',
        why: 'Musée officiel',
        relevanceScore: 1,
      ),
    ]);
    await n.resolvePendingSources();

    final s = c.read(veilleConfigProvider);
    expect(s.selectedSourceIds, isNot(contains(slug)));
    expect(
      s.sourcesMeta[slug]!.connectionStatus,
      VeilleSourceConnectionStatus.failed,
    );
    expect(s.lastError, contains("n'a pas pu être connectée"));
  });

  test('submit sérialise un candidat résolu en source_id', () async {
    final repo = _CaptureRepo();
    final slug = VeilleConfigNotifier.sourceSuggestionSlug(
      'MACBA',
      'https://www.macba.cat',
    );
    repo.resolveResponse = VeilleResolveSourceCandidatesResponseDto(
      resolved: [
        VeilleResolvedSourceCandidateDto(
          clientSlug: slug,
          sourceId: 'src-macba',
          name: 'MACBA',
          url: 'https://www.macba.cat',
          feedUrl: 'https://www.macba.cat/feed.xml',
        ),
      ],
    );
    final c = ProviderContainer(
      overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    final n = c.read(veilleConfigProvider.notifier);

    n.selectTheme('culture');
    n.selectMainTopic('museums', 'Musées');
    n.registerSuggestedSources(const [
      VeilleSourceSuggestionDto(
        name: 'MACBA',
        url: 'https://www.macba.cat',
        why: 'Musée officiel',
        relevanceScore: 1,
      ),
    ]);
    await n.resolvePendingSources();
    await n.submit();

    final source = repo.captured!.sourceSelections.single;
    expect(source.kind, 'niche');
    expect(source.sourceId, 'src-macba');
    expect(source.nicheCandidate, isNull);
    expect(source.toJson()['source_id'], 'src-macba');
  });

  test('addUrlSourceToVeille ajoute une source niche locale sélectionnée', () {
    notifier.addUrlSourceToVeille(
      name: 'Blog niche',
      url: 'https://example.com/rss.xml',
      why: 'Flux spécialisé',
    );

    final s = container.read(veilleConfigProvider);
    final slug = VeilleConfigNotifier.sourceSuggestionSlug(
      'Blog niche',
      'https://example.com/rss.xml',
    );
    expect(s.selectedSourceIds, contains(slug));
    expect(s.sourcesMeta[slug]!.kind, 'niche');
    expect(s.sourcesMeta[slug]!.apiSourceId, isNull);
    expect(s.sourcesMeta[slug]!.url, 'https://example.com/rss.xml');
  });

  test('buildSuggestionQuery borne angles et mots-clés au cap suggester', () {
    notifier.selectTheme('tech');
    notifier.selectMainTopic('ai', 'Intelligence artificielle');

    for (var i = 0; i < VeilleConfigNotifier.maxKeywords; i++) {
      notifier.addKeyword('global-$i');
    }
    for (var i = 0; i < 25; i++) {
      notifier.toggleAngle(
        VeilleAngleSuggestionDto(
          title: 'Angle $i',
          keywords: [for (var j = 0; j < 10; j++) 'kw-$i-$j'],
        ),
      );
    }

    final query = buildSuggestionQuery(container.read(veilleConfigProvider))!;
    final angles = query.anglesKey.split('|');
    final keywords = query.keywordsKey.split('|');

    expect(angles.length, VeilleConfigNotifier.maxSuggestAngles);
    expect(keywords.length, VeilleConfigNotifier.maxSuggestKeywords);
    expect(angles.first, 'Intelligence artificielle');
    expect(keywords.take(2), ['global-0', 'global-1']);
  });

  // ─── Angles LLM (PR-3) ──────────────────────────────────────────────────

  const angle = VeilleAngleSuggestionDto(
    title: 'IA générative',
    keywords: ['IA Générative', 'llm', 'chatgpt'],
    reason: 'Impact sur les workflows',
  );

  test(
    'toggleAngle sélectionne (slug angle-, label, grappe normalisée seedée)',
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
    },
  );

  test(
    'toggleAngle re-toggle désélectionne mais conserve la grappe éditée',
    () {
      notifier.toggleAngle(angle);
      final slug = VeilleConfigNotifier.angleSlug(angle.title);
      notifier.addAngleKeyword(slug, 'gpt-5');

      notifier.toggleAngle(angle); // désélection
      final s = container.read(veilleConfigProvider);
      expect(s.selectedSuggestions, isEmpty);
      expect(
        s.angleKeywords[slug],
        contains('gpt-5'),
        reason: 'edits préservés pour un re-toggle',
      );

      // Re-sélection : la grappe éditée n'est PAS écrasée par le seed initial.
      notifier.toggleAngle(angle);
      expect(
        container.read(veilleConfigProvider).angleKeywords[slug],
        contains('gpt-5'),
      );
    },
  );

  test('addAngleKeyword dédupe + cap maxAngleKeywords, removeAngleKeyword', () {
    notifier.toggleAngle(
      const VeilleAngleSuggestionDto(title: 'Vide', keywords: []),
    );
    final slug = VeilleConfigNotifier.angleSlug('Vide');

    for (var i = 0; i < VeilleConfigNotifier.maxAngleKeywords + 5; i++) {
      notifier.addAngleKeyword(slug, 'kw-$i');
    }
    expect(
      container.read(veilleConfigProvider).angleKeywords[slug]!.length,
      VeilleConfigNotifier.maxAngleKeywords,
    );

    notifier.addAngleKeyword(slug, '  KW-0 '); // doublon normalisé
    expect(
      container.read(veilleConfigProvider).angleKeywords[slug]!.length,
      VeilleConfigNotifier.maxAngleKeywords,
    );

    notifier.removeAngleKeyword(slug, 'kw-0');
    expect(
      container.read(veilleConfigProvider).angleKeywords[slug],
      isNot(contains('kw-0')),
    );
  });

  test(
    '_buildUpsertRequest peuple keywords sur le topic suggested de l\'angle',
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
      final topic = repo.captured!.topics.firstWhere((t) => t.topicId == slug);
      expect(topic.kind, 'suggested');
      expect(topic.keywords, ['ia générative', 'llm', 'chatgpt']);
      final json = topic.toJson();
      expect(json['keywords'], ['ia générative', 'llm', 'chatgpt']);
    },
  );

  // ─── Sujet principal granulaire (Story 23.4) ────────────────────────────

  test(
    'selectMainTopic émet le sujet principal en position 0 (kind preset)',
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
      expect(
        topics.first.kind,
        'preset',
        reason: 'slug canonique → Content.topics',
      );
      expect(topics.first.position, 0);
      // Pas de doublon du main dans les angles.
      expect(topics.where((t) => t.topicId == 'ai').length, 1);
    },
  );

  test('selectTheme reset le sujet principal au changement de macro', () {
    notifier.selectTheme('tech');
    notifier.selectMainTopic('ai', 'IA');
    expect(container.read(veilleConfigProvider).mainTopicSlug, 'ai');

    notifier.selectTheme('science');
    final s = container.read(veilleConfigProvider);
    expect(s.mainTopicSlug, isNull);
    expect(s.mainTopicLabel, isNull);
  });

  test(
    'selectTheme vide angles/sources/mots-clés du thème précédent '
    '(édition pénible — feedback PO)',
    () {
      notifier.selectTheme('tech');
      notifier.selectMainTopic('ai', 'IA');
      notifier.addKeyword('llm');
      notifier.toggleAngle(angle);
      notifier.addUrlSourceToVeille(
        name: 'Blog niche',
        url: 'https://example.com/rss.xml',
      );
      notifier.registerSuggestedSources(const [
        VeilleSourceSuggestionDto(
          name: 'MACBA',
          url: 'https://www.macba.cat',
          why: 'Musée officiel',
          relevanceScore: 1,
        ),
      ]);
      final s0 = container.read(veilleConfigProvider);
      expect(s0.selectedSuggestions, isNotEmpty);
      expect(s0.selectedSourceIds, isNotEmpty);
      expect(s0.keywords, isNotEmpty);
      expect(s0.angleKeywords, isNotEmpty);

      notifier.selectTheme('sport');
      final s1 = container.read(veilleConfigProvider);
      expect(s1.selectedSuggestions, isEmpty);
      expect(s1.selectedSourceIds, isEmpty);
      expect(s1.sourcesMeta, isEmpty);
      expect(s1.keywords, isEmpty);
      expect(s1.angleKeywords, isEmpty);
      expect(s1.angleSuggestionsRequested, isTrue);
      expect(s1.sourceSuggestionsRequested, isTrue);
    },
  );

  test('selectMainTopic re-tap désélectionne', () {
    notifier.selectTheme('tech');
    notifier.selectMainTopic('ai', 'IA');
    notifier.selectMainTopic('ai', 'IA');
    expect(container.read(veilleConfigProvider).mainTopicSlug, isNull);
  });

  test(
    'resolveCustomMainTopic enrichit un sujet local veille en main custom',
    () async {
      final repo = _CaptureRepo();
      final c = ProviderContainer(
        overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final n = c.read(veilleConfigProvider.notifier);

      n.selectTheme('culture');
      await n.resolveCustomMainTopic('musées barcelone');

      final s = c.read(veilleConfigProvider);
      expect(s.mainTopicSlug, 'custom-musees-contemporains-de-barcelone');
      expect(s.mainTopicLabel, 'Musées contemporains de Barcelone');
      expect(s.angleKeywords[s.mainTopicSlug], ['macba', 'exposition']);
      expect(s.customTopics.single.id, s.mainTopicSlug);
    },
  );

  test(
    'hydrateFromActiveConfig restaure macro + sujet principal (position 0)',
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
    },
  );

  // ─── Fix « sujet non sauvegardé » sur le chemin "Autre"/free-text ─────────

  test('setCustomThemeLabel vidé remet mainTopicSlug/Label à null', () {
    notifier.selectTheme(kVeilleOtherThemeSlug);
    notifier.setCustomThemeLabel('Concert de jazz');
    notifier.setCustomThemeLabel('   '); // effacement
    final s = container.read(veilleConfigProvider);
    expect(s.customThemeLabel, isNull);
    expect(s.mainTopicSlug, isNull);
    expect(s.mainTopicLabel, isNull);
  });

  test(
    'thème Autre + brief seul → topic position 0 custom persisté au submit',
    () async {
      final repo = _CaptureRepo();
      final c = ProviderContainer(
        overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final n = c.read(veilleConfigProvider.notifier);

      n.selectTheme(kVeilleOtherThemeSlug);
      n.setCustomThemeLabel('Concert de jazz');
      n.setEditorialBrief('Les meilleurs concerts à Paris');
      await n.submit();

      final topic = repo.captured!.topics.first;
      expect(topic.position, 0);
      expect(topic.topicId, 'custom-concert-de-jazz');
      expect(topic.kind, 'custom');
      expect(topic.label, 'Concert de jazz');
    },
  );

  test(
    'hydrateFromActiveConfig restaure customThemeLabel pour un thème Autre',
    () {
      final cfg = VeilleConfigDto(
        id: 'cfg-1',
        userId: 'user-1',
        themeId: kVeilleOtherThemeSlug,
        themeLabel: 'Concert de jazz',
        status: 'active',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        topics: const [
          VeilleTopicDto(
            id: 't0',
            topicId: 'custom-concert-de-jazz',
            label: 'Concert de jazz',
            kind: 'custom',
            reason: null,
            position: 0,
            keywords: [],
          ),
        ],
        sources: const [],
        keywords: const [],
      );

      notifier.hydrateFromActiveConfig(cfg);
      final s = container.read(veilleConfigProvider);
      expect(s.selectedTheme, kVeilleOtherThemeSlug);
      expect(s.customThemeLabel, 'Concert de jazz', reason: 'champ Step 1 rempli');
      expect(s.mainTopicSlug, 'custom-concert-de-jazz');
      expect(s.mainTopicLabel, 'Concert de jazz');
    },
  );

  // ─── Fix UX : changer de thème réinitialise angles/sources/mots-clés ──────

  test('selectTheme vide angles/sources/keywords + réarme les suggestions', () {
    // Scénario réel : on édite une config 'tech' existante (hydrate met les
    // flags de suggestion à false), puis on change de thème.
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
      ],
      sources: const [],
      keywords: const [],
    );
    notifier.hydrateFromActiveConfig(cfg);
    // Sélections du thème 'tech' dans tous les buckets.
    notifier.toggleAngle(
      const VeilleAngleSuggestionDto(
        title: 'Startups',
        keywords: ['seed', 'levée'],
      ),
    );
    notifier.addKeyword('gpt');
    notifier.addCustomSourceToVeille(
      sourceId: 'src-1',
      name: 'Le Monde',
      url: 'https://lemonde.fr',
    );
    var s = container.read(veilleConfigProvider);
    expect(s.angleSuggestionsRequested, isFalse, reason: 'édition = flags off');
    expect(s.selectedSuggestions, isNotEmpty);
    expect(s.selectedSourceIds, isNotEmpty);
    expect(s.keywords, isNotEmpty);

    notifier.selectTheme('culture');

    s = container.read(veilleConfigProvider);
    expect(s.selectedTheme, 'culture');
    expect(s.mainTopicSlug, isNull);
    expect(s.selectedSuggestions, isEmpty);
    expect(s.selectedSourceIds, isEmpty);
    expect(s.sourcesMeta, isEmpty);
    expect(s.keywords, isEmpty);
    expect(s.angleKeywords, isEmpty);
    expect(s.angleSuggestionsRequested, isTrue, reason: 'refetch réarmé');
    expect(s.sourceSuggestionsRequested, isTrue, reason: 'refetch réarmé');
  });
}
