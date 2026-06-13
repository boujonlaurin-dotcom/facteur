import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../config/routes.dart';
import '../nudge.dart';
import '../nudge_coordinator.dart';
import '../nudge_ids.dart';
import '../nudge_registry.dart';
import 'feed_nudge_anchors.dart';
import 'nudge_tooltip_bubble.dart';

/// Écoute [nudgeCoordinatorProvider] et rend les spotlights pour les nudges
/// qui nécessitent un overlay plein-écran (feed badge/preview).
///
/// Les autres placements (inlineBanner, hintAnimation, tooltip intra-article)
/// sont rendus en place par les feature widgets eux-mêmes — ce host ne fait
/// que coordonner quand activer le spotlight et qu'il a les bonnes conditions
/// (GlobalKey montée, route feed courante).
class NudgeHost extends ConsumerStatefulWidget {
  const NudgeHost({super.key});

  @override
  ConsumerState<NudgeHost> createState() => _NudgeHostState();
}

class _NudgeHostState extends ConsumerState<NudgeHost> {
  TutorialCoachMark? _current;
  String? _shownForId;
  int _anchorWaitGeneration = 0;

  // Caché en champ pour ne JAMAIS toucher `ref` dans dispose() : le shell peut
  // se démonter pendant finalizeTree (sortie d'onboarding), moment où ref.read
  // lève StateError et corrompt l'arbre (écran gris — Sentry FLUTTER-2).
  late final NudgeCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(nudgeCoordinatorProvider);
    _coordinator.activeListenable.addListener(_onActiveChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onActiveChanged());
  }

  @override
  void dispose() {
    _coordinator.activeListenable.removeListener(_onActiveChanged);
    // Vider _shownForId AVANT finish() : le onFinish réentrant ne doit surtout
    // pas toucher `ref` pendant dispose (cf. note sur _coordinator).
    _shownForId = null;
    _current?.finish();
    _current = null;
    super.dispose();
  }

  void _onActiveChanged() {
    if (!mounted) return;
    final coordinator = ref.read(nudgeCoordinatorProvider);
    final id = coordinator.activeId;
    if (id == null) {
      _anchorWaitGeneration += 1;
      _dismissCurrent();
      _shownForId = null;
      return;
    }
    if (_shownForId == id) return;

    final nudge = NudgeRegistry.get(id);
    if (!_isFeedSpotlight(nudge)) {
      _anchorWaitGeneration += 1;
      _dismissCurrent();
      _shownForId = null;
      return;
    }

    final generation = ++_anchorWaitGeneration;
    _waitForAnchor(id, generation);
  }

  Future<void> _waitForAnchor(String id, int generation) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(
        attempt == 0 ? Duration.zero : const Duration(milliseconds: 100),
      );
      if (!mounted ||
          generation != _anchorWaitGeneration ||
          _coordinator.activeId != id) {
        return;
      }
      final currentLocation = GoRouter.of(
        context,
      ).routerDelegate.currentConfiguration.uri.path;
      if (!currentLocation.startsWith(RoutePaths.fluxContinu) &&
          !currentLocation.startsWith(RoutePaths.flaner)) {
        return;
      }
      final anchor = _anchorFor(id, currentLocation);
      // N'afficher que si l'ancre est réellement visible à l'écran : un
      // spotlight sur une cible hors viewport peint le voile plein écran sans
      // trou ni bulle accessibles → utilisateur bloqué derrière un voile
      // uniforme (freeze au refresh de l'Essentiel).
      if (anchor != null && _isAnchorOnScreen(anchor)) {
        _showSpotlight(id, anchor);
        unawaited(_watchAnchorWhileShown(id, anchor));
        return;
      }
    }
  }

  /// Vrai si la cible est montée, mesurée et entièrement visible verticalement
  /// (il faut aussi la place pour le trou du spotlight et la bulle).
  bool _isAnchorOnScreen(GlobalKey anchor) {
    final ctx = anchor.currentContext;
    if (ctx == null || !mounted) return false;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    return topLeft.dy >= 0 && topLeft.dy + box.size.height <= screen.height;
  }

  /// Tant que le spotlight est affiché, vérifie que sa cible existe toujours :
  /// un pull-to-refresh peut démonter la carte ancrée (rebuild des sections),
  /// laissant le voile orphelin. On ferme alors proprement (sans markSeen :
  /// l'utilisateur n'a pas eu le temps de lire).
  Future<void> _watchAnchorWhileShown(String id, GlobalKey anchor) async {
    while (mounted && _current != null && _shownForId == id) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted || _current == null || _shownForId != id) return;
      if (anchor.currentContext == null) {
        _closeSpotlight(id, markSeen: false);
        return;
      }
    }
  }

  bool _isFeedSpotlight(Nudge nudge) {
    return nudge.surface == NudgeSurface.feed &&
        nudge.placement == NudgePlacement.tooltip;
  }

  GlobalKey? _anchorFor(String id, String currentLocation) {
    switch (id) {
      case NudgeIds.feedPreviewLongpress:
        return currentLocation.startsWith(RoutePaths.flaner)
            ? flanerFirstCardKey
            : fluxContinuFirstCardKey;
      default:
        return null;
    }
  }

  void _showSpotlight(String id, GlobalKey target) {
    _dismissCurrent();
    final body = _copyFor(id);
    final focus = TargetFocus(
      identify: 'nudge-$id',
      keyTarget: target,
      shape: ShapeLightFocus.RRect,
      radius: 14,
      // Échappatoire : un tap sur le voile ferme le spotlight. Sans ça, si la
      // bulle devient inaccessible (cible démontée/déplacée), l'utilisateur
      // reste bloqué derrière le voile (pas de route → Échap inopérant).
      enableOverlayTab: true,
      enableTargetTab: false,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.only(top: 12),
          builder: (_, __) => NudgeTooltipBubble(
            body: body,
            onDismiss: () => _onDismissTapped(id),
          ),
        ),
      ],
    );
    _current = TutorialCoachMark(
      targets: [focus],
      colorShadow: const Color(0xFF2C2A29),
      opacityShadow: 0.7,
      paddingFocus: 8,
      hideSkip: true,
      focusAnimationDuration: const Duration(milliseconds: 250),
      pulseAnimationDuration: const Duration(milliseconds: 400),
      // Tap sur le voile (cf. enableOverlayTab) : la lib avance puis appelle
      // onFinish — on synchronise le coordinator pour ne pas laisser le nudge
      // « actif » fantôme.
      onFinish: () => _onSpotlightClosedExternally(id),
    )..show(context: context);
    _shownForId = id;
  }

  /// Fermeture initiée par la lib (tap voile / fin de tutorial). `_shownForId`
  /// sert de garde d'idempotence : les fermetures initiées par nous
  /// (`_closeSpotlight`, `_onActiveChanged`, `dispose`) le vident AVANT
  /// d'appeler `finish()`, donc on ne traite ici que le tap voile.
  void _onSpotlightClosedExternally(String id) {
    _current = null;
    if (_shownForId != id) return;
    _shownForId = null;
    if (!mounted) return;
    final coordinator = ref.read(nudgeCoordinatorProvider);
    if (coordinator.activeId == id) {
      coordinator.dismiss(markSeen: true);
    }
  }

  /// Fermeture initiée par nous (bouton de la bulle, watchdog d'ancre
  /// démontée) : état local vidé d'abord pour neutraliser le onFinish réentrant.
  void _closeSpotlight(String id, {required bool markSeen}) {
    if (_shownForId == id) _shownForId = null;
    _dismissCurrent();
    if (!mounted) return;
    final coordinator = ref.read(nudgeCoordinatorProvider);
    if (coordinator.activeId == id) {
      coordinator.dismiss(markSeen: markSeen);
    }
  }

  String _copyFor(String id) {
    switch (id) {
      case NudgeIds.feedBadgeLongpress:
        return 'Appuyez longuement sur une balise pour bloquer ou prioriser cette thématique.';
      case NudgeIds.feedPreviewLongpress:
        return 'Appuyez longuement sur une carte pour un aperçu rapide sans quitter le feed.';
      default:
        return '';
    }
  }

  void _onDismissTapped(String id) {
    _closeSpotlight(id, markSeen: true);
  }

  void _dismissCurrent() {
    _current?.finish();
    _current = null;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
