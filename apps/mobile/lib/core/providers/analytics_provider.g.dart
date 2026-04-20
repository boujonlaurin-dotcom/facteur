// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analytics_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$posthogServiceHash() => r'c52a2c31e624342f05c7a83772ca8fa2f7c501e5';

/// PostHog wrapper — keepAlive so identify/reset calls persist across rebuilds.
///
/// Copied from [posthogService].
@ProviderFor(posthogService)
final posthogServiceProvider = Provider<PostHogService>.internal(
  posthogService,
  name: r'posthogServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$posthogServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef PosthogServiceRef = ProviderRef<PostHogService>;
String _$analyticsServiceHash() => r'ce5011ca427202ed88c7e0a870ad1c06c4944912';

/// See also [analyticsService].
@ProviderFor(analyticsService)
final analyticsServiceProvider = Provider<AnalyticsService>.internal(
  analyticsService,
  name: r'analyticsServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$analyticsServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AnalyticsServiceRef = ProviderRef<AnalyticsService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
