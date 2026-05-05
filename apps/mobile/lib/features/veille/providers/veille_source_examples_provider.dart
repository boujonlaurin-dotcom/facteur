import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/veille_delivery.dart';
import 'veille_repository_provider.dart';

/// Renvoie ≤2 exemples d'articles récents pour une source donnée — Step 3
/// du flow (preview inline). `autoDispose` car éphémère par expand.
final veilleSourceExamplesProvider = FutureProvider.autoDispose
    .family<List<VeilleSourceExample>, String>((ref, sourceId) async {
  final repo = ref.read(veilleRepositoryProvider);
  return repo.getSourceExamples(sourceId);
});
