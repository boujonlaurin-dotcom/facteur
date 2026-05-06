import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../repositories/feed_repository.dart';

final tabCountsProvider = FutureProvider.autoDispose<TabCounts>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final repo = FeedRepository(apiClient);
  return repo.getTabCounts();
});
