import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/feed_repository.dart';
import 'feed_provider.dart';

final tabCountsProvider = FutureProvider.autoDispose<TabCounts>((ref) async {
  final repo = ref.watch(feedRepositoryProvider);
  return repo.getTabCounts();
});
