import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/analytics_provider.dart';
import '../../../feed/models/content_model.dart';
import '../../screens/content_detail_screen.dart';
import '../models/article_deck.dart';
import '../widgets/article_deck_view.dart';

/// Cible de la route `content/:id` (Story 34.1).
///
/// **Sans deck navigable, cet écran est un passe-plat** : il rend exactement le
/// reader d'avant, sans `PageView`. C'est ce qui garantit qu'aucun appelant
/// historique (notification, deep link, Sauvegardés, modal source, lecteur de
/// perspective externe) ne change de comportement.
///
/// Avec un deck de N > 1 articles, chaque page est un `ContentDetailScreen`
/// à part entière, keyé par l'id de l'article : les états lourds du reader
/// (scroll, WebView, fetch, latch de complétion) restent strictement isolés
/// d'un article à l'autre, sans refonte de l'écran.
class ArticleDeckScreen extends ConsumerWidget {
  const ArticleDeckScreen({
    super.key,
    required this.contentId,
    this.content,
    this.deck,
    this.fromDeepReco = false,
  });

  final String contentId;
  final Content? content;
  final ArticleDeckPayload? deck;
  final bool fromDeepReco;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deck = this.deck;
    if (deck == null || !deck.isNavigable) {
      return ContentDetailScreen(
        contentId: contentId,
        content: content,
        fromDeepReco: fromDeepReco,
      );
    }

    return ArticleDeckView(
      deck: deck,
      onArticleChanged: (from, to) => unawaited(
        ref.read(analyticsServiceProvider).trackArticleSwipeNav(
              contentId: deck.articles[to].id,
              sectionKey: deck.sectionKey,
              direction: to > from ? 'next' : 'previous',
              fromPosition: from,
              toPosition: to,
              deckSize: deck.articles.length,
            ),
      ),
      pageBuilder: (context, slot) {
        final article = deck.articles[slot.index];
        return ContentDetailScreen(
          key: ValueKey('article-deck-page-${article.id}'),
          contentId: article.id,
          content: article,
          // Le header contextuel « Pas de recul » n'appartient qu'à l'article
          // réellement ouvert depuis le CTA, pas à ses voisins de section.
          fromDeepReco: fromDeepReco && slot.index == deck.initialIndex,
          deckSlot: slot,
        );
      },
    );
  }
}
