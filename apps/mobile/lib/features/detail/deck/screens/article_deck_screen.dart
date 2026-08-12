import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/analytics_provider.dart';
import '../../../feed/models/content_model.dart';
import '../../../flux_continu/services/preview_nudge_scheduler.dart';
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
///
/// Story 34.2 — l'écran porte en plus le **deck courant** : arrivé au bout
/// d'une section de la Tournée, il remplace le deck sur place par celui de la
/// section suivante. Remplacement plutôt qu'empilement de routes : dérouler une
/// tournée de huit blocs ne doit pas laisser huit écrans derrière soi.
class ArticleDeckScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ArticleDeckScreen> createState() => _ArticleDeckScreenState();
}

class _ArticleDeckScreenState extends ConsumerState<ArticleDeckScreen> {
  /// Deck rendu : celui de la route, puis celui de la section suivante à chaque
  /// enchaînement.
  ArticleDeckPayload? _deck;

  /// Le CTA « Pas de recul » n'a de sens que sur l'article ouvert depuis lui —
  /// il ne survit ni au swipe, ni au passage à la section suivante.
  bool _fromDeepReco = false;

  @override
  void initState() {
    super.initState();
    _deck = widget.deck;
    _fromDeepReco = widget.fromDeepReco;
  }

  @override
  void didUpdateWidget(ArticleDeckScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nouvelle route (autre article) sur le même élément : on repart du deck
    // fourni, jamais de celui où la lecture précédente s'était arrêtée.
    if (widget.deck != oldWidget.deck ||
        widget.contentId != oldWidget.contentId) {
      _deck = widget.deck;
      _fromDeepReco = widget.fromDeepReco;
    }
  }

  void _advanceToSection(ArticleDeckPayload next) {
    final from = _deck;
    if (from != null) {
      unawaited(
        ref.read(analyticsServiceProvider).trackDeckSectionAdvance(
              fromSectionKey: from.sectionKey,
              toSectionKey: next.sectionKey,
              fromDeckSize: from.articles.length,
              toDeckSize: next.articles.length,
            ),
      );
    }
    setState(() {
      _deck = next;
      _fromDeepReco = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final deck = _deck;
    if (deck == null || !deck.isNavigable) {
      return ContentDetailScreen(
        contentId: widget.contentId,
        content: widget.content,
        fromDeepReco: _fromDeepReco,
      );
    }

    final analytics = ref.read(analyticsServiceProvider);
    final swipeNudge = ref.read(articleSwipeNudgeSchedulerProvider);

    return ArticleDeckView(
      // Change de deck ⇒ nouvelle pile : `PageController` et pages repartent de
      // zéro, sur le premier article de la section suivante.
      key:
          ValueKey('article-deck-${deck.sectionKey}-${deck.initialArticle.id}'),
      deck: deck,
      onArticleChanged: (from, to) {
        // Le geste a servi : le rappel passe en régime « déjà découvert ».
        unawaited(swipeNudge.markDiscovered());
        unawaited(
          analytics.trackArticleSwipeNav(
            contentId: deck.articles[to].id,
            sectionKey: deck.sectionKey,
            direction: to > from ? 'next' : 'previous',
            fromPosition: from,
            toPosition: to,
            deckSize: deck.articles.length,
          ),
        );
      },
      shouldPlaySwipeHint: swipeNudge.canTriggerNow,
      onSwipeHintPlayed: () {
        unawaited(swipeNudge.recordTriggered());
        unawaited(
          analytics.trackArticleSwipeHint(sectionKey: deck.sectionKey),
        );
      },
      onAdvanceToSection: _advanceToSection,
      pageBuilder: (context, slot) {
        final article = deck.articles[slot.index];
        return ContentDetailScreen(
          key: ValueKey('article-deck-page-${article.id}'),
          contentId: article.id,
          content: article,
          // Le header contextuel « Pas de recul » n'appartient qu'à l'article
          // réellement ouvert depuis le CTA, pas à ses voisins de section.
          fromDeepReco: _fromDeepReco && slot.index == deck.initialIndex,
          deckSlot: slot,
        );
      },
    );
  }
}
