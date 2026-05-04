import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config.dart';
import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_config_provider.dart';

void main() {
  group('VeilleConfigNotifier — purpose + brief setters (PR B)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('setPurpose stores slug', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setPurpose('preparer_projet');
      expect(container.read(veilleConfigProvider).purpose, 'preparer_projet');
    });

    test('setPurpose to non-autre clears purposeOther', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setPurpose('autre');
      notifier.setPurposeOther('rédiger un livre');
      expect(container.read(veilleConfigProvider).purposeOther, 'rédiger un livre');

      notifier.setPurpose('culture_generale');
      expect(container.read(veilleConfigProvider).purpose, 'culture_generale');
      expect(container.read(veilleConfigProvider).purposeOther, isNull);
    });

    test('setPurpose to autre keeps purposeOther', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setPurpose('autre');
      notifier.setPurposeOther('rédiger un livre');
      // Re-set purpose to autre — purposeOther doit rester (re-tap UX).
      notifier.setPurpose('autre');
      expect(container.read(veilleConfigProvider).purposeOther, 'rédiger un livre');
    });

    test('setEditorialBrief trims and treats empty as null', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setEditorialBrief('  Plutôt analyses long format  ');
      expect(
        container.read(veilleConfigProvider).editorialBrief,
        'Plutôt analyses long format',
      );

      notifier.setEditorialBrief('   ');
      expect(container.read(veilleConfigProvider).editorialBrief, isNull);
    });

    test('setPurposeOther trims and treats empty as null', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.setPurpose('autre');
      notifier.setPurposeOther('  veille perso  ');
      expect(container.read(veilleConfigProvider).purposeOther, 'veille perso');

      notifier.setPurposeOther('');
      expect(container.read(veilleConfigProvider).purposeOther, isNull);
    });
  });

  group('VeilleConfigNotifier — hydrateFromActiveConfig (T3 edit mode)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    VeilleConfigDto buildDto({
      String frequency = 'biweekly',
      int? dayOfWeek = 3,
    }) {
      final now = DateTime.utc(2026, 5, 4);
      return VeilleConfigDto(
        id: 'cfg-1',
        userId: 'user-1',
        themeId: 'education',
        themeLabel: 'Éducation',
        frequency: frequency,
        dayOfWeek: dayOfWeek,
        deliveryHour: 7,
        timezone: 'Europe/Paris',
        status: 'active',
        lastDeliveredAt: null,
        nextScheduledAt: now,
        createdAt: now,
        updatedAt: now,
        topics: const [
          VeilleTopicDto(
            id: 't-1',
            topicId: 'evaluations',
            label: 'Évaluations',
            kind: 'preset',
            reason: null,
            position: 0,
          ),
          VeilleTopicDto(
            id: 't-2',
            topicId: 'custom-cnl',
            label: 'CNL',
            kind: 'custom',
            reason: 'sujet ajouté',
            position: 1,
          ),
          VeilleTopicDto(
            id: 't-3',
            topicId: 'didactique-numerique',
            label: 'Didactique numérique',
            kind: 'suggested',
            reason: null,
            position: 2,
          ),
        ],
        sources: const [
          VeilleSourceDto(
            id: 'vs-1',
            source: VeilleSourceLiteDto(
              id: 'src-followed-1',
              name: 'Café Pédago',
              url: 'https://cafe.example.com',
              feedUrl: 'https://cafe.example.com/feed',
              theme: 'education',
              type: 'rss',
              isCurated: true,
              logoUrl: null,
            ),
            kind: 'followed',
            why: null,
            position: 0,
          ),
          VeilleSourceDto(
            id: 'vs-2',
            source: VeilleSourceLiteDto(
              id: 'src-niche-1',
              name: 'NicheBlog',
              url: 'https://niche.example.com',
              feedUrl: 'https://niche.example.com/feed',
              theme: 'education',
              type: 'rss',
              isCurated: false,
              logoUrl: null,
            ),
            kind: 'niche',
            why: 'spécialiste des évals',
            position: 1,
          ),
        ],
        purpose: 'culture_generale',
        purposeOther: null,
        editorialBrief: 'Plutôt analyses long format',
        presetId: 'preset-edu',
      );
    }

    test('populates state from dto (theme, topics, sources, frequency, day, purpose)',
        () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.hydrateFromActiveConfig(buildDto());
      final s = container.read(veilleConfigProvider);

      expect(s.step, 1);
      expect(s.selectedTheme, 'education');
      expect(s.selectedTopics, containsAll(['evaluations', 'custom-cnl']));
      expect(s.selectedSuggestions, contains('didactique-numerique'));
      expect(s.customTopics.map((t) => t.id), contains('custom-cnl'));
      expect(s.topicLabels['custom-cnl'], 'CNL');
      expect(s.selectedSourceIds, contains('src-followed-1'));
      expect(s.selectedSourceIds, contains('src-niche-1'));
      expect(s.sourcesMeta['src-niche-1']?.kind, 'niche');
      expect(s.sourcesMeta['src-niche-1']?.apiSourceId, 'src-niche-1');
      expect(s.frequency, VeilleFrequency.biweekly);
      expect(s.day, VeilleDay.thu); // dayOfWeek=3 → jeu
      expect(s.purpose, 'culture_generale');
      expect(s.editorialBrief, 'Plutôt analyses long format');
      expect(s.presetId, 'preset-edu');
    });

    test('idempotent — second call no-op when selectedTheme already set', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.hydrateFromActiveConfig(buildDto());
      final s1 = container.read(veilleConfigProvider);

      // Tente une 2e hydratation avec un dto différent — doit être ignorée.
      notifier.hydrateFromActiveConfig(
        buildDto(frequency: 'monthly', dayOfWeek: null),
      );
      final s2 = container.read(veilleConfigProvider);

      expect(s2.frequency, s1.frequency); // pas écrasé
      expect(s2.day, s1.day);
    });

    test('monthly frequency maps day to default mon (no dayOfWeek)', () {
      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.hydrateFromActiveConfig(
        buildDto(frequency: 'monthly', dayOfWeek: null),
      );
      final s = container.read(veilleConfigProvider);
      expect(s.frequency, VeilleFrequency.monthly);
      expect(s.day, VeilleDay.mon);
    });
  });
}
