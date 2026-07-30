import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/screens/flux_continu_screen.dart';
import 'package:facteur/features/sources/models/source_model.dart';

/// Garde-fou du libellé d'attente « Ta tournée se prépare… ». Le test widget de
/// `SectionBlock` couvre `showPreparingLabel: true/false` **en isolation** : il
/// n'a donc pas pu attraper la suppression accidentelle du calcul d'index côté
/// écran (build mobile cassé sur `main`). Ce fichier couvre l'autre moitié : sur
/// une Tournée partiellement résolue, **une seule** coquille est désignée.
///
/// Monter `FluxContinuScreen` entier n'est pas jouable en test unitaire
/// (Supabase, Hive et GoRouter y sont requis) — d'où le helper top-level
/// `firstPreparingSectionIndex`, référencé ici : le supprimer casse la
/// compilation du test, pas seulement celle de l'app.

FeedThemeSection _resolvedTheme(String slug) => FeedThemeSection(
      kind: SectionKind.theme,
      label: 'Thème $slug',
      accent: const Color(0xFF1565C0),
      coreVisibleCount: 5,
      themeSlug: slug,
      items: [
        Content(
          id: '$slug-1',
          title: 'titre-$slug',
          url: 'https://x/$slug/1',
          contentType: ContentType.article,
          publishedAt: DateTime(2026, 1, 1),
          source: Source(id: 's', name: 'S', type: SourceType.article),
        ),
      ],
    );

FeedThemeSection _placeholderTheme(String slug) => FeedThemeSection(
      kind: SectionKind.theme,
      label: 'Thème $slug',
      accent: const Color(0xFF1565C0),
      coreVisibleCount: 5,
      themeSlug: slug,
      items: const <Content>[],
      hasMore: false,
      isPlaceholder: true,
    );

void main() {
  group('firstPreparingSectionIndex', () {
    test('désigne la première coquille et une seule', () {
      // 1 section résolue puis 2 coquilles : seul l'index 1 porte le libellé.
      final sections = <FluxSection>[
        _resolvedTheme('tech'),
        _placeholderTheme('monde'),
        _placeholderTheme('sport'),
      ];
      final designated = firstPreparingSectionIndex(sections);

      expect(designated, 1);
      // Exactement une section désignée sur toute la Tournée : échoue si le
      // libellé disparaît (-1) comme s'il se duplique sur chaque coquille.
      final labelled = [
        for (var i = 0; i < sections.length; i++)
          if (i == designated) i,
      ];
      expect(labelled, hasLength(1));
    });

    test('aucune coquille → aucun libellé', () {
      expect(
        firstPreparingSectionIndex([_resolvedTheme('tech')]),
        -1,
      );
      expect(firstPreparingSectionIndex(const []), -1);
    });

    test('une Tournée entièrement en coquilles ne désigne que la première', () {
      expect(
        firstPreparingSectionIndex([
          _placeholderTheme('monde'),
          _placeholderTheme('sport'),
        ]),
        0,
      );
    });
  });
}
