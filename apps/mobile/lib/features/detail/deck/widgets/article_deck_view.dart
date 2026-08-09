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

/// Mur de fin de deck : course de sur-défilement maximale au-delà du **dernier**
/// article. Le rebond libre y révélait le fond de route (écran noir) et laissait
/// croire à une page suivante ; contre ce mur, la pile résiste puis revient —
/// on reste sur le dernier article, il n'y a rien derrière.
const double _kEndBumpMax = 32;

/// Course à laquelle le mur se signale au doigt. Volontairement **avant** le
/// fond de course : l'amortissement étant asymptotique (cf.
/// `_DeckBumpScrollPhysics`), les tout derniers pixels ne sont jamais atteints
/// et un retour haptique calé dessus ne se déclencherait jamais.
const double _kEndBumpHapticAt = _kEndBumpMax * 0.6;

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

  /// Vrai tant que le retour haptique du mur de fin n'a pas été rejoué : il ne
  /// se réarme qu'une fois le geste revenu au repos, sinon un doigt maintenu
  /// contre le mur ferait vibrer en continu.
  bool _endBumpArmed = true;

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
      _handleEndBump(metrics.pixels - metrics.maxScrollExtent);
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
        // La surface d'origine suit la lecture pour se rouvrir au bon endroit
        // (cf. `ArticleDeckPayload.onArticleSettled`). Notifié d'ici, et non du
        // haut : c'est le seul point qui distingue une page *validée* d'une
        // page entrevue pendant le geste.
        widget.deck.onArticleSettled?.call(widget.deck.articles[target]);
        widget.onArticleChanged?.call(previous, target);
      }
    }
    return false;
  }

  /// Coup sec quand le geste atteint le mur de fin — c'est lui qui dit « c'est
  /// le dernier » sans rien ajouter à l'écran.
  void _handleEndBump(double overscroll) {
    if (overscroll >= _kEndBumpHapticAt) {
      if (_endBumpArmed) {
        _endBumpArmed = false;
        unawaited(HapticFeedback.lightImpact());
      }
    } else if (overscroll <= 4) {
      _endBumpArmed = true;
    }
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
        // Fond du deck. Sans lui, la bande découverte par le rebond laisse voir
        // le fond de route — noir — ce qui se lit comme un écran suivant vide
        // plutôt que comme le bout de la pile.
        ColoredBox(color: context.facteurColors.backgroundPrimary),
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
              // doit se comporter pareil sur Android et iOS. Borné en fin de
              // deck (cf. `_DeckBumpScrollPhysics`).
              physics: locked
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(parent: _DeckBumpScrollPhysics()),
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
    // La position est bornée au deck : en sur-défilement (tête ou fin), aucune
    // page ne devient « celle de gauche d'un couple » — sans quoi le dernier
    // article se voilait et reculait en butant sur le mur, exactement le noir
    // qu'on veut supprimer. La page glisse alors telle quelle avec le rebond.
    final last = (widget.deck.articles.length - 1).toDouble();
    final delta = (_page.clamp(0.0, last) - index).clamp(-1.0, 1.0);

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

/// Rebond libre en tête de deck (il porte l'affordance de retour), **mur
/// élastique** en fin de deck.
///
/// Au-delà du dernier article, le rebond `BouncingScrollPhysics` laissait la
/// page partir sur presque une demi-largeur d'écran : la bande découverte se
/// lisait comme une page suivante, vide.
///
/// La course est ramenée sous [_kEndBumpMax], mais **jamais par une butée
/// sèche** : le déplacement transmis au doigt fond progressivement à mesure
/// qu'on approche du mur (`resistance²`, donc dérivée nulle à l'arrivée). La
/// page décélère au lieu de se figer — on sent une matière qui résiste, pas un
/// scroll qui casse. Insister ne fait plus rien avancer : on *reste* sur le
/// dernier article, ce qui est précisément le message.
class _DeckBumpScrollPhysics extends BouncingScrollPhysics {
  const _DeckBumpScrollPhysics({super.parent});

  @override
  _DeckBumpScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _DeckBumpScrollPhysics(parent: buildParent(ancestor));

  /// Course réellement parcourue par la pile pour [travel] pixels de doigt
  /// au-delà du dernier article : hyperbole `M·t/(t+M)`.
  ///
  /// Choisie pour ses trois propriétés, dans l'ordre où on les sent : pente 1
  /// au départ (les premiers pixels suivent le doigt, le geste n'est pas mangé),
  /// pente qui décroît continûment (la matière résiste de plus en plus), limite
  /// [_kEndBumpMax] jamais franchie (le mur). Aucun palier, donc aucune saccade.
  static double _wallTravel(double travel) =>
      _kEndBumpMax * travel / (travel + _kEndBumpMax);

  /// Réciproque : quelle course de doigt a produit ce sur-défilement.
  static double _fingerTravel(double overscroll) =>
      _kEndBumpMax * overscroll / (_kEndBumpMax - overscroll);

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // `offset < 0` ⇒ le doigt pousse vers l'article suivant (les pixels du
    // `PageView` augmentent). C'est le seul sens à amortir : vers l'arrière, le
    // deck se navigue normalement.
    final overscroll = position.pixels - position.maxScrollExtent;
    if (offset < 0 && overscroll >= 0) {
      // Dès le premier pixel au-delà du bord, sinon `BouncingScrollPhysics`
      // transmet ce premier pas 1:1 (il n'amortit qu'un sur-défilement déjà
      // constitué) et la pile saute dans le mur au lieu d'y arriver.
      if (overscroll >= _kEndBumpMax) return 0;
      final travel = _fingerTravel(overscroll) - offset;
      return -(_wallTravel(travel) - overscroll);
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // Filet de sécurité pour les trajectoires balistiques (un lancer rapide ne
    // passe pas par `applyPhysicsToUserOffset`). Au doigt, l'amortissement
    // ci-dessus fait que cette butée n'est jamais atteinte.
    final wall = position.maxScrollExtent + _kEndBumpMax;
    if (value > wall) return value - wall;
    return super.applyBoundaryConditions(position, value);
  }
}
