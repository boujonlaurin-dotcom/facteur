import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../models/article_deck.dart';

/// Part de largeur d'écran dont la page **de gauche** retarde pendant le
/// mouvement. 0 = pas de parallaxe, 1 = page figée. Repris de la sémantique
/// Cupertino (la page qui reste derrière avance moins vite que le doigt), ce
/// qui donne la profondeur sans jamais désynchroniser la page du dessus.
const double _kParallaxFactor = 0.45;

/// Retrait d'échelle appliqué à la page de gauche en fin de course.
const double _kScaleDrop = 0.03;

/// Opacité maximale du voile posé sur la page de gauche.
const double _kScrimAlpha = 0.20;

/// Largeur du dégradé qui borde l'arête gauche de la page du dessus — c'est
/// lui qui fait lire les deux pages comme deux feuilles superposées.
const double _kEdgeShadowWidth = 20;

/// Course de sur-défilement (en px de position, pas de doigt : la physique
/// « bouncing » amortit) au-delà de laquelle relâcher referme le deck et rend
/// la main à la section. Sur le 1ᵉʳ article, glisser à droite reste donc
/// « revenir en arrière ».
const double _kBackPullCommit = 56;

/// Course à partir de laquelle l'affordance de retour est pleinement visible.
const double _kBackPullReveal = 72;

/// Pile d'articles navigable au swipe horizontal.
///
/// Une page = un article. Le rendu de la page est délégué à [pageBuilder], qui
/// reçoit son [ArticleDeckSlot] : c'est le reader lui-même qui décide de rendre
/// l'article complet (page active) ou son aperçu d'arrivée (page seulement
/// entrevue pendant le geste).
///
/// Le deck ne prend jamais la main quand la WebView du site est montée
/// ([ArticleDeckPayload] → `webViewLock`) : à ce moment le geste horizontal
/// appartient à la page distante.
class ArticleDeckView extends StatefulWidget {
  const ArticleDeckView({
    super.key,
    required this.deck,
    required this.pageBuilder,
    this.onArticleChanged,
  });

  final ArticleDeckPayload deck;

  /// Construit la page d'index donné pour la place [ArticleDeckSlot] fournie.
  final Widget Function(BuildContext context, ArticleDeckSlot slot) pageBuilder;

  /// Notifie un changement d'article **validé** (fin de geste), jamais un
  /// simple survol pendant le drag.
  final void Function(int fromIndex, int toIndex)? onArticleChanged;

  @override
  State<ArticleDeckView> createState() => _ArticleDeckViewState();
}

class _ArticleDeckViewState extends State<ArticleDeckView> {
  late final PageController _controller;
  late int _settledIndex;

  /// Verrou posé par la page active quand la WebView du site est montée.
  final ValueNotifier<bool> _webViewLock = ValueNotifier<bool>(false);

