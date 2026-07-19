import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../feed/services/read_sync_service.dart';
import '../providers/auto_grow_nudge_provider.dart';
import 'auto_grow_pulse.dart';

/// Enveloppe une carte Flux/Essentiel pour le nudge auto-grow :
///   - déclare la carte comme **candidate** (`visibleFluxContentIdsProvider`)
///     tant qu'elle est visible à ≥ 90 % **et non lue** (même convention « lu »
///     que `closing_recap.dart` : `isRead` OU `consumedContentIdsProvider`) ;
///   - joue le pulse [AutoGrowPulse] quand le signal cible ce `contentId`.
///
/// Ne porte **aucun** geste : le vrai long-press (aperçu flottant) reste géré
/// par la carte elle-même.
class AutoGrowCandidate extends ConsumerStatefulWidget {
  const AutoGrowCandidate({
    super.key,
    required this.contentId,
    required this.isRead,
    required this.child,
    this.keyPrefix = 'flux',
  });

  final String contentId;

  /// État « lu » porté par le modèle (complété en interne par le set de session
  /// `consumedContentIdsProvider`).
  final bool isRead;

  /// Discrimine la `Key` du `VisibilityDetector` entre surfaces (un même
  /// `contentId` peut apparaître en Essentiel ET en Flux → clés distinctes).
  final String keyPrefix;

  final Widget child;

  @override
  ConsumerState<AutoGrowCandidate> createState() => _AutoGrowCandidateState();
}

class _AutoGrowCandidateState extends ConsumerState<AutoGrowCandidate> {
  // Capturé une fois : `ref` est interdit dans `dispose()` (teardown de l'arbre),
  // mais le `StateController` du provider (non autoDispose) reste stable sur
  // toute la vie du container → utilisable jusqu'au dispose de la carte.
  late final StateController<Set<String>> _visibleNotifier;
  bool _visible = false;
  bool _read = false;

  @override
  void initState() {
    super.initState();
    _visibleNotifier = ref.read(visibleFluxContentIdsProvider.notifier);
  }

  void _reconcile() {
    final current = _visibleNotifier.state;
    final shouldBeIn = _visible && !_read;
    final isIn = current.contains(widget.contentId);
    if (shouldBeIn && !isIn) {
      _visibleNotifier.state = {...current, widget.contentId};
    } else if (!shouldBeIn && isIn) {
      _visibleNotifier.state = {...current}..remove(widget.contentId);
    }
  }

  void _onVisibility(VisibilityInfo info) {
    if (!mounted) return;
    _visible = info.visibleFraction >= 0.9;
    _reconcile();
  }

  @override
  void dispose() {
    // `dispose` peut survenir pendant le build d'un parent (unmount d'un enfant
    // retiré de l'arbre) : muter un provider y est interdit (assertion Riverpod,
    // indépendante de tout `watch`). On diffère donc le retrait en microtask —
    // exécutée une fois le build terminé, et jamais laissée « pending » comme le
    // serait un `Timer`. Si le container est détruit entre-temps, l'accès lève et
    // on ignore (plus rien à nettoyer).
    final notifier = _visibleNotifier;
    final id = widget.contentId;
    scheduleMicrotask(() {
      try {
        final current = notifier.state;
        if (current.contains(id)) {
          notifier.state = {...current}..remove(id);
        }
      } catch (_) {
        // ProviderScope déjà disposé : rien à retirer.
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wasRead = _read;
    _read = widget.isRead ||
        ref.watch(
          consumedContentIdsProvider
              .select((ids) => ids.contains(widget.contentId)),
        );
    // L'état lu peut basculer pendant que la carte reste visible (mark-as-read
    // in place) → réconcilie l'appartenance au set après la frame, mais
    // seulement quand « lu » change vraiment (la visibilité, elle, est déjà
    // réconciliée directement par `_onVisibility`).
    if (_read != wasRead) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reconcile();
      });
    }

    final playToken = ref.watch(
      autoGrowNudgeSignalProvider.select(
        (s) => s?.contentId == widget.contentId ? s!.nonce : null,
      ),
    );
    return VisibilityDetector(
      key: Key('autogrow_vis_${widget.keyPrefix}_${widget.contentId}'),
      onVisibilityChanged: _onVisibility,
      child: AutoGrowPulse(playToken: playToken, child: widget.child),
    );
  }
}
