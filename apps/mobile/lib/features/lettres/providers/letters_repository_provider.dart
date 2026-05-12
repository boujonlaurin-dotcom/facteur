import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../repositories/letters_repository.dart';

final lettersRepositoryProvider = Provider<LettersRepository>((ref) {
  return LettersRepository(ref.watch(apiClientProvider));
});
