import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../flux_continu/widgets/manage_favorites_sheet.dart';
import '../models/tour_step.dart';
import '../providers/guided_tour_controller.dart';
import '../tour_anchors.dart';
import 'guided_tour_overlay.dart';

/// Pont racine du tour guidé : écoute [guidedTourControllerProvider] et exécute
/// les effets de bord qui exigent un `BuildContext`/navigation (le notifier, lui,
/// n'en touche jamais — cf. classe de bug `nudge_host.dart:35-38`).
///
/// Monté **une seule fois** dans `MainShell` (stable tant qu'on est dans le shell
/// principal, jamais démonté pendant un changement d'onglet). Il insère un
/// [OverlayEntry] dans l'overlay **racine** pour passer au-dessus de la feuille
/// « Mes favoris » (qui vit dans le navigator de branche).
class GuidedTourBridge extends ConsumerStatefulWidget {
  const GuidedTourBridge({super.key});

  @override
  ConsumerState<GuidedTourBridge> createState() => _GuidedTourBridgeState();
}

class _GuidedTourBridgeState extends ConsumerState<GuidedTourBridge> {
  OverlayEntry? _entry;
  TourStep? _step;
  List<GlobalKey> _targets = const [];
  bool _centerCard = false;
  bool _favSheetOpen = false;
  Timer? _doneTimer;

  @override
  void dispose() {
    _doneTimer?.cancel();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _onStep(TourStep? step) {
    if (step == _step) return;
    _step = step;

    if (step == null) {
      _doneTimer?.cancel();
      _entry?.remove();
      _entry = null;
      return;
    }

    _ensureOverlay();
    _applyStep(step);
    _entry?.markNeedsBuild();
  }

  void _ensureOverlay() {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (_) => GuidedTourOverlay(
        step: _step ?? TourStep.essentielHero,
        targets: _targets,
        centerCard: _centerCard,
        onSkip: () => ref.read(guidedTourControllerProvider.notifier).skip(),
        onNext: () => ref.read(guidedTourControllerProvider.notifier).next(),
      ),
    );
    overlay.insert(_entry!);
  }

  /// Effets de bord + cibles spotlight à l'entrée de chaque étape.
  void _applyStep(TourStep step) {
    _centerCard = false;
    switch (step) {
      case TourStep.essentielHero:
        _targets = [tourEssentielHeroKey, tourEssentielFooterTabKey];
        if (mounted) context.go(RoutePaths.fluxContinu);
        _bumpEssentielScrollToTop();
      case TourStep.descendsCartes:
        _targets = [tourActusSectionKey];
        ref.read(tourScrollTargetProvider.notifier).state = tourActusSectionKey;
      case TourStep.favorisSheet:
        _targets = [tourFavorisSheetKey];
        _openFavoritesSheet();
      case TourStep.flaner:
        _targets = const [];
        _centerCard = true;
        _closeFavoritesSheetIfOpen();
        if (mounted) context.go(RoutePaths.flaner);
      case TourStep.reglages:
        _targets = [tourProfileAvatarKey];
        if (mounted) context.go(RoutePaths.fluxContinu);
      case TourStep.courrier:
        _targets = [tourProfileAvatarKey];
      case TourStep.done:
        _targets = const [];
        _doneTimer?.cancel();
        _doneTimer = Timer(const Duration(milliseconds: 1800), () {
          ref.read(guidedTourControllerProvider.notifier).dismiss();
        });
    }
  }

  void _bumpEssentielScrollToTop() {
    final notifier = ref.read(essentielScrollTriggerProvider.notifier);
    notifier.state = notifier.state + 1;
  }

  /// Ouvre la vraie feuille « Mes favoris » sur le navigator de la branche
  /// Essentiel (via le `context` du hero, encore monté). Si l'utilisateur la
  /// referme au doigt avant de cliquer « Suivant », on auto-avance vers Flâner
  /// (watchdog : on ne reste pas bloqué derrière un voile orphelin).
  void _openFavoritesSheet() {
    final branchCtx = tourEssentielHeroKey.currentContext;
    if (branchCtx == null) return;
    _favSheetOpen = true;
    showManageFavoritesSheet(branchCtx).whenComplete(() {
      _favSheetOpen = false;
      if (!mounted) return;
      // Fermeture initiée par l'utilisateur (pas par notre transition vers
      // Flâner, qui a déjà changé l'état) → on enchaîne.
      if (ref.read(guidedTourControllerProvider) == TourStep.favorisSheet) {
        ref.read(guidedTourControllerProvider.notifier).next();
      }
    });
  }

  void _closeFavoritesSheetIfOpen() {
    if (!_favSheetOpen) return;
    final branchCtx = tourEssentielHeroKey.currentContext;
    if (branchCtx != null) {
      Navigator.of(branchCtx).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TourStep?>(guidedTourControllerProvider, (_, next) {
      _onStep(next);
    });
    return const SizedBox.shrink();
  }
}
