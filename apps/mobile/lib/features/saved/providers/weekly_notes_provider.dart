import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart';

/// Provider for articles with notes from the last 7 days.
/// Used by "Tes pensées de la semaine" section on SavedScreen.
final weeklyNotesProvider = FutureProvider<List<Content>>((ref) async {
  final repository = ref.read(feedRepositoryProvider);
  final response = await repository.getFeed(
    page: 1,
    limit: 10,
    savedOnly: true,
    hasNote: true,
  );

  final weekAgo = DateTime.now().subtract(const Duration(days: 7));
  return response.items
      .where(
          (c) => c.noteUpdatedAt != null && c.noteUpdatedAt!.isAfter(weekAgo))
      .toList();
});
