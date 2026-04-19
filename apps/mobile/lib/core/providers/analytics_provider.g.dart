// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analytics_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$posthogServiceHash() => r'1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b';

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

String _$analyticsServiceHash() => r'975e641a9ba922fe426408c6eec15e7fb24d7b4f';

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
