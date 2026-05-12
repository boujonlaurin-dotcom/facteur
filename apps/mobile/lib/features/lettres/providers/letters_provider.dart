import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../models/letter_progress.dart';
import 'letters_repository_provider.dart';

class LettersNotifier extends AsyncNotifier<LetterProgressState> {
  @override
  Future<LetterProgressState> build() async {
    final auth = ref.watch(authStateProvider);
    if (!auth.isAuthenticated) {
      return const LetterProgressState.empty();
    }
    final letters = await ref.read(lettersRepositoryProvider).getLetters();
    return LetterProgressState(letters: letters);
  }

  Future<AsyncValue<LetterProgressState>> _fetchState() =>
      AsyncValue.guard(() async {
        final letters = await ref.read(lettersRepositoryProvider).getLetters();
        return LetterProgressState(letters: letters);
      });

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await _fetchState();
  }

  Future<void> silentRefresh() async {
    final fresh = await _fetchState();
    if (fresh is AsyncData<LetterProgressState>) {
      state = fresh;
    }
  }

  Future<void> refreshLetterStatus(String letterId) async {
    final updated =
        await ref.read(lettersRepositoryProvider).refreshStatus(letterId);
    final current = state.valueOrNull ?? const LetterProgressState.empty();
    final next = current.letters
        .map((l) => l.id == letterId ? updated : l)
        .toList(growable: false);
    state = AsyncData(LetterProgressState(letters: next));
  }
}

final lettersProvider =
    AsyncNotifierProvider<LettersNotifier, LetterProgressState>(
  LettersNotifier.new,
);
