import 'package:facteur/features/flux_continu/utils/theme_color_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
