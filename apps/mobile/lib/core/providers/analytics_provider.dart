import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:facteur/core/api/api_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';

part 'analytics_provider.g.dart';

@Riverpod(keepAlive: true)
AnalyticsService analyticsService(AnalyticsServiceRef ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AnalyticsService(apiClient);
}
