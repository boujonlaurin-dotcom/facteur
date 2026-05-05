import 'package:flutter/foundation.dart';

import 'letter.dart';

@immutable
class LetterProgressState {
  final List<Letter> letters;

  const LetterProgressState({required this.letters});

  const LetterProgressState.empty() : letters = const [];

  Letter? get activeLetter {
    for (final l in letters) {
      if (l.status == LetterStatus.active) return l;
    }
    return null;
  }
}
