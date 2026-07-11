import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/utils/theme_color_mapping.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FeedThemeSection _feedSection({
  required SectionKind kind,
  String? themeSlug,
}) =>
    FeedThemeSection(
      kind: kind,
      label: 'X',
      accent: const Color(0xFF000000),
      coreVisibleCount: 5,
      themeSlug: themeSlug,
      items: const [],
    );

void main() {
  group('visualFor', () {
    test('returns the matching ThemeVisual for known slugs', () {
      final tech = visualFor('tech');
      expect(tech.label, 'Technologie');
      final env = visualFor('environment');
      expect(env.label, 'Environnement');
    });

    test('falls back to a neutral "Veille" visual for unknown slugs', () {
      final unknown = visualFor('not-a-real-theme');
      expect(unknown.label, 'Veille');
    });

    test('covers the 9 valid Facteur themes', () {
      const validSlugs = {
        'tech',
        'society',
        'environment',
        'economy',
        'politics',
        'culture',
        'science',
        'international',
        'sport',
      };
      for (final slug in validSlugs) {
        expect(
          themeMap.containsKey(slug),
          isTrue,
          reason: 'themeMap should contain "$slug" (valid Facteur theme)',
        );
      }
    });
  });

  test('fallback slugs are valid Facteur theme slugs', () {
    expect(themeMap.containsKey(fallbackTheme1), isTrue);
    expect(themeMap.containsKey(fallbackTheme2), isTrue);
    expect(fallbackTheme1, isNot(equals(fallbackTheme2)));
  });

  group('sectionEmoji', () {
    test('Essentiel → 📰 (repli éditorial)', () {
      expect(sectionEmoji(const EssentielSection(articles: [])), '📰');
    });

    test('Bonnes Nouvelles → 🌱, Actus → 📰', () {
      expect(
        sectionEmoji(const DigestTopicSection(
          kind: SectionKind.bonnes,
          label: 'Bonnes Nouvelles',
          accent: Color(0xFF000000),
          coreVisibleCount: 3,
          topics: [],
        )),
        '🌱',
      );
      expect(
        sectionEmoji(const DigestTopicSection(
          kind: SectionKind.essentiel,
          label: 'Actus du jour',
          accent: Color(0xFF000000),
          coreVisibleCount: 3,
          topics: [],
        )),
        '📰',
      );
    });

    test('Veille → 🔭', () {
      expect(sectionEmoji(_feedSection(kind: SectionKind.veille)), '🔭');
    });

    test('thème connu → emoji dédié, thème inconnu → repli 📰', () {
      expect(
        sectionEmoji(_feedSection(kind: SectionKind.theme, themeSlug: 'tech')),
        '💻',
      );
      expect(
        sectionEmoji(
            _feedSection(kind: SectionKind.theme, themeSlug: 'not-a-theme')),
        '📰',
      );
    });

    test('un emoji est défini pour chacun des 9 thèmes', () {
      for (final slug in themeMap.keys) {
        expect(themeEmoji.containsKey(slug), isTrue,
            reason: 'themeEmoji devrait couvrir "$slug"');
      }
    });
  });
}
