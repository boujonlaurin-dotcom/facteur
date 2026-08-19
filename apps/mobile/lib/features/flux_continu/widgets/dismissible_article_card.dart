import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/analytics_provider.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../digest/models/digest_models.dart' show SourceMini;
import '../../feed/widgets/feedback_inline.dart';
import '../providers/flux_continu_provider.dart';
import 'flux_continu_article_card.dart';
import 'section_block.dart' show FluxFeedbackChip;

/// Carte d'article des pages dédiées « Tout lire » (section digest / thème /
/// source), swipable **dans les deux sens** comme dans la Tournée et Flâner.
///
/// - swipe droit → ouvre l'article ([onTap]) ;
/// - swipe gauche → masque l'article (`hideContent`) et remplace la carte par
///   le bandeau [FeedbackInline] (« Moins voir cette source / ce thème »,
///   « Déjà vu », « Annuler »).
///
/// Pourquoi un widget auto-porté plutôt que le câblage de `SectionBlock`
/// (`pendingFeedbackIds` remontés à l'écran) : les pages dédiées rendent leurs
/// listes depuis trois sources différentes (feed du jour, section paginée,
/// curation d'une source chargée localement). Un état local par carte donne le
/// même comportement sur les trois sans faire porter à chaque écran la
/// mécanique pending/resolve. Une fois le feedback résolu, la carte se rend
/// vide : les listes adossées à `fluxContinuProvider` la perdent de toute façon
/// au rebuild ([FluxContinuNotifier.confirmDismiss]), les listes locales
/// (curation source, découverte) la laissent simplement disparaître.
///
/// La carte doit porter une `Key` stable dérivée du `contentId` : sans elle,
/// l'état de masquage se réaffecterait à l'article voisin quand la liste se
/// resserre.
class DismissibleArticleCard extends ConsumerStatefulWidget {
  /// [Content] ou [DigestItem] — même contrat que [FluxContinuArticleCard].
  final Object article;
  final VoidCallback onTap;

  /// `origin` de l'événement `article_feedback_submitted` (miroir des valeurs
  /// `flux_continu` / `flaner` posées par les feeds).
  final String analyticsOrigin;

  final int sourceCount;
  final List<SourceMini> perspectiveSources;
  final String? divergenceLevel;

  const DismissibleArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    required this.analyticsOrigin,
    this.sourceCount = 0,
    this.perspectiveSources = const [],
    this.divergenceLevel,
  });

  @override
  ConsumerState<DismissibleArticleCard> createState() =>
      _DismissibleArticleCardState();
}

/// Cycle de vie d'une carte : visible → bandeau de feedback → retirée.
enum _DismissPhase { card, feedback, resolved }

class _DismissibleArticleCardState
    extends ConsumerState<DismissibleArticleCard> {
  _DismissPhase _phase = _DismissPhase.card;

  String get _contentId => FluxArticleVM.from(widget.article).contentId;

  void _onSwipeDismiss() {
    final id = _contentId;
    if (id.isEmpty) return;
    unawaited(ref.read(fluxContinuProvider.notifier).markHiddenRemote(id));
    setState(() => _phase = _DismissPhase.feedback);
  }

  void _resolve() {
    if (!mounted || _phase != _DismissPhase.feedback) return;
    setState(() => _phase = _DismissPhase.resolved);
    ref.read(fluxContinuProvider.notifier).confirmDismiss(_contentId);
  }

  void _undo() {
    if (!mounted) return;
    unawaited(ref.read(fluxContinuProvider.notifier).undoHide(_contentId));
    setState(() => _phase = _DismissPhase.card);
  }

  void _track(String feedbackType) {
    unawaited(
      ref.read(analyticsServiceProvider).trackArticleFeedbackSubmitted(
            contentId: _contentId,
            feedbackType: feedbackType,
            origin: widget.analyticsOrigin,
          ),
    );
  }

  Future<void> _onSelectChip(FluxFeedbackChip chip) async {
    switch (chip) {
      case FluxFeedbackChip.source:
        _track('less_source');
        await TopicChip.showArticleSheet(
          context,
          articleToContent(widget.article),
          initialSection: ArticleSheetSection.source,
          highlightInitialSection: true,
        );
        _resolve();
      case FluxFeedbackChip.topic:
        _track('less_topic');
        await TopicChip.showArticleSheet(
          context,
          articleToContent(widget.article),
          initialSection: ArticleSheetSection.topic,
          highlightInitialSection: true,
        );
        _resolve();
      case FluxFeedbackChip.alreadySeen:
        _track('already_seen');
        _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _DismissPhase.resolved:
        return const SizedBox.shrink();
      case _DismissPhase.feedback:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: FeedbackInline(
            onSelectSource: () => _onSelectChip(FluxFeedbackChip.source),
            onSelectTopic: () => _onSelectChip(FluxFeedbackChip.topic),
            onSelectAlreadySeen: () =>
                _onSelectChip(FluxFeedbackChip.alreadySeen),
            onUndo: _undo,
            onClose: _resolve,
          ),
        );
      case _DismissPhase.card:
        return FluxContinuArticleCard(
          article: widget.article,
          onTap: widget.onTap,
          onSwipeDismiss: _onSwipeDismiss,
          sourceCount: widget.sourceCount,
          perspectiveSources: widget.perspectiveSources,
          divergenceLevel: widget.divergenceLevel,
        );
    }
  }
}
