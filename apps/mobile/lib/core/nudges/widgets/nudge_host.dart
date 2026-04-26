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
/// (GlobalKey montée, route `/feed` courante).
class NudgeHost extends ConsumerStatefulWidget {
  const NudgeHost({super.key});

  @override
  ConsumerState<NudgeHost> createState() => _NudgeHostState();
}

class _NudgeHostState extends ConsumerState<NudgeHost> {
  TutorialCoachMark? _current;
  String? _shownForId;

  @override
  void initState() {
    super.initState();
    final coordinator = ref.read(nudgeCoordinatorProvider);
    coordinator.activeListenable.addListener(_onActiveChanged);
  }

  @override
  void dispose() {
    ref
        .read(nudgeCoordinatorProvider)
        .activeListenable
        .removeListener(_onActiveChanged);
    _current?.finish();
    _current = null;
    super.dispose();
  }

  void _onActiveChanged() {
    if (!mounted) return;
    final coordinator = ref.read(nudgeCoordinatorProvider);
    final id = coordinator.activeId;
    if (id == null) {
      _dismissCurrent();
      _shownForId = null;
      return;
    }
    if (_shownForId == id) return;

    final nudge = NudgeRegistry.get(id);
    if (!_isFeedSpotlight(nudge)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentLocation =
          GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
      if (!currentLocation.startsWith(RoutePaths.feed)) return;

      final anchor = _anchorFor(id);
      if (anchor?.currentContext == null) return;

      _showSpotlight(id, anchor!);
    });
  }

  bool _isFeedSpotlight(Nudge nudge) {
    return nudge.surface == NudgeSurface.feed &&
        nudge.placement == NudgePlacement.tooltip;
  }

  GlobalKey? _anchorFor(String id) {
    switch (id) {
      case NudgeIds.feedBadgeLongpress:
        return feedFirstBadgeKey;
      case NudgeIds.feedPreviewLongpress:
        return feedFirstCardKey;
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
      enableOverlayTab: false,
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
    )..show(context: context);
    _shownForId = id;
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
    final coordinator = ref.read(nudgeCoordinatorProvider);
    if (coordinator.activeId == id) {
      coordinator.dismiss(markSeen: true);
    }
    _dismissCurrent();
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
