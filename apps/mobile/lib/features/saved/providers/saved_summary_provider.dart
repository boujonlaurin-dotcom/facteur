import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../models/collection_model.dart';
import 'collections_provider.dart';

/// Provider pour le résumé des sauvegardes (utilisé par les nudges).
final savedSummaryProvider = FutureProvider<SavedSummary>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (!authState.isAuthenticated) return SavedSummary();

  final repo = ref.read(collectionsRepositoryProvider);
  return repo.getSavedSummary();
});
