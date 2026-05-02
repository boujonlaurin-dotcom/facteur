import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../repositories/veille_repository.dart';

final veilleRepositoryProvider = Provider<VeilleRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return VeilleRepository(apiClient);
});
