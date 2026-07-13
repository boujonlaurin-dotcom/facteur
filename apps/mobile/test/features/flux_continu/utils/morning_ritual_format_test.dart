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

    test('digest présent mais sans contenu → prête (le flux fait foi)', () {
      // Le contenu vient du flux (sections), pas du digest : un digest non
      // périmé et du bon jour ne bloque pas, même vide.
      expect(
        isEditionReady(state(), digestResp(withContent: false), now: now),
        isTrue,
      );
    });

    test('flux prête + digest null (non préchargé) → prête', () {
      // Régression bug E2E 24/06 : le digest est chargé séparément et vaut
      // `null` les premières secondes sur /edition. Il ne doit JAMAIS bloquer la
      // révélation — sinon le rituel ne s'affiche jamais avec son bouton.
      expect(isEditionReady(state(), null, now: now), isTrue);
    });

    test('flux absent → pas prête (même digest frais)', () {
      expect(isEditionReady(null, digestResp(), now: now), isFalse);
    });
  });

}
