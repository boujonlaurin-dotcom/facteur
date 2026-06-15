import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart';

/// Fetches today's articles for [themeSlug] including sources the user does
/// **not** follow yet — backs the "Explorer de nouvelles sources" block at
/// the bottom of [ThemeSectionScreen].
///
/// The filtering (`isFollowedSource == false`) and dedup against the section
/// already on screen happens in the UI layer: this keeps the provider
/// stateless and trivial to test, and avoids coupling it to the current
/// `fluxContinuProvider` snapshot.
final themeDiscoveryProvider =
    FutureProvider.family.autoDispose<List<Content>, String>(
  (ref, themeSlug) async {
    final repo = ref.watch(feedRepositoryProvider);
    final resp = await repo.getFeed(
      theme: themeSlug,
      includeUnfollowed: true,
      page: 1,
      limit: 20,
    );
    return resp.items;
  },
);
