import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/flux_continu/widgets/flux_continu_article_card.dart';

/// Epic 30 — le backend sert `completed_at`, `DigestItem` le désérialise… et la
/// couche de rendu le jetait. Deux conversions à protéger.
void main() {
  DigestItem item({DateTime? completedAt}) => DigestItem(
        contentId: 'c-1',
        title: 'Titre',
        url: 'https://example.com/1',
        completedAt: completedAt,
      );

  test('FluxArticleVM.from(DigestItem) mappe la complétion', () {
    expect(FluxArticleVM.from(item()).isCompleted, isFalse);
    expect(
      FluxArticleVM.from(item(completedAt: DateTime(2026, 7, 24, 9)))
          .isCompleted,
      isTrue,
    );
  });

  test('articleToContent préserve completedAt', () {
    final completedAt = DateTime(2026, 7, 24, 9);

    final content = articleToContent(item(completedAt: completedAt));

    // Sans ça, l'écran de détail ouvert depuis le flux rejouait la complétion.
    expect(content.completedAt, completedAt);
    expect(content.isCompleted, isTrue);
    expect(articleToContent(item()).isCompleted, isFalse);
  });
}