  /// Course de sur-défilement en tête de deck (1ᵉʳ article tiré vers la droite).
  final ValueNotifier<double> _backPull = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _settledIndex = widget.deck.initialIndex;
    _controller = PageController(initialPage: _settledIndex);
    _webViewLock.addListener(_onWebViewLockChanged);
  }

  @override
  void dispose() {
    _webViewLock.removeListener(_onWebViewLockChanged);
    _controller.dispose();
    _webViewLock.dispose();
    _backPull.dispose();
    super.dispose();
  }

  void _onWebViewLockChanged() {
    // Le verrou change la `physics` du PageView → rebuild nécessaire.
    if (mounted) setState(() {});
  }

  /// Page courante en valeur continue, robuste avant le premier layout
  /// (`page` lève tant que la position n'a pas de dimensions).
  double get _page {
    if (_controller.hasClients && _controller.position.hasContentDimensions) {
      return _controller.page ?? _settledIndex.toDouble();
    }
    return _settledIndex.toDouble();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;

    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final metrics = notification.metrics;
      final overscroll = metrics.minScrollExtent - metrics.pixels;
      _backPull.value = overscroll > 0 ? overscroll : 0;
    }

    // L'article n'est « changé » qu'au repos : `onPageChanged` du PageView
    // bascule dès le milieu du geste, donc sur de simples survols annulés
    // ensuite. Le reader ne doit ni compter une ouverture ni marquer « Lu »
    // pour un article seulement entrevu.
    if (notification is ScrollEndNotification) {
      final target = _page.round().clamp(0, widget.deck.articles.length - 1);
      if (target != _settledIndex) {
        final previous = _settledIndex;
        setState(() => _settledIndex = target);
        unawaited(HapticFeedback.selectionClick());
        widget.onArticleChanged?.call(previous, target);
      }
    }
    return false;
  }

  void _onPointerUp() {
    if (_backPull.value >= _kBackPullCommit && _settledIndex == 0) {
      _backPull.value = 0;
      unawaited(HapticFeedback.lightImpact());
      Navigator.of(context).maybePop(widget.deck.articles[_settledIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _webViewLock.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Révélée par le rebond du PageView en tête de deck : le fond de
        // l'écran apparaît sous la page qui glisse vers la droite.
        _buildBackAffordance(context),
        Listener(
          onPointerUp: (_) => _onPointerUp(),
          onPointerCancel: (_) => _backPull.value = 0,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.deck.articles.length,
              // `BouncingScrollPhysics` sur les deux plateformes : c'est le
              // rebond qui porte l'affordance de retour en tête de deck, et il
              // doit se comporter pareil sur Android et iOS.
              physics: locked
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(parent: BouncingScrollPhysics()),
              itemBuilder: (context, index) {
                final slot = ArticleDeckSlot(
                  index: index,
                  length: widget.deck.articles.length,
                  isActive: index == _settledIndex,
                  showSegments: widget.deck.showPositionIndicator,
                  webViewLock: _webViewLock,
                );
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => _transformPage(index, child!),
                  // La page est construite ICI, hors du builder animé : elle
                  // n'est pas reconstruite à chaque frame du geste, seule son
                  // enveloppe de transformation l'est.
                  child: widget.pageBuilder(context, slot),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Enveloppe de transformation d'une page.
  ///
  /// La **forme** de l'arbre est constante (mêmes widgets, mêmes niveaux, à
  /// l'identique au repos et en mouvement) : insérer ou retirer un ancêtre du
  /// reader le ferait réinflater et perdre son état (scroll, WebView, fetch en
  /// cours). Seules les *valeurs* varient.
  Widget _transformPage(int index, Widget child) {
    final width = MediaQuery.sizeOf(context).width;
    final delta = (_page - index).clamp(-1.0, 1.0);

    // `delta > 0` ⇒ la page est celle de **gauche** du couple en mouvement,
    // quel que soit le sens du geste (le PageView interpole entre index et
    // index+1). C'est elle qui prend la parallaxe, le voile et le retrait
    // d'échelle ; celle de droite glisse à pleine vitesse par-dessus.
    final behind = delta > 0 ? delta : 0.0;
    final moving = delta.abs();
    final radius = FacteurRadius.large * (moving * 4).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(behind * width * _kParallaxFactor, 0),
      child: Transform.scale(
        scale: 1 - _kScaleDrop * behind,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: radius > 0 ? Clip.antiAlias : Clip.none,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              // Voile de profondeur (page de gauche) — `ColoredBox` ne peint
              // rien à alpha 0, l'état de repos est donc gratuit.
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: _kScrimAlpha * behind),
                ),
              ),
              // Ombre d'arête de la page du dessus.
              if (delta < 0 && moving > 0.001)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _kEdgeShadowWidth,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.13 * moving),
                            Colors.black.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// « ← {section} » révélé sous la page quand on tire le 1ᵉʳ article vers la
  /// droite. Muet partout ailleurs : au-delà du premier article, glisser à
  /// droite mène à l'article précédent, il n'y a rien à annoncer.
  Widget _buildBackAffordance(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return ValueListenableBuilder<double>(
      valueListenable: _backPull,
      builder: (context, pull, _) {
        if (pull <= 0 || _settledIndex != 0) return const SizedBox.shrink();
        final t = (pull / _kBackPullReveal).clamp(0.0, 1.0);
        final armed = pull >= _kBackPullCommit;
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: FacteurSpacing.space4),
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(-12 * (1 - t), 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      PhosphorIcons.arrowLeft(
                        armed
                            ? PhosphorIconsStyle.bold
                            : PhosphorIconsStyle.regular,
                      ),
                      size: 20,
                      color: armed ? colors.primary : colors.textTertiary,
                    ),
                    const SizedBox(height: FacteurSpacing.space2),
                    SizedBox(
                      width: 90,
                      child: Text(
                        widget.deck.sectionLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: armed ? colors.primary : colors.textTertiary,
                          fontWeight:
                              armed ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
