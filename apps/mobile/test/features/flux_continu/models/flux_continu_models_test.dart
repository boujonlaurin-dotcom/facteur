import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Section.articleId', () {
    test('extracts content_id from DigestItem', () {
      final item = DigestItem(contentId: 'abc-123', title: 't', rank: 1);
      expect(Section.articleId(item), 'abc-123');
    });

    test('extracts id from Content', () {
      final content = Content(
        id: 'def-456',
        title: 't',
        url: 'https://x.test',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 1, 1),
        source: Source(id: 's', name: 'S', type: SourceType.article),
      );
      expect(Section.articleId(content), 'def-456');
    });

    test('returns empty string for unknown types', () {
      expect(Section.articleId('not-an-article'), '');
    });
  });

  group('FluxContinuState', () {
    test('isOpen defaults to false for any section', () {
      const state = FluxContinuState();
      expect(state.isOpen(SectionKind.essentiel), isFalse);
      expect(state.isOpen(SectionKind.bonnes), isFalse);
      expect(state.isOpen(SectionKind.theme1), isFalse);
      expect(state.isOpen(SectionKind.theme2), isFalse);
    });

    test('isOpen reads from moreOpen map', () {
      const state = FluxContinuState(moreOpen: {SectionKind.bonnes: true});
      expect(state.isOpen(SectionKind.bonnes), isTrue);
      expect(state.isOpen(SectionKind.essentiel), isFalse);
    });

    test('copyWith clears error when clearError is true', () {
      const state = FluxContinuState(error: 'boom');
      final updated = state.copyWith(clearError: true);
      expect(updated.error, isNull);
    });

    test('copyWith preserves untouched fields', () {
      const state = FluxContinuState(isSerene: true);
      final updated = state.copyWith(isLoading: false);
      expect(updated.isSerene, isTrue);
      expect(updated.isLoading, isFalse);
    });
  });

  group('Section.hasOverflow', () {
    Section build(int total, int core) {
      return Section(
        kind: SectionKind.theme1,
        label: 'Test',
        accent: const Color(0xFFFFFFFF),
        articles: List.generate(total, (i) => 'a$i'),
        coreCount: core,
      );
    }

    test('true when articles exceed coreCount', () {
      expect(build(5, 2).hasOverflow, isTrue);
    });

    test('false when articles equal coreCount', () {
      expect(build(3, 3).hasOverflow, isFalse);
    });

    test('false when articles are fewer than coreCount', () {
      expect(build(1, 3).hasOverflow, isFalse);
    });
  });
}
