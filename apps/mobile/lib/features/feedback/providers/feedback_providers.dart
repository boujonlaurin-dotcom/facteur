import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_provider.dart';
import '../models/feedback_models.dart';
import '../repositories/feedback_repository.dart';

/// Provider du repository de feedback (Epic 13).
final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return FeedbackRepository(apiClient);
});

/// Statut de l'invitation au call (gating segmenté côté backend).
///
/// Lu par la carte de fin de tournée pour décider si le CTA d'invitation
/// au call doit s'afficher. Renvoie `hidden()` en cas d'erreur (jamais d'appel
/// imposé).
final inviteStatusProvider = FutureProvider<FeedbackInviteStatus>((ref) async {
  return ref.read(feedbackRepositoryProvider).getInviteStatus();
});
