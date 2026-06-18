// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guided_tour_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$guidedTourControllerHash() =>
    r'e8af36b7ec64fd7e0426f0e42682726bdfea0ee3';

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
///
/// Copied from [GuidedTourController].
@ProviderFor(GuidedTourController)
final guidedTourControllerProvider =
    NotifierProvider<GuidedTourController, TourStep?>.internal(
  GuidedTourController.new,
  name: r'guidedTourControllerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$guidedTourControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$GuidedTourController = Notifier<TourStep?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
