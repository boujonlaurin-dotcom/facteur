import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_state.dart';
import '../models/tour_step.dart';
import '../tour_ids.dart';

part 'guided_tour_controller.g.dart';

/// Machine à états du tour guidé post-onboarding.
///
/// Vit au niveau application (`keepAlive`) pour survivre aux changements
/// d'onglet et à l'ouverture/fermeture de feuilles pendant le tour. Le notifier
/// **ne touche jamais à `BuildContext`** : tous les effets de bord (navigation,
/// ouverture de feuille, scroll) sont exécutés par [GuidedTourBridge], monté au
/// niveau racine et stable, qui écoute cet état.
///
/// `null` = inactif. La séquence jouée est :
/// `essentielHero → descendsCartes → favorisSheet → flaner → reglages →
/// courrier → done`. [skip] et [finish]/`next()` sur la dernière étape mènent
/// tous deux à [TourStep.done], persistent le flag « vu » et tirent `onComplete`
/// **une seule fois** (rend la main au flow des modales post-onboarding).
@Riverpod(keepAlive: true)
class GuidedTourController extends _$GuidedTourController {
  VoidCallback? _onComplete;
  bool _completed = false;
  bool _starting = false;

  /// Clé `nudge.<id>.seen.<userId>` — alignée sur `NudgeStorage._userSeenKey`
  /// pour partager la sémantique scopée-user (un second compte revoit le tour).
  String _seenKey(String userId) =>
      'nudge.${TourIds.guidedTour}.seen.$userId';

  String get _currentUserId =>
      ref.read(authStateProvider).user?.id ?? 'anonymous';

  @override
  TourStep? build() => null;

  /// Démarre le tour s'il n'a jamais été vu par l'utilisateur courant. Dans tous
  /// les cas, [onComplete] finit par être appelé **exactement une fois** : soit
  /// immédiatement (tour déjà vu), soit à la fin du tour ([finish]/[skip]).
  ///
  /// Idempotent : un second appel pendant qu'un tour tourne est ignoré.
  Future<void> start({required VoidCallback onComplete}) async {
    if (_starting || state != null) return;
    _starting = true;
    _onComplete = onComplete;
    _completed = false;

    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_seenKey(_currentUserId)) ?? false;
    if (seen) {
      _starting = false;
      _fireComplete();
      return;
    }
    _starting = false;
    state = TourStep.essentielHero;
  }

  /// Avance d'une étape ; sur la dernière ([TourStep.courrier]), termine.
  void next() {
    switch (state) {
      case TourStep.essentielHero:
        state = TourStep.descendsCartes;
      case TourStep.descendsCartes:
        state = TourStep.favorisSheet;
      case TourStep.favorisSheet:
        state = TourStep.flaner;
      case TourStep.flaner:
        state = TourStep.reglages;
      case TourStep.reglages:
        state = TourStep.courrier;
      case TourStep.courrier:
        finish();
      case TourStep.done:
      case null:
        break;
    }
  }

  /// « Passer » — saute directement à la conclusion.
  void skip() => finish();

  /// Termine le tour : carte de conclusion, persistance du flag, `onComplete`.
  void finish() {
    if (state == null || state == TourStep.done) return;
    state = TourStep.done;
    unawaited(_markSeen());
    _fireComplete();
  }

  /// Retire la carte de conclusion (appelé par le bridge après son délai
  /// d'affichage). Idempotent. `onComplete` a déjà été tiré par [finish].
  void dismiss() {
    state = null;
  }

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey(_currentUserId), true);
  }

  void _fireComplete() {
    if (_completed) return;
    _completed = true;
    final cb = _onComplete;
    _onComplete = null;
    cb?.call();
  }
}
