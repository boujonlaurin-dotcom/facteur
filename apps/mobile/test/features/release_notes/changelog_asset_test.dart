import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde-fou sur l'asset changelog **bundlé** (pas un stub).
///
/// Une fusion qui colle deux entrées en un seul objet malformé (virgule
/// manquante / clés dupliquées, cf. corruption introduite par #881) casse
/// silencieusement le parsing de la modal « Quoi de neuf » en prod. Ce test
/// échoue dès que `assets/changelog.json` n'est plus un JSON valide et bien
/// formé.
void main() {
  test('bundled changelog.json is valid JSON', () {
    final raw = File('assets/changelog.json').readAsStringSync();
    expect(() => jsonDecode(raw), returnsNormally);
  });

  test('every unreleased entry has a non-empty summary', () {
    final decoded =
        jsonDecode(File('assets/changelog.json').readAsStringSync())
            as Map<String, dynamic>;

    final unreleased = decoded['unreleased'] as List<dynamic>;
    expect(unreleased, isNotEmpty);
    for (final entry in unreleased) {
      final map = entry as Map<String, dynamic>;
      expect(map['summary'], isA<String>(),
          reason: 'chaque entrée unreleased doit porter un summary (string)');
      expect((map['summary'] as String).trim(), isNotEmpty);
    }
  });

  test('every released block is well-formed', () {
    final decoded =
        jsonDecode(File('assets/changelog.json').readAsStringSync())
            as Map<String, dynamic>;

    final released = decoded['released'] as List<dynamic>;
    for (final release in released) {
      final map = release as Map<String, dynamic>;
      expect(map['version'], isA<String>());
      expect(map['entries'], isA<List<dynamic>>());
    }
  });
}
