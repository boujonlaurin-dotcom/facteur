import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // formatFrenchLongDate
  // ---------------------------------------------------------------------------
  group('formatFrenchLongDate', () {
    test('lundi (1er janvier 2024)', () {
      expect(formatFrenchLongDate(DateTime(2024, 1, 1)), 'lundi 1 janvier');
    });

    test('mercredi 27 mai (exemple PO)', () {
      expect(formatFrenchLongDate(DateTime(2026, 5, 27)), 'mercredi 27 mai');
    });

    test('mois accentués (février, août)', () {
      expect(formatFrenchLongDate(DateTime(2024, 2, 29)), 'jeudi 29 février');
      expect(formatFrenchLongDate(DateTime(2024, 8, 15)), 'jeudi 15 août');
    });

    test('décembre', () {
      expect(formatFrenchLongDate(DateTime(2024, 12, 25)), 'mercredi 25 décembre');
    });
  });

  // ---------------------------------------------------------------------------
  // editionSummaryEntries
  // ---------------------------------------------------------------------------
  group('editionSummaryEntries', () {
    EssentielSection hero() =>
        const EssentielSection(articles: <EssentielArticle>[]);

    FeedThemeSection theme(
      String label, {
      SectionOrigin origin = SectionOrigin.validated,
    }) =>
        FeedThemeSection(
          kind: SectionKind.theme,
          label: label,
          accent: const Color(0xFF2C3E50),
          coreVisibleCount: 3,
          themeSlug: 'slug-$label',
          items: const <Content>[],
          origin: origin,
        );

    DigestTopicSection digest(String label, SectionKind kind) =>
        DigestTopicSection(
          kind: kind,
          label: label,
          accent: const Color(0xFFB0470A),
          coreVisibleCount: 3,
          topics: const <DigestTopic>[],
        );

    test('exclut le héros, garde l\'ordre du feed, libellés exacts', () {
      final sections = <FluxSection>[
        hero(),
        theme('Technologie'),
        digest('Actus du jour', SectionKind.essentiel),
        digest('Bonnes Nouvelles', SectionKind.bonnes),
      ];
      expect(
        editionSummaryEntries(sections),
        ['Technologie', 'Actus du jour', 'Bonnes Nouvelles'],
      );
    });

    test('insère « Mot du jour » à grilleSlotIndex (après Actus)', () {
      final sections = <FluxSection>[
        hero(),
        theme('Technologie'),
        digest('Actus du jour', SectionKind.essentiel),
        digest('Bonnes Nouvelles', SectionKind.bonnes),
      ];
      // La Grille ancrée juste avant « Bonnes Nouvelles » (index 3).
      expect(
        editionSummaryEntries(sections, grilleSlotIndex: 3),
        ['Technologie', 'Actus du jour', 'Mot du jour', 'Bonnes Nouvelles'],
      );
    });

    test('« Mot du jour » ajouté en fin quand grilleSlotIndex == length', () {
      final sections = <FluxSection>[hero(), theme('Technologie')];
      expect(
        editionSummaryEntries(sections, grilleSlotIndex: sections.length),
        ['Technologie', 'Mot du jour'],
      );
    });

    test('aucun « Mot du jour » quand grilleSlotIndex est null', () {
      final sections = <FluxSection>[hero(), theme('Technologie')];
      expect(editionSummaryEntries(sections), ['Technologie']);
    });

    test('inclut les sections suggérées (Choisie pour vous)', () {
      final sections = <FluxSection>[
        hero(),
        theme('Cinéma', origin: SectionOrigin.suggested),
        digest('Actus du jour', SectionKind.essentiel),
      ];
      expect(
        editionSummaryEntries(sections),
        ['Cinéma', 'Actus du jour'],
      );
    });

    test('liste vide quand seul le héros est présent', () {
      expect(editionSummaryEntries(<FluxSection>[hero()]), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // isEditionReady
  // ---------------------------------------------------------------------------
  group('isEditionReady', () {
    // Mardi midi (après la bascule 7h30) : dayKey == ce jour.
    final now = DateTime.utc(2026, 6, 23, 12);
    final today = DateTime.utc(2026, 6, 23, 12);
    final yesterday = DateTime.utc(2026, 6, 22, 12);

    FeedThemeSection section() => const FeedThemeSection(
          kind: SectionKind.theme,
          label: 'Technologie',
          accent: Color(0xFF2C3E50),
          coreVisibleCount: 3,
          themeSlug: 'tech',
          items: <Content>[],
        );

    FluxContinuState state({
      List<FluxSection>? sections,
      bool skeleton = false,
    }) =>
        FluxContinuState(
          sections: sections ?? <FluxSection>[section()],
          isSkeleton: skeleton,
        );

    DigestResponse digestResp({
      DateTime? targetDate,
      bool stale = false,
      bool withContent = true,
    }) =>
        DigestResponse(
          digestId: 'd',
          userId: 'u',
          targetDate: targetDate ?? today,
          generatedAt: DateTime.utc(2026, 6, 23, 7),
          topics: withContent
              ? [
                  const DigestTopic(
                    topicId: 't',
                    label: 'Actus',
                    articles: <DigestItem>[],
                  ),
                ]
              : const <DigestTopic>[],
          isStaleFallback: stale,
        );

    test('prête : flux + digest frais du jour', () {
      expect(isEditionReady(state(), digestResp(), now: now), isTrue);
    });

    // Régression : le backend renvoie `target_date` date-nue → minuit local.
    // L'ancien gate la repassait dans `dayKey()` (bascule 7h30) qui rabattait
    // tout minuit sur la veille → édition jamais prête (bug E2E 24/06).
    test('target_date à minuit du jour (date-nue backend) → prête', () {
      expect(
        isEditionReady(
          state(),
          digestResp(targetDate: DateTime(2026, 6, 23)),
          now: now,
        ),
        isTrue,
      );
    });

    test('squelette → pas prête', () {
      expect(
        isEditionReady(state(skeleton: true), digestResp(), now: now),
        isFalse,
      );
    });

    test('sections vides → pas prête', () {
      expect(
        isEditionReady(state(sections: const []), digestResp(), now: now),
        isFalse,
      );
    });

    test('stale fallback → pas prête', () {
      expect(
        isEditionReady(state(), digestResp(stale: true), now: now),
        isFalse,
      );
    });

    test('digest d\'hier (mauvais jour) → pas prête', () {
      expect(
        isEditionReady(state(), digestResp(targetDate: yesterday), now: now),
        isFalse,
      );
    });

    test('digest sans contenu → pas prête', () {
      expect(
        isEditionReady(state(), digestResp(withContent: false), now: now),
        isFalse,
      );
    });

    test('état/digest null → pas prête', () {
      expect(isEditionReady(null, digestResp(), now: now), isFalse);
      expect(isEditionReady(state(), null, now: now), isFalse);
    });
  });
}
