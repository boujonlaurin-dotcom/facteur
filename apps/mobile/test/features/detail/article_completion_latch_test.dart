import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/detail/models/article_completion_latch.dart';
import 'package:facteur/features/feed/services/read_sync_service.dart'
    show CompletionSource;

/// Epic 30 — réouverture d'un article terminé.
///
/// Le compteur de lectures abouties doit servir à calibrer l'objectif
/// journalier : chaque relecture qui réémettait `article_finished` le gonflait
/// et rendait la distribution inexploitable.
void main() {
  test('latch n\'émet qu\'une fois', () {
    final latch = ArticleCompletionLatch();

    expect(latch.latch(CompletionSource.inApp), isTrue);
    expect(latch.latch(CompletionSource.inApp), isFalse);
    expect(latch.completed, isTrue);
    expect(latch.source, CompletionSource.inApp);
  });

  test('seed(prior) bloque l\'émission mais pas l\'affichage', () {
    final latch = ArticleCompletionLatch();
    latch.seed(prior: true);

    // Le test central : l'article est terminé (le cachet et le filet doivent
    // s'afficher), mais rien ne doit être réémis.
    expect(latch.completed, isTrue);
    expect(latch.priorCompleted, isTrue);
    expect(latch.latch(CompletionSource.inApp), isFalse);
    expect(latch.source, isNull);
  });

  test('seed est monotone : un amorçage négatif ne rouvre rien', () {
    final latch = ArticleCompletionLatch();
    latch.seed(prior: true);
    // Source tardive et moins fiable (ex. fetch qui ne connaît pas encore la
    // complétion locale) : elle ne doit pas contredire la précédente.
    latch.seed(prior: false);

    expect(latch.priorCompleted, isTrue);
    expect(latch.latch(CompletionSource.web), isFalse);
  });

  test('un amorçage tardif ne contredit pas une complétion de session', () {
    final latch = ArticleCompletionLatch();
    expect(latch.latch(CompletionSource.web), isTrue);

    latch.seed(prior: true);

    expect(latch.completed, isTrue);
    // L'événement a bien eu lieu dans cette session.
    expect(latch.source, CompletionSource.web);
  });

  test('un contenu externe ne latche jamais', () {
    final latch = ArticleCompletionLatch();

    expect(latch.latch(CompletionSource.inApp, isExternal: true), isFalse);
    expect(latch.completed, isFalse);
  });
}
