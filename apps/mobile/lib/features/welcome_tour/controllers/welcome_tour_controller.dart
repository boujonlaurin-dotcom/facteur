import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signal éphémère émis par le controller à la clôture du tour. Consommé
/// par le host pour :
///   - appeler `AuthStateNotifier.markWelcomeTourSeen()` (persist la clé)
///   - naviguer vers `/digest` ou `/digest?first=true` selon le signal
enum WelcomeTourFinishSignal { none, plain, firstDigest }

/// État du Welcome Tour v2 : spotlight coachmark guidé sur 3 écrans réels
/// (Essentiel → Feed → Paramètres).
///
/// - `active=false` : tour non affiché (pas encore démarré ou déjà terminé).
/// - `active=true` + `currentStep=0..2` : tour en cours, le `WelcomeTourHost`
///   navigue vers l'écran correspondant et affiche l'overlay.
@immutable
class WelcomeTourState {
  final bool active;
  final int currentStep;

  const WelcomeTourState({this.active = false, this.currentStep = 0});

  WelcomeTourState copyWith({bool? active, int? currentStep}) =>
      WelcomeTourState(
        active: active ?? this.active,
        currentStep: currentStep ?? this.currentStep,
      );
}

/// Pure state-machine pour le tour. Les side-effects (persistance seen,
/// navigation) sont volontairement laissés au `WelcomeTourHost` qui écoute
/// le `welcomeTourFinishSignalProvider`.
class WelcomeTourController extends StateNotifier<WelcomeTourState> {
  WelcomeTourController(this._ref) : super(const WelcomeTourState());

  final Ref _ref;
  static const int totalSteps = 3;

  /// Démarre le tour si pas déjà actif. No-op sinon.
  void start() {
    if (state.active) return;
    state = const WelcomeTourState(active: true, currentStep: 0);
  }

  /// Passe à l'étape suivante, ou finalise si dernière étape.
  void next() {
    if (!state.active) return;
    if (state.currentStep >= totalSteps - 1) {
      finish(firstDigest: true);
      return;
    }
    state = state.copyWith(currentStep: state.currentStep + 1);
  }

  /// Skip depuis n'importe quelle étape : ferme le tour avec navigation plain.
  void skip() => finish(firstDigest: false);

  /// Finalise le tour : désactive l'état et émet le signal de clôture.
  ///
  /// `firstDigest=true` → host naviguera vers `/digest?first=true` pour
  /// déclencher le `DigestWelcomeModal` existant. Sinon, `/digest` simple.
  void finish({required bool firstDigest}) {
    if (!state.active) return;
    state = const WelcomeTourState(active: false, currentStep: 0);
    _ref.read(welcomeTourFinishSignalProvider.notifier).state = firstDigest
        ? WelcomeTourFinishSignal.firstDigest
        : WelcomeTourFinishSignal.plain;
  }
}

/// Signal éphémère lu par le `WelcomeTourHost` après finish/skip pour
/// effectuer la persistance seen + la navigation. Le host remet la valeur
/// à `none` après consommation.
final welcomeTourFinishSignalProvider =
    StateProvider<WelcomeTourFinishSignal>(
        (ref) => WelcomeTourFinishSignal.none);

final welcomeTourControllerProvider =
    StateNotifierProvider<WelcomeTourController, WelcomeTourState>(
  (ref) => WelcomeTourController(ref),
);
