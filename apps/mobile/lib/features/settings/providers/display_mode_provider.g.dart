// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'display_mode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$displayModeSpecHash() => r'95a11cba914ff6655eae3d9acdcb19c507f1496e';

/// Spec du mode courant — c'est ce provider que les cartes et le provider
/// Flux Continu watchent (recomposition automatique au changement de mode).
///
/// Copied from [displayModeSpec].
@ProviderFor(displayModeSpec)
final displayModeSpecProvider = AutoDisposeProvider<DisplayModeSpec>.internal(
  displayModeSpec,
  name: r'displayModeSpecProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$displayModeSpecHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef DisplayModeSpecRef = AutoDisposeProviderRef<DisplayModeSpec>;
String _$displayModeNotifierHash() =>
    r'feabb077ef7d30fc6969d549c745fceae38adbfd';

/// See also [DisplayModeNotifier].
@ProviderFor(DisplayModeNotifier)
final displayModeNotifierProvider =
    AutoDisposeNotifierProvider<DisplayModeNotifier, DisplayMode>.internal(
  DisplayModeNotifier.new,
  name: r'displayModeNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$displayModeNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$DisplayModeNotifier = AutoDisposeNotifier<DisplayMode>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
